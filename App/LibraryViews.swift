import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Clipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

struct FilterEditor: View {
    @Environment(DaylineStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let existing: Record?
    @State private var title: String
    @State private var filter: TaskFilter
    @State private var tags: String
    @State private var excluded: String
    @State private var dateRange: Bool
    @State private var start: Date
    @State private var end: Date
    init(existing: Record? = nil) {
        self.existing = existing
        var f = existing?["query"].string?.data(using: .utf8).flatMap { try? JSONDecoder().decode(TaskFilter.self, from: $0) } ?? TaskFilter()
        if let id = f.listID { f.listIDs.append(id); f.listID = nil }
        if let tag = f.tag { f.tags.append(tag); f.tag = nil }
        _title = State(initialValue: existing?.title ?? ""); _filter = State(initialValue: f)
        _tags = State(initialValue: f.tags.joined(separator: ", ")); _excluded = State(initialValue: f.excludedTags.joined(separator: ", "))
        _dateRange = State(initialValue: f.dueFrom != nil || f.dueThrough != nil)
        _start = State(initialValue: f.dueFrom ?? Date()); _end = State(initialValue: f.dueThrough ?? Date())
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("筛选名称", text: $title)
                Picker("条件关系", selection: $filter.matchAny) { Text("满足全部条件（AND）").tag(false); Text("满足任一条件（OR）").tag(true) }
                Picker("内容", selection: $filter.itemType) { Text("任务").tag("task"); Text("笔记").tag("note"); Text("任务与笔记").tag("all") }
                Picker("时间范围", selection: $filter.view) { Text("全部").tag("all"); Text("今天及逾期").tag("today"); Text("未来七天及逾期").tag("upcoming"); Text("未排期").tag("undated") }
                Section("纳入条件") {
                    DisclosureGroup("来自专项 · \(filter.listIDs.count) 个") { listToggles(excluding: false) }
                    TextField("包含标签，用逗号分隔", text: $tags)
                    Picker("优先级", selection: Binding(get: { filter.priority ?? -1 }, set: { filter.priority = $0 < 0 ? nil : $0 })) { Text("不限").tag(-1); ForEach(0..<4) { Text(Labels.priority($0)).tag($0) } }
                }
                Section("始终排除") {
                    TextField("排除标签，用逗号分隔", text: $excluded)
                    DisclosureGroup("排除专项 · \(filter.excludedLists.count) 个") { listToggles(excluding: true) }
                }
                Section("其他限制") {
                    TextField("包含文字", text: $filter.search)
                    Toggle("包括已完成", isOn: $filter.includeCompleted); Toggle("仅置顶", isOn: $filter.pinnedOnly)
                    Toggle("限制具体日期", isOn: $dateRange)
                    if dateRange { LifeDatePicker("从", selection: $start, displayedComponents: .date); LifeDatePicker("至", selection: $end, in: start..., displayedComponents: .date) }
                    Text("时间、类型、文字和排除条件始终生效。「任一条件」只作用于纳入的专项、标签和优先级。").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).paperSurface().navigationTitle(existing == nil ? "新建筛选" : "编辑筛选")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) } }
        }.frame(idealWidth: 550, idealHeight: 650)
    }
    private func listToggles(excluding: Bool) -> some View {
        let lists = [("inbox", "待整理")] + store.projection.lists.map { ($0.id, $0.title) }
        return ForEach(lists, id: \.0) { id, title in
            Toggle(title, isOn: Binding(get: { (excluding ? filter.excludedLists : filter.listIDs).contains(id) }, set: { on in
                if excluding { filter.excludedLists.removeAll { $0 == id }; if on { filter.excludedLists.append(id) } }
                else { filter.listIDs.removeAll { $0 == id }; if on { filter.listIDs.append(id) } }
            }))
        }
    }
    private func split(_ text: String) -> [String] { Array(Set(text.split(whereSeparator: { $0 == "," || $0 == "，" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted() }
    private func save() {
        filter.tags = split(tags); filter.excludedTags = split(excluded)
        let c = Calendar.current
        filter.dueFrom = dateRange ? c.startOfDay(for: start) : nil
        filter.dueThrough = dateRange ? c.date(byAdding: .day, value: 1, to: c.startOfDay(for: max(start, end)))!.addingTimeInterval(-0.001) : nil
        do {
            let data = try JSONEncoder().encode(filter)
            if store.perform(existing == nil ? "filter.add" : "filter.update", id: existing?.id, fields: ["title": .string(title), "query": .string(String(decoding: data, as: UTF8.self))]) != nil { dismiss() }
        } catch { store.errorMessage = error.localizedDescription }
    }
}

struct BatchEditor: View {
    @Environment(DaylineStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let ids: [String]
    @State private var action = "update"
    @State private var postponeDays = 1
    @State private var setDue = false
    @State private var due = Date()
    @State private var allDay = true
    @State private var setList = false
    @State private var list = "inbox"
    @State private var setPriority = false
    @State private var priority = 0
    @State private var setSection = false
    @State private var section = ""
    @State private var setProgress = false
    @State private var progress = 0.0
    var body: some View {
        NavigationStack {
            Form {
                Text("同时处理 \(ids.count) 项内容")
                Picker("操作", selection: $action) { Text("修改所选字段").tag("update"); Text("按天延期").tag("postpone"); Text("标记完成").tag("complete"); Text("恢复未完成").tag("reopen"); Text("移入回收站").tag("trash"); Text("从回收站恢复").tag("restore") }
                if action == "postpone" { Stepper("向后 \(postponeDays) 天", value: $postponeDays, in: 1...366); Text("保留各项原有时间和时长。所选项都需要已有日期。").font(.caption).foregroundStyle(.secondary) }
                if action == "update" {
                    Toggle("修改日期", isOn: $setDue)
                    if setDue { Toggle("全天", isOn: $allDay); LifeDatePicker("安排到", selection: $due, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]) }
                    Toggle("移动到专项", isOn: $setList)
                    if setList { Picker("专项", selection: $list) { Text("待整理").tag("inbox"); ForEach(store.projection.lists) { Text($0.title).tag($0.id) } } }
                    Toggle("修改优先级", isOn: $setPriority)
                    if setPriority { Picker("优先级", selection: $priority) { ForEach(0..<4) { Text(Labels.priority($0)).tag($0) } } }
                    Toggle("修改分组", isOn: $setSection)
                    if setSection { TextField("分组名称（空白表示未分组）", text: $section) }
                    Toggle("修改进度", isOn: $setProgress)
                    if setProgress { Slider(value: $progress, in: 0...100, step: 5); Text("\(Int(progress))%") }
                }
                Text("所有选中项会一起保存；任何一项不符合规则时，本次批量操作都不会写入。").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped).paperSurface().navigationTitle("批量操作")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("应用", action: apply).disabled(ids.isEmpty || (action == "update" && !setDue && !setList && !setPriority && !setSection && !setProgress)) } }
        }.frame(idealWidth: 500, idealHeight: 580)
    }
    private func apply() {
        var f: [String: Value] = ["ids": .strings(ids), "action": .string(action)]
        if action == "postpone" { f["days"] = .number(postponeDays) }
        if action == "update" {
            if setDue { f["due"] = .date(allDay ? Calendar.current.startOfDay(for: due) : due); f["allDay"] = .flag(allDay) }
            if setList { f["listID"] = .string(list) }
            if setPriority { f["priority"] = .number(priority) }
            if setSection { f["section"] = .string(section) }
            if setProgress { f["progress"] = .number(Int(progress)) }
        }
        if store.perform("task.batch", fields: f) != nil { dismiss() }
    }
}

struct TemplateLibrary: View {
    @Environment(DaylineStore.self) private var store
    @Binding var selectedTask: String?
    @State private var chosen: Record?
    var body: some View {
        Group {
            if store.projection.templates.isEmpty { ContentUnavailableView("保存常用流程", systemImage: "square.on.square", description: Text("在任务或笔记的菜单中选择「保存为模板」，子任务也会保留。")) }
            else { List(store.projection.templates) { item in
                HStack { VStack(alignment: .leading) { Text(item.title).font(.headline); Text("包含正文及子任务").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("使用") { chosen = item } }
                    .padding(.vertical, 10).listRowBackground(Color.clear).contextMenu { Button("删除模板") { store.perform("template.trash", id: item.id) } }
            }.scrollContentBackground(.hidden) }
        }.paperSurface().sheet(item: $chosen) { item in TemplateUseView(template: item) { selectedTask = $0 }.environment(store) }
    }
}
struct TemplateUseView: View {
    @Environment(DaylineStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let template: Record
    let created: (String) -> Void
    @State private var list = "inbox"
    @State private var relative = false
    @State private var date = Date()
    var body: some View {
        NavigationStack { Form {
            Text(template.title).font(.headline)
            Picker("保存到", selection: $list) { Text("待整理").tag("inbox"); ForEach(store.projection.lists) { Text($0.title).tag($0.id) } }
            Toggle("安排相对日期", isOn: $relative)
            if relative { LifeDatePicker("第一项的日期", selection: $date, displayedComponents: .date) }
            Text(relative ? "按模板原有的相对天数安排任务，保留原有时间。" : "新建内容不带日期；之后再安排。").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).paperSurface().navigationTitle("使用模板").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("创建") {
                var fields: [String: Value] = ["listID": .string(list)]
                if relative { fields["anchor"] = .date(Calendar.current.startOfDay(for: date)) }
                if let id = store.perform("template.use", id: template.id, fields: fields)?.records.first?.id { created(id); dismiss() }
            } }
        } }.frame(idealWidth: 450, idealHeight: 350)
    }
}

struct HistoryView: View {
    @Environment(DaylineStore.self) private var store
    var taskID: String? = nil
    @State private var selected: ChangeEvent?
    private var history: [ChangeEvent] { store.projection.visibleHistory(store.events).filter { taskID == nil || $0.changes.contains { $0.entity == taskID } }.sorted { $0.clock > $1.clock } }
    var body: some View {
        List(history) { event in
            DisclosureGroup {
                ForEach(Array(event.changes.enumerated()), id: \.offset) { _, change in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.projection.records[change.entity]?.title ?? "视图设置").font(.headline)
                        ForEach(change.fields.keys.sorted(), id: \.self) { key in
                            Text("\(label(key))：\(describe(change.fields[key]!, key: key))").font(.caption).textSelection(.enabled)
                        }
                    }.padding(.vertical, 6)
                }
                Button("撤回这次修改") { selected = event }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(event.changes.first.flatMap { store.projection.records[$0.entity]?.title } ?? "视图设置").lineLimit(1)
                    Text(event.createdAt.formatted(date: .abbreviated, time: .shortened) + " · \(event.changes.count) 项变更").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 7)
            }.listRowBackground(Color.clear)
        }.paperSurface().overlay { if history.isEmpty { ContentUnavailableView("暂无修改记录", systemImage: "clock.arrow.circlepath") } }
            .alert("撤回这次修改？", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
                Button("取消", role: .cancel) { selected = nil }
                Button("撤回") { if let selected { store.perform("event.undo", id: selected.id) }; selected = nil }
            } message: { Text("原始历史会保留。如果相关内容之后又被修改，系统会拒绝撤回，避免覆盖后续工作。") }
    }
    private func label(_ key: String) -> String { ["title":"标题", "notes":"正文", "richNotes":"正文格式", "due":"日期", "end":"结束时间", "completed":"完成", "trashed":"回收站", "progress":"进度", "pinned":"置顶", "section":"分组", "itemType":"类型", "listID":"专项", "priority":"优先级", "rank":"排序", "tags":"标签"] [key] ?? key }
    private func describe(_ v: Value, key: String) -> String {
        if key == "richNotes" { return "已保存文字格式" }
        if key == "snapshot" { return "已保存模板正文和子任务" }
        if key == "itemType" { return v.string == "note" ? "笔记" : "任务" }
        if key == "listID" { return v.string == "inbox" ? "待整理" : store.projection.records[v.string ?? ""]?.title ?? "原专项" }
        if key == "priority", let p = v.number { return Labels.priority(p) }
        if key == "progress", let p = v.number { return "\(p)%" }
        if ["due", "end", "reminder", "createdAt", "completedAt"].contains(key), let date = v.date { return date.formatted(date: .abbreviated, time: .shortened) }
        switch v { case .string(let s): return s.count > 250 ? String(s.prefix(250)) + "…" : s; case .number(let n): return "\(n)"; case .flag(let b): return b ? "是" : "否"; case .strings(let a): return a.joined(separator: "、"); case .null: return "清除" } }
}
