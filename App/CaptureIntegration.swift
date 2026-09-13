import SwiftUI
import AppIntents

struct AddDaylineTask: AppIntent {
    static var title: LocalizedStringResource = "添加 Life · OS 任务"
    static var description = IntentDescription("按明确字段添加任务。标题原样保存。")
    static var openAppWhenRun = true
    @Parameter(title: "任务标题") var title: String
    @Parameter(title: "日期与时间") var due: Date?
    @Parameter(title: "全天", default: false) var allDay: Bool
    @Parameter(title: "备注") var notes: String?
    @Parameter(title: "优先级（0–3）", default: 0) var priority: Int
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let store = DaylineStore.shared
        var fields: [String: Value] = ["title": .string(title), "allDay": .flag(allDay), "priority": .number(priority)]
        if let due { fields["due"] = .date(due) }; if let notes { fields["notes"] = .string(notes) }
        let response = try store.execute(AgentRequest(command: "task.add", fields: fields))
        return .result(value: response.records.first.map { TaskLink.url($0.id).absoluteString } ?? "")
    }
}
struct FindDaylineTasks: AppIntent {
    static var title: LocalizedStringResource = "查询 Life · OS 任务"
    static var description = IntentDescription("按文字查询任务，返回包含 ID、标题与日期的 JSON。")
    static var openAppWhenRun = true
    @Parameter(title: "包含文字", default: "") var search: String
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let response = try DaylineStore.shared.execute(AgentRequest(command: "task.list", filter: TaskFilter(search: search)))
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return .result(value: String(decoding: try e.encode(response.records), as: UTF8.self))
    }
}

#if os(macOS)
import AppKit
import Carbon

@MainActor final class QuickCaptureController {
    static let shared = QuickCaptureController()
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var panel: NSPanel?
    private var previousApp: NSRunningApplication?
    private(set) var status = "尚未启用"
    func start() {
        guard hotKey == nil else { return }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerResult = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in QuickCaptureController.shared.show() }
            return noErr
        }, 1, &event, nil, &handler)
        guard handlerResult == noErr else { status = "无法注册快捷键处理器"; return }
        let result = RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x444C4E45, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        status = result == noErr ? "⌘⇧空格 · 快速添加" : "快捷键被占用（\(result)），仍可通过菜单栏添加"
    }
    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        if panel == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 360), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            window.title = "快速添加"; window.isFloatingPanel = true; window.level = .floating; window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel = window
        }
        panel?.contentView = NSHostingView(rootView: QuickCaptureView(close: { [weak self] in self?.panel?.orderOut(nil); self?.previousApp?.activate(options: []) }).environment(DaylineStore.shared).daylineTheme())
        panel?.center(); NSApp.activate(ignoringOtherApps: true); panel?.makeKeyAndOrderFront(nil)
    }
}
struct QuickCaptureView: View {
    @Environment(DaylineStore.self) private var store
    let close: () -> Void
    @State private var title = ""
    @State private var dateEnabled = false
    @State private var date = Date()
    @State private var allDay = true
    @State private var list = "inbox"
    @State private var priority = 0
    @FocusState private var focus: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TextField("任务标题", text: $title).font(.title2).textFieldStyle(.plain).focused($focus).onSubmit(add)
            Picker("专项", selection: $list) { Text("待整理").tag("inbox"); ForEach(store.projection.lists.filter { !$0.archived }) { Text($0.title).tag($0.id) } }
            Toggle("设置日期", isOn: $dateEnabled)
            if dateEnabled { HStack { LifeDatePicker("日期", selection: $date, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]); Toggle("全天", isOn: $allDay) } }
            Picker("优先级", selection: $priority) { ForEach(0..<4) { Text(Labels.priority($0)).tag($0) } }
            HStack { Button("取消", action: close).keyboardShortcut(.cancelAction); Spacer(); Button("添加", action: add).buttonStyle(.borderedProminent).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(width: 500).paperSurface().onAppear { focus = true }
    }
    private func add() {
        var fields: [String: Value] = ["title": .string(title), "priority": .number(priority), "listID": .string(list), "allDay": .flag(allDay)]
        if dateEnabled { fields["due"] = .date(allDay ? Calendar.current.startOfDay(for: date) : date) }
        if store.perform("task.add", fields: fields) != nil { close() }
    }
}
#endif
