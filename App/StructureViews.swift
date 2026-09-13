import SwiftUI

struct ProjectDraft: Identifiable {
    let id = UUID()
    let directionID: String?
}

struct DirectionProjectsView: View {
    @Environment(DaylineStore.self) private var store
    let directionID: String
    let newProject: (String?) -> Void
    let editDirection: (Record) -> Void
    let openProject: (Record) -> Void
    var body: some View {
        ScrollView {
            if let direction = store.projection.records[directionID] {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        if !direction.notes.isEmpty { Text(direction.notes).foregroundStyle(.secondary) }
                        Spacer()
                        Menu {
                            Button("编辑方向") { editDirection(direction) }
                            Button("新建专项") { newProject(direction.id) }
                        } label: { Image(systemName: "ellipsis").iconTarget() }
                            .accessibilityLabel("\(direction.title)的操作")
                    }
                    ForEach(Structure.projects(in: direction.id, projection: store.projection)) { projectCard($0) }
                    Button { newProject(direction.id) } label: { Label("新建专项", systemImage: "plus") }.buttonStyle(.ink)
                }.padding(24).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.paperSurface()
    }
    private func projectCard(_ project: Record) -> some View {
        let tasks = store.projection.query(TaskFilter(listID: project.id)).filter { $0.parentID == nil }
        return Button { openProject(project) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.stack").padding(.top, 3)
                VStack(alignment: .leading, spacing: 7) {
                    Text(project.title).font(.headline)
                    ForEach(tasks.prefix(3)) { task in Text(task.title).font(.subheadline).lineLimit(1).foregroundStyle(.secondary) }
                }
                Spacer(); Image(systemName: "chevron.right").font(.caption).padding(.top, 4)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.ink).background(Color.paperInset, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct DirectionEditor: View {
    @Environment(DaylineStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let existing: Record?
    @State private var title: String
    @State private var notes: String
    init(existing: Record? = nil) {
        self.existing = existing; _title = State(initialValue: existing?.title ?? ""); _notes = State(initialValue: existing?.notes ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("方向名称", text: $title)
                Section("这个方向对你意味着什么（可选）") { TextEditor(text: $notes).frame(minHeight: 100) }
                if let existing, !store.projection.lists.contains(where: { $0.directionID == existing.id }) {
                    Button("删除空方向") { if store.perform("direction.update", id: existing.id, fields: ["trashed": .flag(true)]) != nil { dismiss() } }
                }
            }.formStyle(.grouped).paperSurface().navigationTitle(existing == nil ? "新建方向" : "编辑方向")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            if store.perform(existing == nil ? "direction.add" : "direction.update", id: existing?.id, fields: ["title": .string(title.trimmingCharacters(in: .whitespacesAndNewlines)), "notes": .string(notes)]) != nil { dismiss() }
                        }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }.frame(idealWidth: 470, idealHeight: 380)
    }
}

struct NewListView: View {
    @Environment(DaylineStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let existing: Record?
    @State private var title: String
    @State private var direction: String
    @State private var listType: String
    @State private var sections: String
    init(existing: Record? = nil, directionID: String? = nil) {
        self.existing = existing; _title = State(initialValue: existing?.title ?? "")
        _direction = State(initialValue: existing?.directionID ?? directionID ?? "")
        _listType = State(initialValue: existing?["listType"].string ?? "task")
        _sections = State(initialValue: existing?.sections.joined(separator: "\n") ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("专项名称", text: $title)
                Picker("所属方向", selection: $direction) {
                    Text("选择方向").tag("")
                    ForEach(store.projection.directions) { Text($0.title).tag($0.id) }
                }
                Picker("默认新增", selection: $listType) { Text("任务").tag("task"); Text("笔记").tag("note") }
                Section("任务分组 / 看板分栏（可选，每行一组）") {
                    TextEditor(text: $sections).frame(minHeight: 140)
                    Text("用于专项内部的执行阶段；具体行动请创建任务和子任务。").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).paperSurface().navigationTitle(existing == nil ? "新建专项" : "编辑专项")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            let groups = sections.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                            let fields: [String: Value] = ["title": .string(title), "directionID": .string(direction), "folder": .null, "listType": .string(listType), "sections": .strings(groups)]
                            if store.perform(existing == nil ? "project.add" : "project.update", id: existing?.id, fields: fields) != nil { dismiss() }
                        }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.projection.directions.contains(where: { $0.id == direction }))
                    }
                }
        }.frame(idealWidth: 470, idealHeight: 520)
    }
}
