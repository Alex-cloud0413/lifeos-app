import SwiftUI
import UniformTypeIdentifiers

struct ArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @AppStorage("paperTextureEnabled") private var paperTexture = true
    @Environment(DaylineStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var importing = false
    @State private var document = ArchiveDocument()
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("iCloud 与数据") {
                    Label(store.syncStatus, systemImage: store.cloudAvailable ? "icloud" : "icloud.slash")
                    if let date = store.lastImport { LabeledContent("最近下载", value: Labels.date(date, allDay: false)) }
                    if let date = store.lastExport { LabeledContent("最近上传", value: Labels.date(date, allDay: false)) }
                    if store.cloudEnabled {
                        Text("任务储存在你自己的 iCloud 私有数据库中。每台设备保留离线副本，联网后由系统同步。新安装的设备首次打开 App 后才开始接收数据。").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("这是本机预览版本，当前任务只在这台 Mac 上保存。签名后的 iCloud 版本使用独立任务库，可通过下方备份导入。").font(.caption).foregroundStyle(Color.ink)
                    }
                    Button("检查 iCloud 状态") { Task { await store.refreshCloudStatus() } }
                }
                #if os(macOS)
                Section("快速添加") { Text(QuickCaptureController.shared.status); Button("打开快速添加") { QuickCaptureController.shared.show() } }
                Section("本地 Agent") {
                    Text(store.agentStatus)
                    HStack { Button("启用连接") { store.startAgent() }; Button("关闭连接") { store.stopAgent() } }
                    Text("本地 Agent 可读取和修改全部 Life · OS 任务。连接仅供这台 Mac 的当前用户使用；App 需保持运行，关闭窗口后仍可通过菜单栏使用。").font(.caption).foregroundStyle(.secondary)
                    Text("lifeos directions\nlifeos add \"写周报\"").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                #endif
                Section("备份与恢复") {
                    LabeledContent("任务数", value: "\(store.projection.tasks.count)")
                    LabeledContent("操作记录", value: "\(store.projection.eventIDs.count)")
                    Button("导出完整备份…") {
                        do { document = ArchiveDocument(data: try store.exportArchive()); exporting = true }
                        catch { message = error.localizedDescription }
                    }
                    Button("合并导入备份…") { importing = true }
                    Text("备份包含方向、专项、任务、筛选与操作记录。导入会合并并去重，不会清空现有资料。可以将备份保存在 iCloud 云盘。").font(.caption).foregroundStyle(.secondary)
                }
                Section("外观") {
                    Toggle("轻柔纸纹", isOn: $paperTexture)
                    Text("开启增加对比度或减少透明度时，自动使用纯白背景。").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("Life · OS \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · 个人开发版本").font(.caption)
                    Text("任务与日历，按自己的节奏安排。无广告、无自建账号服务器。").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).paperSurface().navigationTitle("设置")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Life-OS-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in if case .failure(let error) = result { message = error.localizedDescription } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let count = try store.importArchive(Data(contentsOf: url)); message = "已合并 \(count) 条新操作记录。"
                    } catch { message = error.localizedDescription }
                }
                .alert("备份与恢复", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("好") { message = nil } } message: { Text(message ?? "") }
        }.frame(idealWidth: 560, idealHeight: 680)
    }
}
