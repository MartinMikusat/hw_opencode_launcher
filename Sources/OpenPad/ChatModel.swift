import AppKit
import Foundation
import UserNotifications

@MainActor
final class ChatModel: ObservableObject {
    struct Msg: Identifiable {
        let id: String
        var role: String
        var order: [String] = []
        var texts: [String: String] = [:] // partID → text
        var toolCount = 0
        var errorCount = 0
        var text: String { order.compactMap { texts[$0] }.joined(separator: "\n") }
    }

    @Published var directory: String?
    @Published var messages: [Msg] = []
    @Published var busy = false
    @Published var statusLine = ""
    @Published var sessionID: String?
    @Published var modelChoices: [(label: String, providerID: String, modelID: String)] = []
    @Published var selectedModelLabel: String?
    @Published var defaultModelName = ""
    @Published var agents: [String] = []
    @Published var selectedAgent: String?
    @Published var connecting = false

    var serverURL = ""
    var panelVisible = true
    var onEscape: (() -> Void)?
    /// Called when a busy session goes idle while the panel is hidden.
    var onIdleWhileHidden: ((String) -> Void)?

    private var client: OpencodeClient?
    private var port = 0
    private var queuedText: String?
    private var eventTask: Task<Void, Never>?
    private var lastEventDirectory: String?
    /// Optimistic user messages we inserted locally; the server echoes the real
    /// message back over SSE — we hide that echo instead of rendering twice.
    private var pendingLocalIDs = Set<String>()
    private var hiddenMessageIDs = Set<String>()

    // MARK: directory + server

    func choose(directory: String) {
        let dir = (directory as NSString).expandingTildeInPath
        self.directory = dir
        sessionID = nil
        messages = []
        pendingLocalIDs = []
        hiddenMessageIDs = []
        statusLine = ""
        connecting = true
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            do {
                let (client, port) = try await ServerManager.ensureServer(directory: dir)
                guard let self, !Task.isCancelled else { return }
                self.client = client
                self.port = port
                self.serverURL = "http://127.0.0.1:\(port)"
                self.connecting = false
                Registry.shared.record(directory: dir, port: port)
                await self.loadPickers()
                self.streamEvents(client: client, for: dir)
                if let queued = self.queuedText {
                    self.queuedText = nil
                    self.send(queued)
                }
            } catch {
                guard let self else { return }
                self.connecting = false
                self.directory = nil
                self.statusLine = error.localizedDescription
            }
        }
    }

    private func loadPickers() async {
        guard let client else { return }
        if let config = try? await client.config(), let model = config.model {
            defaultModelName = String(model.split(separator: "/").last ?? "")
        }
        if let res = try? await client.providers() {
            var choices: [(label: String, providerID: String, modelID: String)] = []
            for p in res.providers {
                for (id, m) in p.models {
                    choices.append((label: "\(p.id)/\(m.name)", providerID: p.id, modelID: id))
                }
            }
            modelChoices = choices
        }
        if let list = try? await client.agents() {
            agents = list.filter { $0.hidden != true }.map(\.name)
        }
    }

    // MARK: events

    private func streamEvents(client: OpencodeClient, for dir: String) {
        lastEventDirectory = dir
        Task { [weak self] in
            do {
                for try await event in client.eventStream() {
                    guard let self, !Task.isCancelled else { return }
                    self.handle(event)
                }
            } catch {
                if !Task.isCancelled {
                    self?.statusLine = "event stream lost"
                }
            }
        }
    }

    private func handle(_ event: ServerEvent) {
        switch event {
        case let .messageUpdated(info):
            guard info.sessionID == sessionID else { return }
            if info.role == "user" {
                // message.updated fires repeatedly — skip all updates for an
                // echo we already hid, and match it only once against a pending
                // optimistic local message.
                if hiddenMessageIDs.contains(info.id) { return }
                if !pendingLocalIDs.isEmpty {
                    pendingLocalIDs.removeFirst()
                    hiddenMessageIDs.insert(info.id)
                    messages.removeAll { $0.id == info.id }
                    return
                }
            }
            upsert(id: info.id) { $0.role = info.role }
        case let .partUpdated(part):
            guard sessionID != nil, !hiddenMessageIDs.contains(part.messageID) else { return }
            upsert(id: part.messageID) { msg in
                switch part {
                case let .text(id, _, text):
                    if !msg.order.contains(id) { msg.order.append(id) }
                    msg.texts[id] = text
                case let .tool(_, _, _, status):
                    if status == "completed" { msg.toolCount += 1 }
                    if status == "error" { msg.errorCount += 1 }
                default:
                    break
                }
            }
        case let .sessionStatus(sid, status):
            guard sid == sessionID else { return }
            busy = status == "busy" || status == "retry"
        case let .sessionIdle(sid):
            guard sid == sessionID else { return }
            let wasBusy = busy
            busy = false
            if wasBusy && !panelVisible {
                onIdleWhileHidden?(lastReplyPreview())
            }
        case let .permissionAsked(p):
            guard p.sessionID == sessionID else { return }
            askPermission(p)
        case .other:
            break
        }
    }

    private func upsert(id: String, _ mutate: (inout Msg) -> Void) {
        if let i = messages.firstIndex(where: { $0.id == id }) {
            mutate(&messages[i])
        } else {
            var m = Msg(id: id, role: "assistant")
            mutate(&m)
            messages.append(m)
        }
    }

    private func lastReplyPreview() -> String {
        messages.last(where: { $0.role != "user" })?.text
            .components(separatedBy: .newlines).first
            .map { String($0.prefix(100)) } ?? "task finished"
    }

    private func askPermission(_ p: Permission) {
        let alert = NSAlert()
        alert.messageText = "opencode asks permission"
        alert.informativeText = p.title
        alert.addButton(withTitle: "Allow Once")
        alert.addButton(withTitle: "Allow Always")
        alert.addButton(withTitle: "Reject")
        let r = alert.runModal()
        let response = r == .alertFirstButtonReturn ? "once" : r == .alertSecondButtonReturn ? "always" : "reject"
        Task { try? await client?.respondPermission(sessionID: p.sessionID, permissionID: p.id, response: response) }
    }

    // MARK: actions

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, directory != nil else { return }
        guard let client else {
            queuedText = text // still connecting — send once the server is up
            return
        }
        let dir = directory!
        Task {
            do {
                if sessionID == nil {
                    let s = try await client.createSession(title: String(text.prefix(60)))
                    sessionID = s.id
                    Registry.shared.record(directory: dir, port: port, task: s.title)
                }
                guard let sid = sessionID else { return }
                let userID = "local_\(UUID().uuidString)"
                pendingLocalIDs.insert(userID)
                upsert(id: userID) { m in
                    m.role = "user"
                    m.order = ["t"]
                    m.texts = ["t": text]
                }
                busy = true
                let model = selectedModelLabel
                    .flatMap { l in modelChoices.first(where: { $0.label == l }) }
                    .map { OpencodeClient.PromptBody.Model(providerID: $0.providerID, modelID: $0.modelID) }
                try await client.promptAsync(sessionID: sid, text: text, model: model, agent: selectedAgent)
            } catch {
                busy = false
                statusLine = error.localizedDescription
            }
        }
    }

    func abort() {
        guard let sid = sessionID else { return }
        Task { try? await client?.abort(sessionID: sid) }
    }

    func newChat() {
        sessionID = nil
        messages = []
        pendingLocalIDs = []
        hiddenMessageIDs = []
    }

    func openInGhostty() {
        guard !serverURL.isEmpty, let dir = directory else { return }
        guard let bin = ServerManager.findBinary() else { return }
        Process.launchedProcess(launchPath: "/usr/bin/open", arguments: [
            "-na", "Ghostty", "--args", "-e", "/bin/zsh", "-lc",
            "cd \(dir.shellEscaped) && \(bin.shellEscaped) attach \(serverURL)",
        ])
    }
}


