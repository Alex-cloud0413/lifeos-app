import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(DaylineStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    let pageRoute: String?
    @State private var phoneNavigation: PhoneNavigation
    @State private var route: String? = "inbox"
    init(pageRoute: String? = nil, phoneNavigation: PhoneNavigation? = nil) {
        self.pageRoute = pageRoute
        _phoneNavigation = State(initialValue: phoneNavigation ?? PhoneNavigation())
    }
    @State private var selectedTask: String?
    @State private var collapsedTasks: Set<String> = []
    @State private var dragSession = TaskDragSession()
    @State private var subtaskParent: Record?
    @State private var search = ""
    @State private var quickText = ""
    @State private var mode = "list"
    @State private var searching = false
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var showSettings = false
    @State private var trashSnapshot: [Record]?
    @State private var showDirectionSheet = false
    @State private var editingDirection: Record?
    @State private var projectDraft: ProjectDraft?
    @State private var taskDraft: ProjectTaskDraft?
    @State private var showFilterSheet = false
    @State private var showBatch = false
    @State private var editingList: Record?
    @State private var editingFilter: Record?
    @FocusState private var quickFocused: Bool
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    private var currentRoute: String { pageRoute ?? route ?? "inbox" }
    private var sort: String { store.projection.records["view:" + currentRoute]?["sort"].string ?? "manual" }
    private var grouping: String { store.projection.records["view:" + currentRoute]?["group"].string ?? "none" }
    private var toolRoute: Bool { ["templates", "history"].contains(currentRoute) || currentRoute.hasPrefix("direction:") }
    private var spacious: Bool { currentRoute == "calendar" || toolRoute || mode == "board" }
    private var currentList: String? { currentRoute.hasPrefix("list:") ? currentRoute : nil }
    private var filter: TaskFilter {
        let r = currentRoute
        var f = TaskFilter(view: r == "calendar" || toolRoute ? "all" : r, search: search)
        if r == "inbox" { f.view = "all"; f.listID = "inbox" }
        if let currentList { f.view = "all"; f.listID = currentList; f.itemType = "all" }
        if r == "notes" { f.itemType = "note" }
        if r.hasPrefix("tag:") { f.view = "all"; f.tag = String(r.dropFirst(4)); f.itemType = "all" }
        if r.hasPrefix("filter:"), let data = store.projection.records[r]?["query"].string?.data(using: .utf8), let saved = try? JSONDecoder().decode(TaskFilter.self, from: data) { f = saved; if !search.isEmpty { f.search = search } }
        if mode == "board" && r != "calendar" { f.includeCompleted = true }
        return f
    }
    private var tasks: [Record] { TaskOrdering.sorted(store.projection.query(filter), by: sort) }
    private var outline: TaskOutline { TaskOutline(matching: tasks, records: store.projection.records, sort: sort) }
    private var visibleRows: [TaskOutline.Row] { outline.rows(collapsed: search.isEmpty ? collapsedTasks : []) }
    private var title: String {
        if let record = store.projection.records[currentRoute] {
            if currentList != nil {
                let direction = store.projection.records[record.directionID ?? ""]?.title ?? "待归类专项"
                return record.title + " · " + direction
            }
            return record.title
        }
        if currentRoute.hasPrefix("tag:") { return "#" + String(currentRoute.dropFirst(4)) }
        return [ "all":"全部任务", "inbox":"待整理", "calendar":"日历", "notes":"笔记", "templates":"模板", "history":"修改历史", "completed":"已完成", "trash":"回收站"][currentRoute] ?? "任务"
    }
    var body: some View {
        navigation
            #if os(macOS)
            .searchable(text: $search, isPresented: $searching, prompt: "搜索任务、笔记或标签")
            #endif
            .alert("操作未完成", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) { Button("好") { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
            .sheet(item: $subtaskParent) { parent in SubtaskComposer(parent: parent, onCreated: openTask).environment(store) }
            .sheet(isPresented: $showSettings) { SettingsView().environment(store) }
            .confirmationDialog("清空回收站？", isPresented: Binding(get: { trashSnapshot != nil }, set: { if !$0 { trashSnapshot = nil } }), titleVisibility: .visible) {
                Button("清空回收站", role: .destructive) {
                    guard let snapshot = trashSnapshot else { return }
                    if store.perform("trash.empty", fields: ["confirm": .flag(true), "ids": .strings(snapshot.map(\.id)), "revisions": .strings(snapshot.map(\.revision))]) != nil {
                        selectedTask = nil; selection.removeAll(); selecting = false
                    }
                    trashSnapshot = nil
                }
                Button("取消", role: .cancel) { trashSnapshot = nil }
            } message: { Text("回收站中的全部内容将从所有设备移除，包括任务、子任务和已删除的专项。清空后无法在 App 中恢复。") }
            .sheet(item: $projectDraft) { NewListView(directionID: $0.directionID).environment(store) }
            .sheet(item: $taskDraft) { draft in ProjectTaskComposer(project: draft.project, onCreated: openTask).environment(store) }
            .sheet(isPresented: $showDirectionSheet) { DirectionEditor().environment(store) }
            .sheet(item: $editingDirection) { DirectionEditor(existing: $0).environment(store) }
            .sheet(isPresented: $showFilterSheet) { FilterEditor().environment(store) }
            .sheet(item: $editingList) { NewListView(existing: $0).environment(store) }
            .sheet(item: $editingFilter) { FilterEditor(existing: $0).environment(store) }
            .sheet(isPresented: $showBatch) { BatchEditor(ids: Array(selection)).environment(store) }
            .onReceive(NotificationCenter.default.publisher(for: .daylineQuickAdd)) { _ in if pageRoute == nil { beginAdding() } }
            .onReceive(NotificationCenter.default.publisher(for: .daylineSearch)) { _ in if pageRoute == nil { openRoute("all"); searching = true } }
            .onReceive(NotificationCenter.default.publisher(for: .daylineRevealTask)) { note in
                if let id = note.object as? String, let task = store.projection.records[id] {
                    for ancestor in TaskOutline.ancestors(of: task, records: store.projection.records) { collapsedTasks.remove(ancestor.id) }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .daylineOpenTask)) { note in if pageRoute == nil, let id = note.object as? String { openTask(id) } }
            .onOpenURL { if pageRoute == nil, let id = TaskLink.id(from: $0) { openTask(id) } }
            .onChange(of: search) { _, value in if !value.isEmpty && toolRoute { route = "all" } }
            .onChange(of: route) { _, _ in
                selectedTask = nil; selecting = false; selection.removeAll()
            }
            #if os(iOS)
            .onChange(of: selectedTask) { _, id in
                if let id { openTask(id); selectedTask = nil }
            }
            #endif
            .onChange(of: scenePhase) { _, phase in if pageRoute == nil && phase == .active {
                do { try store.reload() } catch { store.errorMessage = error.localizedDescription }
                store.consumeSharedInbox()
            } }
            .onAppear { if pageRoute == nil { store.consumeSharedInbox() } }
    }
    private func openTask(_ id: String) {
        do { try store.reload() } catch { store.errorMessage = error.localizedDescription }
        guard let item = store.projection.records[id], !store.projection.isPurged(item) else { store.errorMessage = "任务尚未同步到本机，或链接已经失效。请等待同步完成后重试。"; return }
        for parent in TaskOutline.ancestors(of: item, records: store.projection.records) { collapsedTasks.remove(parent.id) }
        #if os(iOS)
        phoneNavigation.path = TaskNavigation.opening(id, from: phoneNavigation.path, projection: store.projection)
        #else
        let destination = store.projection.isHidden(item) ? "trash" : item.listID == "inbox" ? (item.isNote ? "notes" : "inbox") : item.listID
        if currentRoute != destination { openRoute(destination) }
        DispatchQueue.main.async { selectedTask = id }
        #endif
    }
    @ViewBuilder private var navigation: some View {
        #if os(macOS)
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar.navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            Group {
                if selectedTask != nil || !spacious {
                    TaskWorkspaceSplit(
                        list: AnyView(content.environment(store).daylineTheme()),
                        detail: AnyView(detailPane.environment(store).daylineTheme())
                    )
                } else { content }
            }.navigationTitle(title).toolbar { toolbar }
        }
        #else
        if pageRoute != nil {
            content.navigationTitle(currentList == nil ? title : "").toolbar { toolbar }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .searchable(text: $search, isPresented: $searching, prompt: "搜索任务、笔记或标签")
        } else {
            NavigationStack(path: $phoneNavigation.path) {
                sidebar
                    .navigationDestination(for: TaskDestination.self) { destination in
                        switch destination {
                        case .page(let value):
                            RootView(pageRoute: value, phoneNavigation: phoneNavigation)
                        case .task(let id):
                            TaskEditor(id: id).id(id)
                                .navigationTitle("任务详情")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar(.visible, for: .navigationBar)
                        }
                    }
            }
        }
        #endif
    }
    @ViewBuilder private var detailPane: some View {
        if let id = selectedTask, store.projection.records[id] != nil {
            VStack(spacing: 0) {
                HStack {
                    Text("详情").foregroundStyle(.secondary)
                    Spacer()
                    Button { selectedTask = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.ink).accessibilityLabel("关闭详情")
                }.padding(16)
                Divider()
                TaskEditor(id: id).id(id)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("选择任务", systemImage: "checkmark.circle", description: Text("查看详情与安排。"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private var sidebar: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            sidebarBrand.padding(20)
            #endif
            List {
                Section {
                    nav("待整理", "tray", "inbox")
                }
                Section("方向") {
                    ForEach(store.projection.directions) { direction in
                        DisclosureGroup {
                            ForEach(Structure.projects(in: direction.id, projection: store.projection)) { listRow($0) }
                            Button("新建专项") { projectDraft = ProjectDraft(directionID: direction.id) }
                        } label: {
                            Button { navigate(direction.id) } label: { Text(direction.title).foregroundStyle(Color.ink) }.buttonStyle(.plain)
                        }.listRowBackground(Color.clear).contextMenu { Button("编辑方向") { editingDirection = direction } }
                    }
                    Button { showDirectionSheet = true } label: { Label("新建方向", systemImage: "plus") }
                }
                let unassigned = store.projection.lists.filter { !$0.archived && (store.projection.records[$0.directionID ?? ""]?.kind != "direction" || store.projection.records[$0.directionID ?? ""]?.trashed == true) }
                if !unassigned.isEmpty { Section("待归类专项") { ForEach(unassigned) { listRow($0) } } }
                if store.projection.lists.contains(where: \.archived) { Section("已归档专项") { ForEach(store.projection.lists.filter(\.archived)) { listRow($0) } } }
                Section("辅助视图") {
                    nav("全部任务", "tray.full", "all"); nav("日历", "calendar", "calendar")
                    nav("笔记", "note.text", "notes"); nav("模板", "square.on.square", "templates")
                }
                Section("筛选") {
                    ForEach(store.projection.filters) { item in nav(item.title, "line.3.horizontal.decrease.circle", item.id).contextMenu {
                        Button("编辑筛选") { editingFilter = item }
                        Button("删除筛选") { store.perform("filter.update", id: item.id, fields: ["trashed": .flag(true)]) }
                    } }
                    Button { showFilterSheet = true } label: { Label { Text("新建筛选") } icon: { Image(systemName: "plus").foregroundStyle(Color.ink) } }
                }
                let tags = Array(Set(store.projection.tasks.filter { !store.projection.isHidden($0) }.flatMap(\.tags))).sorted()
                if !tags.isEmpty { Section("标签") { ForEach(tags, id: \.self) { nav($0, "number", "tag:" + $0) } } }
                Section { nav("修改历史", "clock.arrow.circlepath", "history"); nav("已完成", "checkmark.circle", "completed"); nav("回收站", "trash", "trash") }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
                #if os(iOS)
                .contentMargins(.top, 0, for: .scrollContent)
                #endif
            Button { showSettings = true } label: { Label("设置与同步", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.ink).padding(18)
        }
        #if os(iOS)
        // Keep the brand in the viewport's safe area, outside the bouncing list.
        // An unused large-title navigation bar used to resize this whole column.
        .safeAreaInset(edge: .top, spacing: 0) {
            sidebarBrand.padding(.horizontal, 20).padding(.vertical, 10)
                .background { PaperSurface() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .paperSurface()
    }
    private var sidebarBrand: some View {
        HStack(spacing: 12) {
            DaylineMark().frame(width: 30, height: 30)
            Text("Life · OS").font(.headline)
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine).accessibilityIdentifier("sidebarBrand")
    }
    private func navigate(_ value: String) { openRoute(value) }
    private func openRoute(_ value: String) {
        #if os(iOS)
        phoneNavigation.path = TaskNavigation.pages(for: value, records: store.projection.records)
        #else
        route = value
        #endif
    }
    private func openProject(_ project: Record) { openRoute(project.id) }
    private func nav(_ name: String, _ icon: String, _ value: String) -> some View {
        Button { navigate(value) } label: {
            Label { Text(name) } icon: { Image(systemName: icon) }.foregroundStyle(Color.ink)
                .padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).listRowBackground(Color.clear)
    }
    private func listRow(_ list: Record) -> some View {
        nav(list.title, list["listType"].string == "note" ? "note.text" : "square.stack", list.id)
            .contextMenu { Button("编辑专项与分组") { editingList = list }; Button(list.archived ? "取消归档" : "归档专项") { store.perform("list.update", id: list.id, fields: ["archived": .flag(!list.archived)]) } }
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        #if os(iOS)
        if let id = currentList, let project = store.projection.records[id] {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 4) {
                    Text(project.title).font(.subheadline.weight(.semibold))
                    Text("·").foregroundStyle(.secondary)
                    Text(store.projection.records[project.directionID ?? ""]?.title ?? "待归类专项")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.lineLimit(1).accessibilityElement(children: .ignore)
                    .accessibilityLabel(title).accessibilityIdentifier("projectHeading")
            }
        }
        #endif
        ToolbarItemGroup(placement: .primaryAction) {
            if currentRoute == "trash" {
                Button("清空回收站") { trashSnapshot = store.perform("trash.list")?.records }
                    .disabled(store.projection.trashRecords.isEmpty)
            }
            if !toolRoute && currentRoute != "calendar" {
                Menu {
                    Picker("显示", selection: $mode) { Text("列表").tag("list"); Text("看板").tag("board") }
                    Picker("排序", selection: Binding(get: { sort }, set: { saveView("sort", $0) })) {
                        Text("手动排序").tag("manual"); Text("优先级").tag("priority"); Text("日期").tag("date"); Text("标题").tag("title"); Text("创建时间").tag("created")
                    }
                    Picker("分组", selection: Binding(get: { grouping }, set: { saveView("group", $0) })) {
                        Text("不分组").tag("none"); Text("专项内分组").tag("section"); Text("按专项").tag("list"); Text("按优先级").tag("priority")
                    }
                    if let id = currentList, let list = store.projection.records[id] { Button("编辑专项与分组") { editingList = list } }
                    #if os(iOS)
                    if currentList != nil {
                        Button(selecting ? "退出批量选择" : "批量选择") { selecting.toggle(); selection.removeAll() }
                    }
                    #endif
                } label: { Image(systemName: "line.3.horizontal.decrease") }.accessibilityLabel("视图、排序与分组")
                #if os(macOS)
                Button { selecting.toggle(); selection.removeAll() } label: { Image(systemName: selecting ? "checkmark.circle.fill" : "checklist") }.accessibilityLabel("批量选择")
                #else
                if currentList == nil {
                    Button { selecting.toggle(); selection.removeAll() } label: { Image(systemName: selecting ? "checkmark.circle.fill" : "checklist") }.accessibilityLabel("批量选择")
                }
                #endif
            }
            if !toolRoute { Button(action: beginAdding) { Image(systemName: "plus") }.help("添加任务 ⌘N").accessibilityLabel("添加任务") }
        }
    }
    private func beginAdding() {
        if let id = currentList, let project = store.projection.records[id] {
            taskDraft = ProjectTaskDraft(project: project)
        } else {
            if toolRoute || ["trash", "completed"].contains(currentRoute) { route = "inbox" }
            DispatchQueue.main.async { quickFocused = true }
        }
    }
    private func saveView(_ key: String, _ value: String) { store.perform("view.update", id: "view:" + currentRoute, fields: [key: .string(value)]) }
    @ViewBuilder private var content: some View {
        if !store.ready { ContentUnavailableView("正在打开任务库", systemImage: "externaldrive") }
        else if currentRoute.hasPrefix("direction:") {
            DirectionProjectsView(directionID: currentRoute,
                              newProject: { projectDraft = ProjectDraft(directionID: $0) },
                              editDirection: { editingDirection = $0 },
                              openProject: openProject)
        }
        else if currentRoute == "templates" { TemplateLibrary(selectedTask: $selectedTask) }
        else if currentRoute == "history" { HistoryView() }
        else {
            VStack(spacing: 0) {
                if currentList == nil && !["trash", "completed"].contains(currentRoute) { quickAdd }
                if selecting { HStack {
                    Button(selection.count == tasks.count ? "取消全选" : "全选") { selection = selection.count == tasks.count ? [] : Set(tasks.map(\.id)) }
                    Text("已选 \(selection.count) 项").foregroundStyle(.secondary); Spacer()
                    Button("批量修改") { showBatch = true }.disabled(selection.isEmpty)
                }.padding(.horizontal, 20).padding(.bottom, 10) }
                if currentRoute == "calendar" { CalendarPlanner(selectedTask: $selectedTask, tasks: tasks) }
                else if mode == "board" { BoardView(tasks: outline.roots, selectedTask: $selectedTask, listID: currentList) }
                else { taskList }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).paperSurface()
        }
    }
    private var quickAdd: some View {
        HStack {
            Image(systemName: currentRoute == "notes" ? "note.text" : "plus").foregroundStyle(Color.ink)
            TextField(currentRoute == "notes" ? "添加笔记标题" : "添加任务标题", text: $quickText).textFieldStyle(.plain).focused($quickFocused).onSubmit(add)
            if !quickText.isEmpty { Button(action: add) { Image(systemName: "arrow.up.circle.fill") }.buttonStyle(.ink) }
        }.padding(13).background(Color.daylineSecondary, in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 20).padding(.vertical, 14)
    }
    private func add() {
        guard !quickText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let note = currentRoute == "notes" || store.projection.records[currentList ?? ""]?["listType"].string == "note"
        let fields: [String: Value] = ["title": .string(quickText), "listID": .string(currentList ?? "inbox"), "itemType": .string(note ? "note" : "task")]
        if let id = store.perform("task.add", fields: fields)?.records.first?.id { selectedTask = id; quickText = "" }
    }
    private var buckets: [(name: String, records: [Record])] {
        if grouping == "none" {
            let heading = currentList == nil ? "\(outline.roots.count) 项任务 · \(tasks.count - tasks.filter { $0.parentID == nil }.count) 项子任务" : ""
            return [(heading, outline.roots)]
        }
        let groups = Dictionary(grouping: outline.roots) { task -> String in
            switch grouping { case "section": return task.section.isEmpty ? "未分组" : task.section
            case "list": return store.projection.records[task.listID]?.title ?? "待整理"
            default: return Labels.priority(task.priority) }
        }
        return groups.keys.sorted().map { ($0, groups[$0]!) }
    }
    private var taskList: some View {
        Group {
            if tasks.isEmpty { ContentUnavailableView(search.isEmpty ? "这里还没有内容" : "没有匹配结果", systemImage: currentRoute == "notes" ? "note.text" : "tray", description: Text("添加内容，或切换专项查看。")) }
            else {
                List {
                    ForEach(buckets, id: \.name) { bucket in
                        Section {
                            let rootIDs = Set(bucket.records.map(\.id))
                            let rows = visibleRows.filter { rootIDs.contains($0.rootID) }
                            ForEach(rows) { item in
                                row(item, rows: rows).tag(item.id)
                            }
                            #if os(macOS)
                            .onMove { offsets, index in
                                TaskListInsertion.move(offsets: offsets, index: index, rows: rows.map(\.task),
                                    viewID: "view:" + currentRoute, store: store)
                            }
                            .onInsert(of: [UTType.text]) { index, providers in
                                TaskListInsertion.perform(index: index, providers: providers, rows: rows.map(\.task),
                                    session: dragSession, viewID: "view:" + currentRoute, store: store)
                            }
                            #endif
                        } header: {
                            if !bucket.name.isEmpty { Text(bucket.name) }
                        }
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden).frame(maxWidth: .infinity, maxHeight: .infinity)
                #if os(iOS)
                .contentMargins(.top, 0, for: .scrollContent)
                #endif
                #if os(macOS)
                .onMoveCommand { direction in
                    guard !selecting, !tasks.isEmpty else { return }
                    let rows = visibleRows
                    guard !rows.isEmpty else { return }
                    if direction == .left || direction == .right, let id = selectedTask,
                       let row = rows.first(where: { $0.id == id }) {
                        if direction == .right { collapsedTasks.remove(id) }
                        else if row.hasChildren && !collapsedTasks.contains(id) { collapsedTasks.insert(id) }
                        else { selectedTask = row.task.parentID }
                    } else {
                        let current = rows.firstIndex { $0.id == selectedTask } ?? (direction == .down ? -1 : rows.count)
                        let next = min(rows.count - 1, max(0, current + (direction == .down ? 1 : -1)))
                        selectedTask = rows[next].id
                    }
                }
                #endif
            }
        }
    }
    private func row(_ item: TaskOutline.Row, rows: [TaskOutline.Row]) -> some View {
        let task = item.task
        return HStack(alignment: .taskTitleCenter, spacing: 4) {
            Button {
                if !collapsedTasks.insert(task.id).inserted { collapsedTasks.remove(task.id) }
            } label: {
                Image(systemName: collapsedTasks.contains(task.id) && search.isEmpty ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(width: 22, height: 38).contentShape(Rectangle())
            }.buttonStyle(.plain).opacity(item.hasChildren ? 1 : 0).disabled(!item.hasChildren)
                .alignmentGuide(.taskTitleCenter) { $0[VerticalAlignment.center] }
                .accessibilityHidden(!item.hasChildren)
                .accessibilityLabel("\(collapsedTasks.contains(task.id) ? "展开" : "收起")子任务：\(task.title)")
            if item.depth > 6 { Text("\(item.depth + 1) 层").font(.caption2).foregroundStyle(.secondary) }

            if selecting { Button { if !selection.insert(task.id).inserted { selection.remove(task.id) } } label: { Image(systemName: selection.contains(task.id) ? "checkmark.circle.fill" : "circle") }.buttonStyle(.ink).accessibilityLabel("选择：\(task.title)") }
            TaskRow(task: task, select: {
                if selecting { if !selection.insert(task.id).inserted { selection.remove(task.id) } }
                else { selectedTask = task.id }
            }, dragSession: dragSession)
            if !selecting && !store.projection.isHidden(task) { TaskDragHandle(task: task, session: dragSession) }
        }.padding(.leading, CGFloat(min(item.depth, 6)) * 14)
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<min(item.depth, 6), id: \.self) { _ in
                        Rectangle().fill(Color.ink.opacity(0.12)).frame(width: 1).frame(width: 14)
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
            .foregroundStyle(Color.ink).listRowBackground(Color.clear)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("第 \(item.depth + 1) 层任务：\(task.title)")
            .contextMenu { taskMenu(task) }
            .modifier(TaskReorderTarget(task: task, session: dragSession, rows: rows.map(\.task), viewID: "view:" + currentRoute))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if !task.isNote { Button(task.completed ? "恢复" : "完成") { store.toggle(task) }.tint(Color.ink) }
                Button(task.trashed ? "恢复" : "回收站") { store.perform(task.trashed ? "task.restore" : "task.trash", id: task.id) }.tint(Color.ink)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button("移动") { selection = [task.id]; showBatch = true }.tint(Color.ink)
                if !task.isNote { Button("明天") { store.reschedule(task, to: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!) }.tint(Color.ink) }
            }
    }
    @ViewBuilder private func taskMenu(_ task: Record) -> some View {
        if task.trashed { Button("恢复") { store.perform("task.restore", id: task.id) } }
        else {
            Button("添加子任务") { collapsedTasks.remove(task.id); subtaskParent = task }
            if !task.isNote { Button(task.completed ? "恢复未完成" : "标记完成") { store.toggle(task) } }
            Button(task.pinned ? "取消置顶" : "置顶") { store.update(task.id, ["pinned": .flag(!task.pinned)]) }
            Button("复制") { if let id = store.perform("task.duplicate", id: task.id)?.records.first?.id { selectedTask = id } }
            Button("保存为模板") { store.perform("template.save", id: task.id) }
            ShareLink(item: TaskLink.url(task.id)) { Text("分享任务链接") }
            Button("复制任务链接") { Clipboard.copy(TaskLink.url(task.id).absoluteString) }
            Button("移入回收站") { store.perform("task.trash", id: task.id) }
        }
    }
}

private struct ProjectTaskDraft: Identifiable {
    let id = UUID()
    let project: Record
}

@Observable final class PhoneNavigation {
    var path: [TaskDestination] = []
}

private struct ProjectTaskComposer: View {
    @Environment(DaylineStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let project: Record
    let onCreated: (String) -> Void
    @State private var title = ""
    @FocusState private var focused: Bool
    private var isNote: Bool { project["listType"].string == "note" }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(project.title).font(.subheadline).foregroundStyle(.secondary)
                TextField(isNote ? "笔记标题" : "任务标题", text: $title, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(2...5).focused($focused).onSubmit(create)
                Spacer(minLength: 0)
            }.padding(24).paperSurface().navigationTitle(isNote ? "添加笔记" : "添加任务")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.keyboardShortcut(.cancelAction) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("添加并打开", action: create)
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }.daylineTheme()
        #if os(macOS)
        .frame(width: 440, height: 260)
        #else
        .presentationDetents([.medium, .large])
        #endif
        .onAppear { focused = true }
    }
    private func create() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let fields: [String: Value] = ["title": .string(title), "listID": .string(project.id), "itemType": .string(isNote ? "note" : "task")]
        guard let id = store.perform("task.add", fields: fields)?.records.first?.id else { return }
        dismiss(); onCreated(id)
    }
}

struct TaskRow: View {
    @Environment(DaylineStore.self) private var store
    let task: Record
    var select: (() -> Void)? = nil
    var dragSession: TaskDragSession? = nil
    private var titleHeight: CGFloat {
        #if os(iOS)
        44
        #else
        24
        #endif
    }
    private var hasMetadata: Bool { task.due != nil || task.recurrence != "none" || !task.tags.isEmpty || (!task.isNote && task.progress > 0) }
    var body: some View {
        HStack(alignment: .taskTitleCenter, spacing: 8) {
            Group {
                if task.isNote { Image(systemName: "note.text").foregroundStyle(Color.ink).iconTarget() }
                else {
                    Button { store.toggle(task) } label: {
                        Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(task.completed ? .secondary : Color.ink)
                    }.buttonStyle(.ink).disabled(store.projection.isHidden(task))
                        .accessibilityLabel("\(task.completed ? "恢复未完成" : "完成")：\(task.title)")
                }
            }.alignmentGuide(.taskTitleCenter) { $0[VerticalAlignment.center] }
            Group {
                if let select { Button(action: select) { details }.buttonStyle(.ink) }
                else { details }
            }
            // iOS uses only the handle gesture; a native row drag provider steals its touches.
            #if os(macOS)
            .onDrag { dragSession?.begin(task.id) ?? NSItemProvider(object: task.id as NSString) } preview: {
                    Text(task.title).font(.body).foregroundStyle(Color.ink).padding(12)
                        .background(Color.paper).overlay { Color.ink.opacity(0.055).allowsHitTesting(false) }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            #endif
        }.padding(.vertical, 6).contentShape(Rectangle())
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(task.title).font(.body).strikethrough(task.completed).lineLimit(2)
                    .multilineTextAlignment(.leading)
                if task.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Color.ink) }
                if task.priority > 0 { Text(String(repeating: "!", count: task.priority)).font(.caption.weight(.semibold)).accessibilityLabel(Labels.priority(task.priority)) }
            }.frame(minHeight: titleHeight, alignment: .leading)
                .alignmentGuide(.taskTitleCenter) { $0[VerticalAlignment.center] }
            if hasMetadata {
                HStack(spacing: 8) {
                    if let due = task.due { Text(Labels.date(due, allDay: task.allDay)).foregroundStyle(.secondary) }
                    if task.recurrence != "none" { Image(systemName: "repeat") }
                    ForEach(task.tags.prefix(2), id: \.self) { Text("#" + $0).foregroundStyle(Color.ink) }
                    if !task.isNote, task.progress > 0 { Text("\(task.progress)%").monospacedDigit() }
                }.font(.caption).foregroundStyle(.secondary)
            }
            if !task.isNote, task.progress > 0, !task.completed {
                ProgressView(value: Double(task.progress), total: 100).tint(Color.ink).frame(maxWidth: 140)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}

#if os(macOS)
/// Native split tracking, keyboard accessibility and per-Mac divider persistence.
private struct TaskWorkspaceSplit: NSViewControllerRepresentable {
    let list: AnyView
    let detail: AnyView
    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = TaskWorkspaceController()
        controller.splitView.isVertical = true
        controller.splitView.dividerStyle = .thin
        let listController = NSHostingController(rootView: list)
        let detailController = NSHostingController(rootView: detail)
        let listItem = NSSplitViewItem(viewController: listController)
        listItem.minimumThickness = 260
        listItem.preferredThicknessFraction = 0.34
        listItem.maximumThickness = 900
        listItem.holdingPriority = .init(251)
        let detailItem = NSSplitViewItem(viewController: detailController)
        detailItem.minimumThickness = 420
        detailItem.preferredThicknessFraction = 0.66
        controller.addSplitViewItem(listItem)
        controller.addSplitViewItem(detailItem)
        return controller
    }
    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        (controller.splitViewItems[0].viewController as? NSHostingController<AnyView>)?.rootView = list
        (controller.splitViewItems[1].viewController as? NSHostingController<AnyView>)?.rootView = detail
    }
}
@MainActor private final class TaskWorkspaceController: NSSplitViewController {
    private var positioned = false
    private let widthKey = "LifeOS.taskListWidth.v1"
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(rememberWidth), name: NSSplitView.didResizeSubviewsNotification, object: splitView)
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        let available = splitView.bounds.width - splitView.dividerThickness
        guard !positioned, available >= 680 else { return }
        positioned = true
        let saved = (UserDefaults.standard.object(forKey: widthKey) as? NSNumber)?.doubleValue
        let desired = saved ?? available * 0.34
        splitView.setPosition(max(260, min(900, available - 420, desired)), ofDividerAt: 0)
    }
    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        super.splitView(splitView, effectiveRect: proposedEffectiveRect, forDrawnRect: drawnRect, ofDividerAt: dividerIndex).insetBy(dx: -4, dy: 0)
    }
    @objc private func rememberWidth() {
        guard positioned, let first = splitView.arrangedSubviews.first, first.frame.width >= 260 else { return }
        UserDefaults.standard.set(first.frame.width, forKey: widthKey)
    }
}

#endif
