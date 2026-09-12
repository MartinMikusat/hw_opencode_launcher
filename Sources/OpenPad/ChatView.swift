import SwiftUI

struct ChatView: View {
    @ObservedObject var model: ChatModel
    @State private var query = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if model.directory == nil {
                pickerBody
            } else {
                chatBody
            }
        }
        .background(.regularMaterial)
        .onExitCommand { model.onEscape?() }
        .onAppear { inputFocused = true }
    }

    // MARK: directory picker

    private var pickerBody: some View {
        VStack(spacing: 0) {
            TextField("Where should it work? (folder name or path)", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding(14)
                .focused($inputFocused)
                .onSubmit { resolveQuery() }
            Divider()
            List {
                let recents = filteredRecents
                if !recents.isEmpty {
                    Section("Recent") {
                        ForEach(recents, id: \.directory) { entry in
                            dirRow(
                                path: entry.directory,
                                detail: entry.lastTask.isEmpty
                                    ? entry.directory
                                    : "\(entry.lastTask) · \(entry.directory)"
                            )
                        }
                    }
                }
                Section("Folders") {
                    ForEach(DirectoryResolver.candidates(matching: query).prefix(8), id: \.self) { path in
                        dirRow(path: path, detail: path)
                    }
                }
            }
            .listStyle(.plain)
            HStack {
                if !model.statusLine.isEmpty {
                    Text(model.statusLine).foregroundStyle(.red).font(.callout)
                }
                Spacer()
                Button("Browse…") { browse() }
                    .keyboardShortcut("b", modifiers: .command)
            }
            .padding(10)
        }
    }

    private var filteredRecents: [ServerEntry] {
        let recents = Registry.shared.recents
        guard !query.isEmpty else { return recents }
        return recents.filter {
            $0.directory.localizedCaseInsensitiveContains(query)
                || $0.lastTask.localizedCaseInsensitiveContains(query)
        }
    }

    private func dirRow(path: String, detail: String) -> some View {
        Button { model.choose(directory: path) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(path.lastPathComponent).font(.headline)
                Text(detail.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func resolveQuery() {
        if let dir = DirectoryResolver.resolve(query, recents: Registry.shared.recents) {
            model.choose(directory: dir)
        } else if FileManager.default.fileExists(atPath: (query as NSString).expandingTildeInPath) {
            model.choose(directory: (query as NSString).expandingTildeInPath)
        } else {
            model.statusLine = "no folder found for \"\(query)\""
        }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.choose(directory: url.path)
        }
    }

    // MARK: chat

    private var chatBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(model.directory?.lastPathComponent ?? "")
                    .font(.headline)
                Text(model.directory?.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if !model.modelChoices.isEmpty {
                    Picker("Model", selection: $model.selectedModelLabel) {
                        ForEach(model.modelChoices, id: \.label) { c in
                            Text(c.label).tag(Optional(c.label))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
                if !model.agents.isEmpty {
                    Menu {
                        Button("default") { model.selectedAgent = nil }
                        ForEach(model.agents, id: \.self) { a in
                            Button(a) { model.selectedAgent = a }
                        }
                    } label: {
                        Text(model.selectedAgent ?? "agent")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.messages) { msg in
                            messageRow(msg)
                        }
                        if model.busy {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("working…").foregroundStyle(.secondary)
                            }
                            .id("working")
                        }
                    }
                    .padding(12)
                }
                .onChange(of: model.messages.count) {
                    withAnimation { proxy.scrollTo(model.messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: model.busy) {
                    withAnimation { proxy.scrollTo("working", anchor: .bottom) }
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Message…", text: $query, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .onSubmit { send() }
                if model.busy {
                    Button("Stop") { model.abort() }
                        .keyboardShortcut(".", modifiers: .command)
                }
                Button("New") { model.newChat(); query = "" }
                    .keyboardShortcut("n", modifiers: .command)
                Button { model.openInGhostty() } label: {
                    Image(systemName: "terminal")
                }
                .help("Open session in Ghostty")
                .keyboardShortcut("o", modifiers: .command)
            }
            .padding(10)
            if !model.statusLine.isEmpty {
                Text(model.statusLine)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.bottom, 6)
            }
        }
        .onAppear { inputFocused = true }
    }

    private func messageRow(_ msg: ChatModel.Msg) -> some View {
        VStack(alignment: msg.role == "user" ? .trailing : .leading, spacing: 4) {
            if msg.role == "user" {
                Text(msg.text)
                    .padding(8)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                let body = msg.text
                if body.isEmpty {
                    Text("*(done — \(msg.toolCount) tool call\(msg.toolCount == 1 ? "" : "s")\(msg.errorCount > 0 ? ", \(msg.errorCount) errors" : ""))*")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    Text(LocalizedStringKey(body))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: msg.role == "user" ? .trailing : .leading)
        .id(msg.id)
    }

    private func send() {
        let text = query
        query = ""
        model.send(text)
    }
}
