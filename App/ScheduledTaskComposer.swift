import SwiftUI

struct ScheduledTaskComposer: View {
    @Environment(DaylineStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onCreated: (String) -> Void
    @State private var title = ""
    @State private var date: Date
    @State private var projectID = "inbox"
    @FocusState private var focused: Bool

    init(date: Date, onCreated: @escaping (String) -> Void) {
        _date = State(initialValue: date)
        self.onCreated = onCreated
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("任务标题", text: $title, axis: .vertical).focused($focused)
                LifeDatePicker("日期", selection: $date, displayedComponents: .date)
                Picker("专项", selection: $projectID) {
                    Text("待整理").tag("inbox")
                    ForEach(store.projection.lists.filter { !$0.archived && $0["listType"].string != "note" }) { project in
                        Text(project.title).tag(project.id)
                    }
                }
            }.formStyle(.grouped).paperSurface().navigationTitle("添加任务")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.keyboardShortcut(.cancelAction) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("添加并打开", action: create)
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }.daylineTheme()
        #if os(macOS)
        .frame(width: 460, height: 320)
        #else
        .presentationDetents([.medium, .large])
        #endif
        .onAppear { focused = true }
    }
    private func create() {
        let fields: [String: Value] = ["title": .string(title), "listID": .string(projectID),
            "due": .date(Calendar.current.startOfDay(for: date)), "allDay": .flag(true)]
        guard let id = store.perform("task.add", fields: fields)?.records.first?.id else { return }
        dismiss(); onCreated(id)
    }
}
