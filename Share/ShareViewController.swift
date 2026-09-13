import UIKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class ShareDraft: ObservableObject {
    @Published var title = ""
    @Published var notes = ""
    @Published var loading = true
    @Published var error: String?
}
final class ShareViewController: UIViewController {
    private let draft = ShareDraft()
    override func viewDidLoad() {
        super.viewDidLoad()
        let child = UIHostingController(rootView: ShareCaptureView(draft: draft, save: { [weak self] in self?.save() }, cancel: { [weak self] in self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)) }))
        addChild(child); child.view.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child.view)
        NSLayoutConstraint.activate([child.view.topAnchor.constraint(equalTo: view.topAnchor), child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor), child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        child.didMove(toParent: self)
        Task { @MainActor in
            do {
                var texts: [String] = []
                let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
                for item in items {
                    for provider in item.attachments ?? [] {
                        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                            let value = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil)
                            if let url = value as? URL { texts.append(url.absoluteString) }
                        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                            let value = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil)
                            if let value = value as? String { texts.append(value) }
                            else if let data = value as? Data, let value = String(data: data, encoding: .utf8) { texts.append(value) }
                        }
                    }
                }
                draft.notes = Array(NSOrderedSet(array: texts)) .compactMap { $0 as? String }.joined(separator: "\n\n")
                let suggested = items.compactMap { $0.attributedTitle?.string }.first ?? texts.first?.components(separatedBy: "\n").first ?? ""
                draft.title = String(suggested.prefix(120)); draft.loading = false
            } catch { draft.error = error.localizedDescription; draft.loading = false }
        }
    }
    private func save() {
        do { try SharedInbox.save(SharedCapture(title: draft.title, notes: draft.notes)); extensionContext?.completeRequest(returningItems: nil) }
        catch { draft.error = error.localizedDescription }
    }
}
struct ShareCaptureView: View {
    @ObservedObject var draft: ShareDraft
    let save: () -> Void
    let cancel: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                if draft.loading { ProgressView("正在接收内容…") }
                TextField("任务标题", text: $draft.title)
                Section("备注与来源") { TextEditor(text: $draft.notes).frame(minHeight: 160) }
                Text("存入收集箱。下次打开 Life · OS 时接收并同步到 iCloud。").font(.caption).foregroundStyle(.secondary)
                if let error = draft.error { Text(error).foregroundStyle(Color.ink) }
            }.paperSurface().navigationTitle("存入 Life · OS").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: cancel) }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(draft.loading || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }.daylineTheme()
    }
}
