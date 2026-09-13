import SwiftUI

struct TaskEditor: View {
    @Environment(DaylineStore.self) private var store
    let id: String
    @State private var title = ""
    @State private var notes = ""
    @State private var titleDirty = false
    @State private var notesDirty = false
    @State private var originalTitle = ""
    @State private var originalNotes = ""
    @State private var originalTags = ""
    @State private var tags = ""
    @State private var childTitle = ""
    @State private var dragSession = TaskDragSession()
    @State private var subtaskParent: Record?
    @State private var saveTask: Task<Void, Never>?
    @State private var loaded = false
    @State private var rich = ""
    @State private var originalRich = ""
    @State private var showHistory = false
    @State private var showNotesFocus = false
    @State private var focusedNotesController = RichEditorController()
    @State private var progress = 0.0
    var task: Record? { store.projection.records[id] }
    var body: some View {
        if let task, !store.projection.isPurged(task) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ancestry(task)
                    header(task)
                    Divider()
                    if store.projection.isHidden(task) {
                        Label("任务在回收站中", systemImage: "trash").foregroundStyle(.secondary)
                        if task.trashed { Button("恢复任务") { store.perform("task.restore", id: id) }.buttonStyle(.borderedProminent) }
                        else { Text("恢复父任务后，这个子任务也会重新出现。").font(.caption).foregroundStyle(.secondary) }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(task.isNote ? "正文" : "备注").font(.subheadline.bold())
                            RichTextEditor(text: notesBinding, rich: richBinding, toggleFocus: {
                                saveTask?.cancel(); save(); showNotesFocus = true
                            })
                        }
                        children(task)
                        Divider()
                        DisclosureGroup("归属、进度与日期") {
                            VStack(alignment: .leading, spacing: 24) {
                                organization(task)
                                if !task.isNote { schedule(task) }
                            }.padding(.top, 16)
                        }.font(.subheadline.weight(.medium))
                        Divider()
                        HStack {
                            Text(task.completed ? "已完成" : "所有修改自动保存").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { store.perform("task.trash", id: id) } label: { Image(systemName: "trash") }.buttonStyle(.ink).foregroundStyle(.secondary).help("移入回收站")
                        }
                    }
                }.padding(24)
            }.paperSurface()
                .onAppear { if !loaded { load(task) } }
                .onChange(of: task.revision) { _, _ in
                    if !titleDirty { originalTitle = task.title; title = task.title }
                    if !notesDirty { originalNotes = task.notes; notes = task.notes }
                    if rich == originalRich { rich = task["richNotes"].string ?? ""; originalRich = rich }
                    progress = Double(task.progress)
                    if tags == originalTags { originalTags = task.tags.joined(separator: ", "); tags = originalTags }
                }
                .onDisappear { saveTask?.cancel(); save() }
                .sheet(item: $subtaskParent) { parent in SubtaskComposer(parent: parent) { childID in NotificationCenter.default.post(name: .daylineOpenTask, object: childID) }.environment(store) }
                .sheet(isPresented: $showHistory) { NavigationStack { HistoryView(taskID: id).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showHistory = false } } }.navigationTitle("修改历史") }.frame(idealWidth: 550, idealHeight: 600) }
                #if os(macOS)
                .background {
                    NotesFocusWindow(isPresented: $showNotesFocus, content: AnyView(focusedNotes), close: closeNotesFocus)
                        .frame(width: 0, height: 0)
                }
                #else
                .fullScreenCover(isPresented: $showNotesFocus, onDismiss: { saveTask?.cancel(); save() }) {
                    focusedNotes.interactiveDismissDisabled()
                }
                #endif
        }
    }
    private var notesBinding: Binding<String> {
        Binding(get: { notes }, set: { value in
            notes = value
            if loaded { notesDirty = notes != originalNotes; if notesDirty { scheduleSave() } }
        })
    }
    private var richBinding: Binding<String> {
        Binding(get: { rich }, set: { value in
            rich = value
            if loaded && rich != originalRich { scheduleSave() }
        })
    }
    private var focusedNotes: some View {
        FocusedNotesView(title: title, text: notesBinding, rich: richBinding, controller: focusedNotesController, close: closeNotesFocus)
    }
    private func closeNotesFocus() {
        focusedNotesController.finishEditing?()
        saveTask?.cancel(); save(); showNotesFocus = false
    }
    @ViewBuilder private func ancestry(_ task: Record) -> some View {
        let parents = TaskOutline.ancestors(of: task, records: store.projection.records)
        if !parents.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(parents) { parent in
                        Button { save(); NotificationCenter.default.post(name: .daylineOpenTask, object: parent.id) } label: {
                            Text(parent.title).lineLimit(1)
                        }.buttonStyle(.ink).accessibilityLabel("返回上级任务：\(parent.title)")
                        Image(systemName: "chevron.right").font(.caption2).accessibilityHidden(true)
                    }
                    Text("第 \(parents.count + 1) 层").foregroundStyle(.secondary)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func header(_ task: Record) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                if !task.isNote { Button { save(); store.toggle(task) } label: { Label(task.completed ? "已完成" : "标记完成", systemImage: task.completed ? "checkmark.circle.fill" : "circle") }.buttonStyle(.ink).foregroundStyle(task.completed ? Color.secondary : Color.ink).disabled(store.projection.isHidden(task)) }
                else { Label("笔记", systemImage: "note.text").foregroundStyle(Color.ink) }
                Spacer()
                Menu {
                    Button(task.pinned ? "取消置顶" : "置顶") { store.update(id, ["pinned": .flag(!task.pinned)]) }
                    Button("复制任务链接") { Clipboard.copy(TaskLink.url(id).absoluteString) }
                    Button("保存为模板") { save(); store.perform("template.save", id: id) }
                    Button(task.isNote ? "转换为任务" : "转换为笔记") { save(); store.perform("task.convert", id: id, fields: ["itemType": .string(task.isNote ? "task" : "note")]) }
                    if task.parentID != nil { Button("提升为独立任务") { store.update(id, ["parentID": .null]) } }
                    Button("修改历史") { showHistory = true }
                } label: { Image(systemName: "ellipsis").iconTarget() }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("任务操作")
                Menu { ForEach(0..<4) { p in Button(Labels.priority(p)) { store.update(id, ["priority": .number(p)]) } } } label: {
                    HStack(spacing: 3) { Image(systemName: task.priority == 0 ? "flag" : "flag.fill"); if task.priority > 0 { Text(String(repeating: "!", count: task.priority)).font(.caption.weight(.semibold)) } }.foregroundStyle(Labels.priorityColor(task.priority)).iconTarget()
                }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel(Labels.priority(task.priority))
            }
            TextField("任务标题", text: $title, axis: .vertical).font(.title2.weight(.semibold)).textFieldStyle(.plain).lineLimit(1...5)
                .onChange(of: title) { _, _ in if loaded { titleDirty = title != originalTitle; if titleDirty { scheduleSave() } } }.onSubmit(save)
                .disabled(store.projection.isHidden(task))
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text("标题不能为空，原来的标题仍然保留。").font(.caption).foregroundStyle(Color.ink) }
        }
    }
    private func schedule(_ task: Record) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("时间安排").font(.subheadline.weight(.semibold))
            Toggle("设置日期", isOn: Binding(get: { task.due != nil }, set: { enabled in
                if enabled { store.update(id, ["due": .date(Calendar.current.startOfDay(for: Date()))]) }
                else { store.update(id, ["due": .null, "end": .null, "recurrence": .string("none")]) }
            }))
            if let due = task.due {
                LifeDatePicker("日期", selection: Binding(get: { due }, set: { store.reschedule(task, to: $0) }), displayedComponents: task.allDay ? [.date] : [.date, .hourAndMinute])
                Toggle("全天", isOn: Binding(get: { task.allDay }, set: { store.update(id, ["allDay": .flag($0)]) }))
                Toggle("设置结束时间", isOn: Binding(get: { task.end != nil }, set: { store.update(id, ["end": $0 ? .date(due.addingTimeInterval(task.allDay ? 86400 : 3600)) : .null]) }))
                if let end = task.end {
                    LifeDatePicker("结束", selection: Binding(get: { end }, set: { store.update(id, ["end": .date($0)]) }), in: due.addingTimeInterval(60)..., displayedComponents: task.allDay ? [.date] : [.date, .hourAndMinute])
                }
                Picker("重复", selection: Binding(get: { task.recurrence }, set: { store.update(id, ["recurrence": .string($0)]) })) {
                    ForEach(Recurrence.choices, id: \.self) { Text(Labels.repeatRule($0)).tag($0) }
                }
            }
        }.font(.subheadline)
    }
    private func organization(_ task: Record) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("方向", value: store.projection.records[store.projection.records[task.listID]?.directionID ?? ""]?.title ?? "尚未归类")
            Picker("专项", selection: Binding(get: { task.listID }, set: { store.update(id, ["listID": .string($0)]) })) {
                Text("待整理").tag("inbox")
                ForEach(store.projection.directions) { direction in
                    Section(direction.title) { ForEach(Structure.projects(in: direction.id, projection: store.projection)) { Text($0.title).tag($0.id) } }
                }
                Section("其他专项") {
                    ForEach(store.projection.lists.filter { $0.archived || $0.directionID == nil }) { Text($0.title).tag($0.id) }
                }
            }.disabled(task.parentID != nil)
            if task.parentID != nil { Text("子任务跟随父任务的专项。").font(.caption).foregroundStyle(.secondary) }
            let sections = store.projection.records[task.listID]?.sections ?? []
            if !sections.isEmpty || !task.section.isEmpty {
                Picker("分组", selection: Binding(get: { task.section }, set: { store.update(id, ["section": .string($0)]) })) {
                    Text("未分组").tag("")
                    ForEach(Array(Set(sections + (task.section.isEmpty ? [] : [task.section]))).sorted(), id: \.self) { Text($0).tag($0) }
                }
            }
            if !task.isNote {
                HStack { Text("进度"); Spacer(); Text("\(Int(progress))%").monospacedDigit() }
                Slider(value: $progress, in: 0...100, step: 1) { editing in if !editing { store.update(id, ["progress": .number(Int(progress))]) } }.disabled(task.completed)
            }
            if !task.completed && !task.isNote {
                Picker("状态", selection: Binding(get: { task.status }, set: { store.update(id, ["status": .string($0)]) })) { Text("待办").tag("todo"); Text("进行中").tag("doing") }
            }
            HStack { Image(systemName: "number").foregroundStyle(.secondary); TextField("标签，用逗号分隔", text: $tags).textFieldStyle(.plain).onSubmit(save).onChange(of: tags) { _, _ in if loaded && tags != originalTags { scheduleSave() } } }
            if let parent = task.parentID, let parentTask = store.projection.records[parent] { Button { NotificationCenter.default.post(name: .daylineOpenTask, object: parent) } label: { Label("返回父任务 · \(parentTask.title)", systemImage: "arrow.turn.up.left") }.buttonStyle(.ink).font(.caption) }
        }.font(.subheadline)
    }
    private func children(_ task: Record) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let children = TaskOrdering.sorted(store.projection.children(of: id), by: "manual")
            HStack { Text("子任务").font(.subheadline.weight(.semibold)); Spacer(); Text("\(children.filter(\.completed).count)/\(children.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            ForEach(children) { child in
                HStack(alignment: .taskTitleCenter) {
                    TaskRow(task: child, select: { NotificationCenter.default.post(name: .daylineOpenTask, object: child.id) }, dragSession: dragSession)
                    let count = store.projection.children(of: child.id).count
                    if count > 0 { Label("\(count)", systemImage: "list.bullet.indent").font(.caption).foregroundStyle(.secondary).accessibilityLabel("\(count) 项下级任务") }
                    Menu {
                        Button("添加子任务") { save(); subtaskParent = child }
                        Button("移入回收站") { store.perform("task.trash", id: child.id) }
                    } label: { Image(systemName: "ellipsis").iconTarget() }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("子任务操作：\(child.title)")
                    TaskDragHandle(task: child, session: dragSession)
                }.font(.subheadline).padding(.vertical, 3)
                    .modifier(TaskReorderTarget(task: child, session: dragSession, rows: children, viewID: "view:" + task.listID))
            }
            HStack {
                Image(systemName: "plus").foregroundStyle(.secondary)
                TextField("添加子任务", text: $childTitle).textFieldStyle(.plain).onSubmit { addChild(task) }
                if !childTitle.isEmpty {
                    Button { addChild(task) } label: { Image(systemName: "arrow.up.circle.fill") }
                        .buttonStyle(.ink).accessibilityLabel("保存子任务")
                }
            }.padding(10).background(Color.daylineSecondary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
    private func addChild(_ task: Record) {
        save()
        if let childID = store.addQuick(childTitle, listID: task.listID, parentID: id) {
            childTitle = ""
            NotificationCenter.default.post(name: .daylineRevealTask, object: childID)
        }
    }
    private func load(_ task: Record) { loaded = false; rich = task["richNotes"].string ?? ""; originalRich = rich; progress = Double(task.progress); originalTitle = task.title; originalNotes = task.notes; originalTags = task.tags.joined(separator: ", "); title = originalTitle; notes = originalNotes; tags = originalTags; titleDirty = false; notesDirty = false; loaded = true }
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(500)); save() } catch { }
        }
    }
    private func save() {
        var fields: [String: Value] = [:]
        if titleDirty, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields["title"] = .string(title) }
        if notesDirty { fields["notes"] = .string(notes) }
        if rich != originalRich { fields["richNotes"] = .string(rich); fields["notes"] = .string(notes) }
        if tags != originalTags { fields["tags"] = .strings(Array(Set(tags.split(whereSeparator: { $0 == "," || $0 == "，" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()) }
        guard !fields.isEmpty else { return }
        if store.perform("task.update", id: id, fields: fields) != nil {
            if fields["title"] != nil { originalTitle = title; titleDirty = false }
            if fields["notes"] != nil { originalNotes = notes; notesDirty = false }
            if fields["richNotes"] != nil { originalRich = rich }
            if fields["tags"] != nil { originalTags = tags }
        }
    }
}

struct SubtaskComposer: View {
    @Environment(DaylineStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let parent: Record
    let onCreated: (String) -> Void
    @State private var title = ""
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("上级任务 · " + parent.title).font(.subheadline).foregroundStyle(.secondary)
                TextField("子任务标题", text: $title, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(2...5).focused($focused)
                    .onSubmit(create)
                Spacer(minLength: 0)
            }.padding(24).paperSurface().navigationTitle("添加子任务")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("添加并打开", action: create).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }.daylineTheme()
        #if os(macOS)
        .frame(width: 440, height: 260)
        #else
        .presentationDetents([.medium])
        #endif
        .onAppear { focused = true }
    }
    private func create() {
        guard let id = store.addQuick(title, listID: parent.listID, parentID: parent.id) else { return }
        dismiss(); onCreated(id)
    }
}
