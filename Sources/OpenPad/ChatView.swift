import AppKit
import SwiftUI

/// Strict monochrome palette — shades of grey only; red reserved for errors.
private enum Ink {
    static let bg = Color(white: 0.055)
    static let fill = Color.white.opacity(0.07)
    static let fillHover = Color.white.opacity(0.11)
    static let hairline = Color.white.opacity(0.12)
    static let text = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.36)
    static let error = Color(red: 0.95, green: 0.35, blue: 0.35)
    static func mono(_ size: CGFloat) -> Font { .custom("BerkeleyMonoVariable-Regular", size: size) }
    static func monoItalic(_ size: CGFloat) -> Font { .custom("BerkeleyMonoVariable-Italic", size: size) }
}

/// Braille spinner — terminals don't have ProgressView.
private struct Spinner: View {
    static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { ctx in
            Text(Self.frames[Int(ctx.date.timeIntervalSinceReferenceDate / 0.08) % Self.frames.count])
        }
    }
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
                    .font(Ink.mono(12))
                    .foregroundStyle(Ink.secondary)
                Spacer()
                if !model.modelChoices.isEmpty {
                    Button { showModelPicker.toggle() } label: {
                        Text("[\(model.selectedModelLabel ?? (model.defaultModelName.isEmpty ? "model" : model.defaultModelName))]")
                            .font(Ink.mono(11))
                            .lineLimit(1)
                            .foregroundStyle(Ink.secondary)
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
                                Spinner().font(Ink.mono(11))
                                Text("connecting…")
                                    .font(Ink.mono(11))
                                    .foregroundStyle(Ink.secondary)
                            }
                            .foregroundStyle(Ink.secondary)
                        }
                        ForEach(model.messages) { msg in
                            messageRow(msg)
                        }
                        if model.busy {
                            HStack(spacing: 8) {
                                Spinner().font(Ink.mono(11))
                                Text("working…")
                                    .font(Ink.mono(11))
                            }
                            .foregroundStyle(Ink.secondary)
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("❯")
                    .font(Ink.mono(12))
                    .foregroundStyle(Ink.secondary)
                TextField("Message…", text: $query, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Ink.mono(12))
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
                    textButton("^C", help: "Stop (⌘.)") { model.abort() }
                        .keyboardShortcut(".", modifiers: .command)
                }
                textButton("+", help: "New chat (⌘N)") { model.newChat(); query = "" }
                    .keyboardShortcut("n", modifiers: .command)
                textButton(">_", help: "Open in Ghostty (⌘O)") { model.openInGhostty() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            if !model.statusLine.isEmpty {
                Text(model.statusLine)
                    .font(Ink.mono(10))
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

    /// match-sorter tiers: prefix (3) > word boundary (2) > substring (1) > miss (0).
    private func matchTier(_ term: String, in label: String) -> Int {
        guard let r = label.localizedStandardRange(of: term) else { return 0 }
        if r.lowerBound == label.startIndex { return 3 }
        let before = label[label.index(before: r.lowerBound)]
        return before.isLetter || before.isNumber ? 1 : 2
    }

    private var filteredModelChoices: [(label: String, providerID: String, modelID: String)] {
        let terms = modelSearch.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return model.modelChoices }
        let ranked = model.modelChoices.compactMap { choice -> (item: (label: String, providerID: String, modelID: String), rank: Int)? in
            let worst = terms.map { matchTier($0, in: choice.label) }.min() ?? 0
            return worst > 0 ? (choice, worst) : nil
        }
        return ranked
            .sorted { $0.rank == $1.rank ? $0.item.label < $1.item.label : $0.rank > $1.rank }
            .map(\.item)
    }

    private var modelPickerDropdown: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("❯")
                    .font(Ink.mono(11))
                    .foregroundStyle(Ink.tertiary)
                TextField("search models", text: $modelSearch)
                    .textFieldStyle(.plain)
                    .font(Ink.mono(11))
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
                Text("*")
                    .font(Ink.mono(10))
                    .opacity(selected ? 1 : 0)
                    .frame(width: 12)
                Text(label)
                    .font(Ink.mono(11))
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

    private func textButton(_ label: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Ink.mono(12))
                .foregroundStyle(Ink.secondary)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func messageRow(_ msg: ChatModel.Msg) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if msg.role == "user" {
                HStack(alignment: .top, spacing: 8) {
                    Text("❯")
                        .font(Ink.mono(12))
                        .foregroundStyle(Ink.secondary)
                    Text(msg.text)
                        .font(Ink.mono(12))
                        .foregroundStyle(Ink.text)
                        .textSelection(.enabled)
                }
            } else {
                ForEach(msg.order, id: \.self) { partID in
                    if let text = msg.texts[partID], !text.isEmpty {
                        Text(LocalizedStringKey(text))
                            .font(Ink.mono(12))
                            .lineSpacing(3)
                            .foregroundStyle(Ink.text)
                            .textSelection(.enabled)
                    } else if let tool = msg.tools.first(where: { $0.id == partID }) {
                        toolRow(tool)
                    }
                }
                if msg.stopped {
                    Text("stopped")
                        .font(Ink.monoItalic(11))
                        .foregroundStyle(Ink.tertiary)
                } else if msg.text.isEmpty, !model.busy {
                    Text("done — \(msg.toolCount) tool call\(msg.toolCount == 1 ? "" : "s")\(msg.errorCount > 0 ? ", \(msg.errorCount) errors" : "")")
                        .font(Ink.monoItalic(11))
                        .foregroundStyle(Ink.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(msg.id)
    }

    private func toolRow(_ tool: (id: String, name: String, detail: String?, status: String)) -> some View {
        HStack(spacing: 6) {
            Text("$")
                .font(Ink.mono(11))
            Text(tool.name)
                .font(Ink.mono(11))
            if let detail = tool.detail, !detail.isEmpty {
                Text(detail.replacingOccurrences(of: "\n", with: " "))
                    .font(Ink.mono(11))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if tool.status == "running" || tool.status == "pending" {
                Spinner().font(Ink.mono(11))
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
