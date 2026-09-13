import SwiftUI
#if os(macOS)
import AppKit
private typealias EditorFont = NSFont
#else
import UIKit
private typealias EditorFont = UIFont
#endif

struct RichAction: Equatable { var id = UUID(); var name: String; var argument = "" }

@MainActor final class RichEditorController {
    var finishEditing: (() -> Void)?
}

struct RichTextEditor: View {
    @Binding var text: String
    @Binding var rich: String
    var fillsSpace = false
    var isExpanded = false
    var controller: RichEditorController? = nil
    var toggleFocus: (() -> Void)? = nil
    @State private var action: RichAction?
    @State private var localController = RichEditorController()
    @State private var linkPrompt = false
    @State private var link = "https://"
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    tool("粗体", "bold", "bold"); tool("斜体", "italic", "italic"); tool("下划线", "underline", "underline"); tool("删除线", "strikethrough", "strike")
                    Menu { Button("大标题") { action = RichAction(name: "h1") }; Button("小标题") { action = RichAction(name: "h2") }; Button("正文") { action = RichAction(name: "body") }; Button("等宽文字") { action = RichAction(name: "code") } } label: { Image(systemName: "textformat.size").iconTarget() }.accessibilityLabel("文字样式")
                    tool("项目列表", "list.bullet", "bullet"); tool("编号列表", "list.number", "number"); tool("勾选列表", "checklist", "checklist")
                    Button { linkPrompt = true } label: { Image(systemName: "link") }.accessibilityLabel("插入链接")
                }.buttonStyle(.ink).padding(8)
            }
            Divider()
            NativeRichEditor(text: $text, rich: $rich, action: action, controller: controller ?? localController)
                .frame(minHeight: fillsSpace ? 0 : 250, maxHeight: fillsSpace ? .infinity : nil)
            if let toggleFocus {
                HStack {
                    Spacer()
                    Button {
                        (controller ?? localController).finishEditing?()
                        toggleFocus()
                    } label: {
                        Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }.buttonStyle(.ink)
                        .accessibilityLabel(isExpanded ? "退出备注全屏" : "全屏查看备注")
                        .accessibilityIdentifier(isExpanded ? "exitNotesFullscreen" : "expandNotesFullscreen")
                        .help(isExpanded ? "退出备注全屏" : "全屏查看备注")
                }.padding(.horizontal, 8).padding(.bottom, 4)
            }
        }.background(fillsSpace ? Color.clear : Color.daylineSecondary, in: RoundedRectangle(cornerRadius: 10))
            .alert("插入链接", isPresented: $linkPrompt) { TextField("https:// 或 \(AppConfiguration.urlScheme)://", text: $link); Button("取消", role: .cancel) {}; Button("插入") { if let url = URL(string: link), ["https", "http", AppConfiguration.urlScheme].contains(url.scheme ?? "") { action = RichAction(name: "link", argument: link) } } } message: { Text("链接会应用到选中文字；没有选中文字时，插入链接地址。") }
    }
    private func tool(_ label: String, _ icon: String, _ command: String) -> some View { Button { action = RichAction(name: command) } label: { Image(systemName: icon) }.accessibilityLabel(label).help(label) }
}

private enum RichDocument {
    static func read(_ rich: String, plain: String) -> NSAttributedString {
        if let data = Data(base64Encoded: rich), let value = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil), value.string == plain { return value }
        return NSAttributedString(string: plain, attributes: [.font: EditorFont.preferredFont(forTextStyle: .body)])
    }
    static func encode(_ value: NSAttributedString) -> String { (try? value.data(from: NSRange(location: 0, length: value.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]))?.base64EncodedString() ?? "" }
    static func typingAttributes(_ action: RichAction, current: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        let sample = NSMutableAttributedString(string: "x", attributes: current)
        _ = apply(action, to: sample, selection: NSRange(location: 0, length: 1))
        return sample.attributes(at: 0, effectiveRange: nil)
    }
    static func apply(_ action: RichAction, to text: NSMutableAttributedString, selection: NSRange) -> NSRange {
        let range = NSRange(location: min(selection.location, text.length), length: min(selection.length, max(0, text.length - selection.location)))
        if ["bullet", "number", "checklist"].contains(action.name) {
            let paragraph = (text.string as NSString).paragraphRange(for: range)
            let raw = (text.string as NSString).substring(with: paragraph)
            let lines = raw.components(separatedBy: "\n")
            var positions: [(Int, String)] = []; var cursor = paragraph.location
            for (index, line) in lines.enumerated() {
                if index < lines.count - 1 || !line.isEmpty || lines.count == 1 {
                    let prefix = action.name == "bullet" ? "• " : action.name == "number" ? "\(index + 1). " : "☐ "
                    positions.append((cursor, prefix))
                }
                cursor += (line as NSString).length + 1
            }
            for (position, prefix) in positions.reversed() { text.insert(NSAttributedString(string: prefix, attributes: [.font: EditorFont.systemFont(ofSize: 15)]), at: position) }
            return NSRange(location: range.location + (positions.first?.1.utf16.count ?? 0), length: 0)
        }
        if action.name == "link" {
            if range.length == 0 { text.insert(NSAttributedString(string: action.argument, attributes: [.link: action.argument, .font: EditorFont.systemFont(ofSize: 15)]), at: range.location); return NSRange(location: range.location + action.argument.utf16.count, length: 0) }
            text.addAttribute(.link, value: action.argument, range: range); return range
        }
        let target = ["h1", "h2", "body"].contains(action.name) ? (text.string as NSString).paragraphRange(for: range) : range
        guard target.length > 0 else { return range }
        if action.name == "underline" || action.name == "strike" {
            let key: NSAttributedString.Key = action.name == "underline" ? .underlineStyle : .strikethroughStyle
            let enabled = (text.attribute(key, at: target.location, effectiveRange: nil) as? Int ?? 0) != 0
            text.addAttribute(key, value: enabled ? 0 : NSUnderlineStyle.single.rawValue, range: target); return range
        }
        text.enumerateAttribute(.font, in: target) { value, segment, _ in
            let font = value as? EditorFont ?? EditorFont.systemFont(ofSize: 15)
            var next = font
            switch action.name {
            case "h1": next = EditorFont.boldSystemFont(ofSize: 25)
            case "h2": next = EditorFont.boldSystemFont(ofSize: 20)
            case "body": next = EditorFont.systemFont(ofSize: 15)
            case "code": next = EditorFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            case "bold", "italic":
                #if os(macOS)
                let trait: NSFontTraitMask = action.name == "bold" ? .boldFontMask : .italicFontMask
                next = NSFontManager.shared.traits(of: font).contains(trait) ? NSFontManager.shared.convert(font, toNotHaveTrait: trait) : NSFontManager.shared.convert(font, toHaveTrait: trait)
                #else
                let trait: UIFontDescriptor.SymbolicTraits = action.name == "bold" ? .traitBold : .traitItalic
                var traits = font.fontDescriptor.symbolicTraits
                if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
                if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) { next = UIFont(descriptor: descriptor, size: font.pointSize) }
                #endif
            default: break
            }
            text.addAttribute(.font, value: next, range: segment)
        }
        return range
    }
}

#if os(macOS)
private struct NativeRichEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var rich: String
    let action: RichAction?
    let controller: RichEditorController
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let editor = NSTextView(); editor.isRichText = true; editor.importsGraphics = false; editor.drawsBackground = false
        editor.isAutomaticDataDetectionEnabled = false; editor.isAutomaticLinkDetectionEnabled = false; editor.isAutomaticTextCompletionEnabled = false
        editor.minSize = .zero; editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false; editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true; editor.textContainerInset = NSSize(width: 8, height: 10)
        editor.textStorage?.setAttributedString(RichDocument.read(rich, plain: text)); editor.delegate = context.coordinator
        controller.finishEditing = { [weak editor, weak coordinator = context.coordinator] in
            guard let editor else { return }
            editor.unmarkText()
            if editor.window?.firstResponder === editor { editor.window?.makeFirstResponder(nil) }
            coordinator?.flush(editor)
        }
        editor.linkTextAttributes = [.foregroundColor: NSColor.labelColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        scroll.documentView = editor; return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if let action, context.coordinator.actionID != action.id {
            context.coordinator.actionID = action.id
            if editor.selectedRange().length == 0 && ["bold", "italic", "underline", "strike", "code"].contains(action.name) {
                editor.typingAttributes = RichDocument.typingAttributes(action, current: editor.typingAttributes)
                editor.window?.makeFirstResponder(editor); return
            }
            let value = NSMutableAttributedString(attributedString: editor.attributedString())
            let range = RichDocument.apply(action, to: value, selection: editor.selectedRange())
            editor.textStorage?.setAttributedString(value); editor.setSelectedRange(range)
            context.coordinator.emit(editor); editor.window?.makeFirstResponder(editor)
        } else if editor.window?.firstResponder !== editor && (context.coordinator.lastText != text || context.coordinator.lastRich != rich) {
            let value = RichDocument.read(rich, plain: text)
            if !editor.attributedString().isEqual(to: value) { editor.textStorage?.setAttributedString(value) }
            context.coordinator.lastText = text; context.coordinator.lastRich = rich
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeRichEditor; var actionID: UUID?
        var lastText: String; var lastRich: String
        private var emission = 0
        private var pendingEmission = false
        init(_ parent: NativeRichEditor) { self.parent = parent; lastText = parent.text; lastRich = parent.rich }
        func textDidChange(_ notification: Notification) { if let editor = notification.object as? NSTextView { emit(editor) } }
        func flush(_ editor: NSTextView) {
            if pendingEmission || editor.string != parent.text { emit(editor, immediately: true) }
        }
        func emit(_ editor: NSTextView, immediately: Bool = false) {
            let plain = editor.string, rich = RichDocument.encode(editor.attributedString())
            lastText = plain; lastRich = rich; emission += 1; pendingEmission = true; let version = emission
            let publish = { [weak self] in
                guard let self, self.emission == version else { return }
                self.pendingEmission = false
                self.parent.text = plain; self.parent.rich = rich
            }
            if immediately { publish() } else { DispatchQueue.main.async(execute: publish) }
        }
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)), let id = TaskLink.id(from: url) { NotificationCenter.default.post(name: .daylineOpenTask, object: id); return true }
            return false
        }
    }
}
#else
private struct NativeRichEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var rich: String
    let action: RichAction?
    let controller: RichEditorController
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let editor = UITextView(); editor.backgroundColor = .clear; editor.isScrollEnabled = true; editor.allowsEditingTextAttributes = true
        editor.dataDetectorTypes = []; editor.attributedText = RichDocument.read(rich, plain: text); editor.delegate = context.coordinator
        controller.finishEditing = { [weak editor, weak coordinator = context.coordinator] in
            guard let editor else { return }
            editor.unmarkText()
            editor.resignFirstResponder()
            coordinator?.flush(editor)
        }
        editor.adjustsFontForContentSizeCategory = true; editor.tintColor = .black
        editor.linkTextAttributes = [.foregroundColor: UIColor.label, .underlineStyle: NSUnderlineStyle.single.rawValue]
        editor.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8); return editor
    }
    func updateUIView(_ editor: UITextView, context: Context) {
        context.coordinator.parent = self
        if let action, context.coordinator.actionID != action.id {
            context.coordinator.actionID = action.id
            if editor.selectedRange.length == 0 && ["bold", "italic", "underline", "strike", "code"].contains(action.name) {
                editor.typingAttributes = RichDocument.typingAttributes(action, current: editor.typingAttributes)
                editor.becomeFirstResponder(); return
            }
            let value = NSMutableAttributedString(attributedString: editor.attributedText ?? NSAttributedString(string: ""))
            let range = RichDocument.apply(action, to: value, selection: editor.selectedRange)
            editor.attributedText = value; editor.selectedRange = range; context.coordinator.emit(editor); editor.becomeFirstResponder()
        } else if !editor.isFirstResponder && (context.coordinator.lastText != text || context.coordinator.lastRich != rich) {
            let value = RichDocument.read(rich, plain: text)
            if !(editor.attributedText ?? NSAttributedString(string: "")).isEqual(to: value) { editor.attributedText = value }
            context.coordinator.lastText = text; context.coordinator.lastRich = rich
        }
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeRichEditor; var actionID: UUID?
        var lastText: String; var lastRich: String
        private var emission = 0
        private var pendingEmission = false
        init(_ parent: NativeRichEditor) { self.parent = parent; lastText = parent.text; lastRich = parent.rich }
        func textViewDidChange(_ editor: UITextView) { emit(editor) }
        func flush(_ editor: UITextView) {
            if pendingEmission || (editor.text ?? "") != parent.text { emit(editor, immediately: true) }
        }
        func emit(_ editor: UITextView, immediately: Bool = false) {
            let plain = editor.text ?? "", rich = RichDocument.encode(editor.attributedText ?? NSAttributedString(string: ""))
            lastText = plain; lastRich = rich; emission += 1; pendingEmission = true; let version = emission
            let publish = { [weak self] in
                guard let self, self.emission == version else { return }
                self.pendingEmission = false
                self.parent.text = plain; self.parent.rich = rich
            }
            if immediately { publish() } else { DispatchQueue.main.async(execute: publish) }
        }
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            if let id = TaskLink.id(from: URL) { NotificationCenter.default.post(name: .daylineOpenTask, object: id); return false }; return true
        }
    }
}
#endif

struct FocusedNotesView: View {
    let title: String
    @Binding var text: String
    @Binding var rich: String
    let controller: RichEditorController
    let close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                Text(title).font(.headline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Button("完成", action: close).buttonStyle(.ink).keyboardShortcut(.cancelAction)
                    .accessibilityLabel("结束全屏查看备注")
            }.padding(.horizontal, 20).padding(.vertical, 10)
            RichTextEditor(text: $text, rich: $rich, fillsSpace: true, isExpanded: true, controller: controller, toggleFocus: close)
                .frame(maxWidth: 1100, maxHeight: .infinity).padding(.horizontal, 12)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).paperSurface().daylineTheme()
    }
}

#if os(macOS)
/// A separate native full-screen window keeps the task workspace and its scroll position intact.
struct NotesFocusWindow: NSViewRepresentable {
    @Binding var isPresented: Bool
    let content: AnyView
    let close: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ anchor: NSView, context: Context) {
        context.coordinator.update(presented: isPresented, content: content, close: close, screen: anchor.window?.screen)
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.dispose() }

    final class Coordinator: NSObject, NSWindowDelegate {
        private var window: NSWindow?
        private var host: NSHostingView<AnyView>?
        private var close: (() -> Void)?
        private var wantsPresented = false
        private var leavingFullscreen = false
        func update(presented: Bool, content: AnyView, close: @escaping () -> Void, screen: NSScreen?) {
            self.close = close; wantsPresented = presented
            if !presented { requestClose(); return }
            if let host { host.rootView = content; return }
            let frame = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1100, height: 800)
            let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "备注 · Life · OS"; window.isReleasedWhenClosed = false
            window.collectionBehavior = [.fullScreenPrimary]; window.minSize = NSSize(width: 500, height: 400)
            window.delegate = self
            let host = NSHostingView(rootView: content); window.contentView = host
            self.window = window; self.host = host
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window, self.wantsPresented else { return }
                window.toggleFullScreen(nil)
            }
        }
        private func requestClose() {
            guard let window else { return }
            if window.styleMask.contains(.fullScreen) {
                if !leavingFullscreen { leavingFullscreen = true; window.toggleFullScreen(nil) }
            } else { window.close() }
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool { close?(); return true }
        func windowDidExitFullScreen(_ notification: Notification) { close?(); window?.close() }
        func windowWillClose(_ notification: Notification) {
            close?(); window = nil; host = nil; leavingFullscreen = false
        }
        func dispose() { close?(); window?.delegate = nil; window?.close(); window = nil; host = nil }
    }
}
#endif
