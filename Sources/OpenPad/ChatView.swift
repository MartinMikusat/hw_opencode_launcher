import AppKit
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
    @FocusState private var inputFocused: Bool

    var body: some View {
        chatBody
        .background(Ink.bg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Ink.hairline, lineWidth: 0.5)
        )
        .preferredColorScheme(.dark)
        .onExitCommand {
            // Esc stops the agent first; a second Esc (once idle) hides the panel.
            if model.busy { model.abort() } else { model.onEscape?() }
        }
    }

    // MARK: chat

    private var chatBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("~")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.secondary)
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
                    // Return sends; Shift+Return inserts a newline. The field
                    // editor owns the text while editing, so insert into it
                    // directly — writing to `query` gets clobbered and letting
                    // the event fall through selects-all and eats the text.
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) || NSEvent.modifierFlags.contains(.shift) {
                            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                                editor.insertText("\n", replacementRange: editor.selectedRange())
                            }
                            return .handled
                        }
                        send()
                        return .handled
                    }
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
            .padding(.top, 1)
            .padding(.bottom, 11)
            if !model.statusLine.isEmpty {
                Text(model.statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.error)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
        }
        // Defer so the field editor is attached before grabbing focus.
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
            } else {
                ForEach(msg.order, id: \.self) { partID in
                    if let text = msg.texts[partID], !text.isEmpty {
                        Text(LocalizedStringKey(text))
                            .font(.system(size: 13))
                            .lineSpacing(2)
                            .foregroundStyle(Ink.text)
                            .textSelection(.enabled)
                    } else if let tool = msg.tools.first(where: { $0.id == partID }) {
                        toolRow(tool)
                    }
                }
                if msg.stopped {
                    Text("stopped")
                        .font(.system(size: 12))
                        .italic()
                        .foregroundStyle(Ink.tertiary)
                } else if msg.text.isEmpty, !model.busy {
                    Text("done — \(msg.toolCount) tool call\(msg.toolCount == 1 ? "" : "s")\(msg.errorCount > 0 ? ", \(msg.errorCount) errors" : "")")
                        .font(.system(size: 12))
                        .italic()
                        .foregroundStyle(Ink.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: msg.role == "user" ? .trailing : .leading)
        .id(msg.id)
    }

    private func toolRow(_ tool: (id: String, name: String, detail: String?, status: String)) -> some View {
        HStack(spacing: 6) {
            Text(tool.name)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            if let detail = tool.detail, !detail.isEmpty {
                Text(detail.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if tool.status == "running" || tool.status == "pending" {
                ProgressView().controlSize(.mini)
            }
        }
        .foregroundStyle(tool.status == "error" ? Ink.error : Ink.tertiary)
    }

    private func send() {
        let text = query
        query = ""
        model.send(text)
    }
}
