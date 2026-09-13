import SwiftUI

@main struct DaylineApp: App {
    @State private var store = DaylineStore.shared
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    var body: some Scene {
        WindowGroup(id: "main") {
            RootView().environment(store)
                #if os(macOS)
                .onAppear { QuickCaptureController.shared.start() }
                #endif
                .daylineTheme()
                .frame(minWidth: minimumWidth, minHeight: minimumHeight)
        }
        #if os(macOS)
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("全局快速添加") { QuickCaptureController.shared.show() }.keyboardShortcut(.space, modifiers: [.command, .shift])
                Button("快速添加任务") { NotificationCenter.default.post(name: .daylineQuickAdd, object: nil) }.keyboardShortcut("n", modifiers: .command)
                Button("搜索任务") { NotificationCenter.default.post(name: .daylineSearch, object: nil) }.keyboardShortcut("f", modifiers: .command)
            }
        }
        #endif
        #if os(macOS)
        Settings { SettingsView().environment(store).daylineTheme().frame(width: 560, height: 600) }
        MenuBarExtra("Life · OS", systemImage: "checkmark.circle") {
            Text("待整理 \(store.projection.query(TaskFilter(listID: "inbox")).count) 项")
            Button("快速添加 · ⌘⇧空格") { QuickCaptureController.shared.show() }
            Button("打开 Life · OS") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            Divider()
            Text(store.syncStatus)
            Button("退出 Life · OS") { NSApp.terminate(nil) }
        }
        #endif
    }
    private var minimumWidth: CGFloat? {
        #if os(macOS)
        1040
        #else
        nil
        #endif
    }
    private var minimumHeight: CGFloat? {
        #if os(macOS)
        660
        #else
        nil
        #endif
    }
}

extension Notification.Name {
    static let daylineRevealTask = Notification.Name("dayline.revealTask")
    static let daylineOpenTask = Notification.Name("dayline.openTask")
    static let daylineQuickAdd = Notification.Name("dayline.quickAdd")
    static let daylineSearch = Notification.Name("dayline.search")
}

extension Color {
    static func dayline(_ name: String) -> Color {
        .ink
    }
    static var daylineBackground: Color {
        .paper
    }
    static var daylineSecondary: Color {
        .paperInset
    }
}

@MainActor enum Labels {
    static func repeatRule(_ rule: String) -> String {
        ["none": "不重复", "daily": "每天", "weekdays": "工作日", "weekly": "每周", "biweekly": "每两周", "monthly": "每月", "yearly": "每年"][rule] ?? rule
    }
    static func priority(_ priority: Int) -> String { ["无优先级", "低优先级", "中优先级", "高优先级"][max(0, min(3, priority))] }
    static func priorityColor(_ priority: Int) -> Color { priority == 0 ? .secondary : .ink }
    private static let dayFormatter = formatter("M月d日 EEE")
    private static let timeFormatter = formatter("M月d日 HH:mm")
    private static func formatter(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = pattern
        formatter.timeZone = .autoupdatingCurrent; return formatter
    }
    static func date(_ date: Date, allDay: Bool = true) -> String {
        (allDay ? dayFormatter : timeFormatter).string(from: date)
    }
}
