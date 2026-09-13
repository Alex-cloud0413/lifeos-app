import SwiftUI
import UniformTypeIdentifiers

@Observable final class TaskDragSession {
    var sourceID: String?
    var liftedID: String?
    var hoverID: String?
    var hoverSide: TaskReordering.Placement?
    @ObservationIgnored var regions: [String: Region] = [:]
    struct Region { let frame: CGRect; let rows: [Record]; let viewID: String? }
    func update(_ id: String, location: CGPoint, projection: Projection) {
        sourceID = id; liftedID = id
        guard let source = projection.records[id], !projection.isHidden(source),
              let entry = regions.filter({ $0.value.frame.contains(location) }).min(by: { $0.value.frame.height < $1.value.frame.height }),
              let row = projection.records[entry.key],
              let target = TaskReordering.target(for: source, over: row, records: projection.records),
              entry.value.rows.contains(where: { $0.id == target.id }) else { hoverID = nil; hoverSide = nil; return }
        hoverID = row.id
        hoverSide = target.id != row.id || location.y >= entry.value.frame.midY ? .after : .before
    }
    @MainActor func finish(store: DaylineStore) {
        defer { cancel() }
        guard let sourceID, let source = store.projection.records[sourceID], let hoverID,
              let row = store.projection.records[hoverID], let region = regions[hoverID], let side = hoverSide,
              let target = TaskReordering.target(for: source, over: row, records: store.projection.records) else { return }
        var fields: [String: Value] = ["targetID": .string(target.id), "placement": .string(side.rawValue),
            "orderedIDs": .strings(region.rows.filter { TaskReordering.peers(source, $0) }.map(\.id))]
        if let viewID = region.viewID { fields["viewID"] = .string(viewID) }
        store.perform("task.move", id: sourceID, fields: fields)
    }
    func cancel() { sourceID = nil; liftedID = nil; hoverID = nil; hoverSide = nil }
    func begin(_ id: String) -> NSItemProvider {
        sourceID = id
        return NSItemProvider(object: id as NSString)
    }
}

struct TaskDragHandle: View {
    @Environment(DaylineStore.self) private var store
    @GestureState private var dragging = false
    let task: Record
    let session: TaskDragSession
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption).foregroundStyle(Color.secondary.opacity(0.65))
            .iconTarget().contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .updating($dragging) { _, state, _ in state = true }
                .onChanged { value in session.update(task.id, location: value.location, projection: store.projection) }
                .onEnded { value in
                    session.update(task.id, location: value.location, projection: store.projection)
                    session.finish(store: store)
                })
            .onChange(of: dragging) { _, value in if !value { session.cancel() } }
            .accessibilityLabel("拖动排序：\(task.title)")
            .help("拖动到同级任务之间")
            .alignmentGuide(.taskTitleCenter) { $0[VerticalAlignment.center] }
    }
}

struct TaskReorderTarget: ViewModifier {
    @Environment(DaylineStore.self) private var store
    let task: Record
    let session: TaskDragSession
    let rows: [Record]
    let viewID: String?
    @State private var height: CGFloat = 44
    @State private var placement: TaskReordering.Placement?

    private var displayPlacement: TaskReordering.Placement? { session.hoverID == task.id ? session.hoverSide : placement }
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 8).fill(Color.ink.opacity(session.liftedID == task.id ? 0.055 : 0))
                    .animation(.easeOut(duration: 0.12), value: session.liftedID == task.id)
                    .allowsHitTesting(false)
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.onAppear { register(geometry) }
                        .onChange(of: geometry.frame(in: .global)) { _, _ in register(geometry) }
                        .onChange(of: rows.map(\.id)) { _, _ in register(geometry) }
                        .onDisappear { session.regions.removeValue(forKey: task.id) }
                }
            }
            .overlay(alignment: displayPlacement == .before ? .top : .bottom) {
                if displayPlacement != nil {
                    Rectangle().fill(Color.ink.opacity(0.65)).frame(height: 1.5)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            #if os(macOS)
            .onDrop(of: [UTType.text], delegate: TaskMoveDropDelegate(
                task: task, session: session, rows: rows, viewID: viewID, store: store,
                height: height, placement: $placement))
            #endif
    }
    private func register(_ geometry: GeometryProxy) {
        height = geometry.size.height
        session.regions[task.id] = .init(frame: geometry.frame(in: .global), rows: rows, viewID: viewID)
    }
}

private struct TaskMoveDropDelegate: DropDelegate {
    let task: Record
    let session: TaskDragSession
    let rows: [Record]
    let viewID: String?
    let store: DaylineStore
    let height: CGFloat
    @Binding var placement: TaskReordering.Placement?

    private func destination(_ info: DropInfo) -> (Record, TaskReordering.Placement)? {
        guard let id = session.sourceID, let source = store.projection.records[id],
              !store.projection.isHidden(source),
              let target = TaskReordering.target(for: source, over: task, records: store.projection.records),
              rows.contains(where: { $0.id == target.id }) else { return nil }
        return (target, target.id != task.id || info.location.y >= height / 2 ? .after : .before)
    }
    func validateDrop(info: DropInfo) -> Bool { destination(info) != nil && info.hasItemsConforming(to: [UTType.text]) }
    func dropEntered(info: DropInfo) { placement = destination(info)?.1 }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        placement = destination(info)?.1
        return DropProposal(operation: placement == nil ? .forbidden : .move)
    }
    func dropExited(info: DropInfo) { placement = nil }
    func performDrop(info: DropInfo) -> Bool {
        guard let (target, side) = destination(info), let sourceID = session.sourceID,
              let source = store.projection.records[sourceID],
              let provider = info.itemProviders(for: [UTType.text]).first else { placement = nil; return false }
        let orderedIDs = rows.filter { TaskReordering.peers(source, $0) }.map(\.id)
        placement = nil
        provider.loadObject(ofClass: String.self) { value, _ in
            guard value == sourceID else { return }
            Task { @MainActor in
                var fields: [String: Value] = ["targetID": .string(target.id), "placement": .string(side.rawValue), "orderedIDs": .strings(orderedIDs)]
                if let viewID { fields["viewID"] = .string(viewID) }
                store.perform("task.move", id: sourceID, fields: fields)
                session.sourceID = nil
            }
        }
        return true
    }
}

extension VerticalAlignment {
    private struct TaskTitleCenter: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions[VerticalAlignment.center] }
    }
    static let taskTitleCenter = VerticalAlignment(TaskTitleCenter.self)
}

// List owns its platform drop interaction; its insertion callback preserves native
// scrolling and swipe actions while the row delegate handles detail-page children.
@MainActor enum TaskListInsertion {
    static func move(offsets: IndexSet, index: Int, rows: [Record], viewID: String, store: DaylineStore) {
        guard offsets.count == 1, let offset = offsets.first, rows.indices.contains(offset),
              let source = store.projection.records[rows[offset].id],
              let (target, side) = TaskReordering.insertion(for: source, at: index, rows: rows, records: store.projection.records) else { return }
        store.perform("task.move", id: source.id, fields: ["targetID": .string(target.id), "placement": .string(side.rawValue),
            "orderedIDs": .strings(rows.filter { TaskReordering.peers(source, $0) }.map(\.id)), "viewID": .string(viewID)])
    }

    static func perform(index: Int, providers: [NSItemProvider], rows: [Record],
                        session: TaskDragSession, viewID: String, store: DaylineStore) {
        guard let sourceID = session.sourceID, let source = store.projection.records[sourceID],
              !store.projection.isHidden(source), let provider = providers.first,
              !rows.isEmpty else { return }
        guard let (target, side) = TaskReordering.insertion(for: source, at: index, rows: rows, records: store.projection.records) else { return }
        let orderedIDs = rows.filter { TaskReordering.peers(source, $0) }.map(\.id)
        provider.loadObject(ofClass: String.self) { value, _ in
            guard value == sourceID else { return }
            Task { @MainActor in
                store.perform("task.move", id: sourceID, fields: ["targetID": .string(target.id),
                    "placement": .string(side.rawValue), "orderedIDs": .strings(orderedIDs), "viewID": .string(viewID)])
                session.sourceID = nil
            }
        }
    }
}
