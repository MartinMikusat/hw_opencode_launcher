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
    @State private var modelSearch = ""
    @State private var showModelPicker = false
    @State private var hoveredModel: String?
    /// 0 = the server-default row; 1... = filteredModelChoices[i-1].
    @State private var modelHighlight = 0
    @FocusState private var inputFocused: Bool
    @FocusState private var searchFocused: Bool

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
            // Esc closes the picker, then stops the agent, then hides the panel.
            if showModelPicker { showModelPicker = false }
            else if model.busy { model.abort() }
            else { model.onEscape?() }
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
                    Button { showModelPicker.toggle() } label: {
                        pickerLabel(model.selectedModelLabel ?? (model.defaultModelName.isEmpty ? "model" : model.defaultModelName))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("m", modifiers: .command)
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
        // When the picker closes, the search field's removal leaves first
        // responder nil — return focus to the input so Esc keeps working.
        .onChange(of: showModelPicker) {
            if !showModelPicker { DispatchQueue.main.async { inputFocused = true } }
        }
        // In-panel dropdown — SwiftUI .popover can't present from a
        // nonactivating NSPanel, so the picker is an overlay in the same window.
        // The dismiss catcher sits *behind* the dropdown (overlays stack in
        // application order).
        .overlay {
            if showModelPicker {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { showModelPicker = false }
            }
        }
        .overlay(alignment: .topTrailing) {
            if showModelPicker {
                modelPickerDropdown
                    .padding(.top, 40)
                    .padding(.trailing, 10)
            }
        }
    }

    private var filteredModelChoices: [(label: String, providerID: String, modelID: String)] {
        let terms = modelSearch.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return model.modelChoices }
        return model.modelChoices.filter { choice in
            terms.allSatisfy { choice.label.localizedCaseInsensitiveContains($0) }
        }
    }

    private var modelPickerDropdown: some View {
        VStack(spacing: 0) {
            TextField("Search models", text: $modelSearch)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Ink.text)
                .focused($searchFocused)
                .onChange(of: modelSearch) { modelHighlight = min(modelHighlight, filteredModelChoices.count) }
                .onKeyPress(keys: [.upArrow, .downArrow, .return]) { press in
                    switch press.key {
                    case .upArrow: modelHighlight = max(0, modelHighlight - 1)
                    case .downArrow: modelHighlight = min(filteredModelChoices.count, modelHighlight + 1)
                    case .return: pickHighlightedModel()
                    default: return .ignored
                    }
                    return .handled
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            hairline
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        modelRow(
                            label: model.defaultModelName.isEmpty ? "server default" : "default (\(model.defaultModelName))",
                            selected: model.selectedModelLabel == nil,
                            highlighted: modelHighlight == 0
                        ) { model.selectedModelLabel = nil }
                        .id(0)
                        ForEach(Array(filteredModelChoices.enumerated()), id: \.element.label) { i, c in
                            modelRow(
                                label: c.label,
                                selected: model.selectedModelLabel == c.label,
                                highlighted: modelHighlight == i + 1
                            ) { model.selectedModelLabel = c.label }
                            .id(i + 1)
                        }
                    }
                }
                .onChange(of: modelHighlight) { proxy.scrollTo(modelHighlight, anchor: .center) }
            }
            // LazyVStack inside an overlay doesn't reliably reload rows when
            // the filtered collection changes — force a rebuild per query.
            .id(modelSearch)
            .frame(maxHeight: 320)
        }
        .frame(width: 260)
        .background(Ink.bg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Ink.hairline, lineWidth: 0.5)
        )
        .preferredColorScheme(.dark)
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
    }

    private func pickHighlightedModel() {
        if modelHighlight > 0, filteredModelChoices.indices.contains(modelHighlight - 1) {
            model.selectedModelLabel = filteredModelChoices[modelHighlight - 1].label
        } else {
            model.selectedModelLabel = nil
        }
        showModelPicker = false
    }

    private func modelRow(label: String, selected: Bool, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            showModelPicker = false
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(selected ? 1 : 0)
                    .frame(width: 12)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(highlighted || hoveredModel == label ? Ink.fill : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredModel = $0 ? label : nil }
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
