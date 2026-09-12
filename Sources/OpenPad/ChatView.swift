import SwiftUI

/// Strict monochrome palette — shades of grey only; red reserved for errors.
private enum Ink {
    static let bg = Color(white: 0.075)
    static let fill = Color.white.opacity(0.07)
    static let fillHover = Color.white.opacity(0.11)
    static let hairline = Color.white.opacity(0.10)
    static let text = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.36)
    static let error = Color(red: 0.95, green: 0.35, blue: 0.35)
}

struct ChatView: View {
    @ObservedObject var model: ChatModel
    @State private var query = ""
    @State private var hoveredDir: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if model.directory == nil {
                pickerBody
            } else {
                chatBody
            }
        }
        .background(Ink.bg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Ink.hairline, lineWidth: 0.5)
        )
        .preferredColorScheme(.dark)
        .onExitCommand { model.onEscape?() }
        .onChange(of: model.directory) { query = "" }
    }

    // MARK: directory picker

    private var pickerBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Ink.tertiary)
                TextField("Where should it work?", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Ink.text)
                    .focused($inputFocused)
                    .onSubmit { resolveQuery() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            hairline
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let recents = filteredRecents
                    if !recents.isEmpty {
                        sectionHeader("Recent")
                        ForEach(recents, id: \.directory) { entry in
                            dirRow(
                                path: entry.directory,
                                detail: entry.lastTask.isEmpty ? nil : entry.lastTask
                            )
                        }
                    }
                    let folders = DirectoryResolver.candidates(matching: query)
                    if !folders.isEmpty {
                        sectionHeader("Folders")
                        ForEach(folders.prefix(8), id: \.self) { path in
                            dirRow(path: path, detail: nil)
                        }
                    }
                    if recents.isEmpty && folders.isEmpty {
                        Text("No matching folders — press ⏎ to try Spotlight, or ⌘B to browse")
                            .font(.callout)
                            .foregroundStyle(Ink.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            hairline
            HStack {
                if !model.statusLine.isEmpty {
                    Text(model.statusLine).foregroundStyle(Ink.error).font(.callout)
                }
                Spacer()
                ghostButton("Browse…", systemImage: "folder") { browse() }
                    .keyboardShortcut("b", modifiers: .command)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Ink.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private func dirRow(path: String, detail: String?) -> some View {
        let hovered = hoveredDir == path
        return Button { model.choose(directory: path) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(path.lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.text)
                    Text(detail ?? path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.tertiary)
                    .opacity(hovered ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hovered ? Ink.fill : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredDir = $0 ? path : nil }
    }

    private func resolveQuery() {
        if let dir = DirectoryResolver.resolve(query, recents: Registry.shared.recents) {
            model.choose(directory: dir)
        } else if FileManager.default.fileExists(atPath: query.expandingTildeInPath) {
            model.choose(directory: query.expandingTildeInPath)
        } else {
            model.statusLine = "No folder found for “\(query)” — use ⌘B to browse"
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
            HStack(spacing: 10) {
                Text(model.directory?.lastPathComponent ?? "")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.text)
                Text(model.directory?.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                if !model.modelChoices.isEmpty {
                    Menu {
                        Button(model.defaultModelName.isEmpty ? "server default" : "default (\(model.defaultModelName))") {
                            model.selectedModelLabel = nil
                        }
                        Divider()
                        ForEach(model.modelChoices, id: \.label) { c in
                            Button(c.label) { model.selectedModelLabel = c.label }
                        }
                    } label: {
                        pickerLabel(model.selectedModelLabel ?? (model.defaultModelName.isEmpty ? "model" : model.defaultModelName))
                    }
                }
                if !model.agents.isEmpty {
                    Menu {
                        Button("default") { model.selectedAgent = nil }
                        ForEach(model.agents, id: \.self) { a in
                            Button(a) { model.selectedAgent = a }
                        }
                    } label: {
                        pickerLabel(model.selectedAgent ?? "agent")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            hairline
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.connecting {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small).tint(Ink.secondary)
                                Text("connecting…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Ink.secondary)
                            }
                        }
                        ForEach(model.messages) { msg in
                            messageRow(msg)
                        }
                        if model.busy {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small).tint(Ink.secondary)
                                Text("working…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Ink.secondary)
                            }
                            .id("working")
                        }
                    }
                    .padding(14)
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.messages.count) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(model.messages.last?.id, anchor: .bottom)
                    }
                }
                .onChange(of: model.busy) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("working", anchor: .bottom)
                    }
                }
            }
            hairline
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message…", text: $query, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.text)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .onSubmit { send() }
                if model.busy {
                    iconButton("stop.fill", help: "Stop (⌘.)") { model.abort() }
                        .keyboardShortcut(".", modifiers: .command)
                }
                iconButton("plus", help: "New chat (⌘N)") { model.newChat(); query = "" }
                    .keyboardShortcut("n", modifiers: .command)
                iconButton("terminal", help: "Open in Ghostty (⌘O)") { model.openInGhostty() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            if !model.statusLine.isEmpty {
                Text(model.statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.error)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
        }
        // Focus must be deferred: the picker TextField sharing this FocusState is
        // removed in the same update, and its removal clears the value again.
        .onAppear { DispatchQueue.main.async { inputFocused = true } }
    }

    private var hairline: some View {
        Rectangle().fill(Ink.hairline).frame(height: 0.5)
    }

    private func pickerLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(Ink.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Ink.fill)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func iconButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Ink.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func ghostButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Ink.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Ink.fill)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func messageRow(_ msg: ChatModel.Msg) -> some View {
        VStack(alignment: msg.role == "user" ? .trailing : .leading, spacing: 4) {
            if msg.role == "user" {
                Text(msg.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Ink.fillHover)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if msg.text.isEmpty {
                if !model.busy {
                    Text("done — \(msg.toolCount) tool call\(msg.toolCount == 1 ? "" : "s")\(msg.errorCount > 0 ? ", \(msg.errorCount) errors" : "")")
                        .font(.system(size: 12))
                        .italic()
                        .foregroundStyle(Ink.tertiary)
                }
            } else {
                Text(LocalizedStringKey(msg.text))
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .foregroundStyle(Ink.text)
                    .textSelection(.enabled)
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
