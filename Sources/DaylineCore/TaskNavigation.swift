import Foundation

public enum TaskDestination: Hashable {
    case page(String)
    case task(String)
}

public enum TaskNavigation {
    public static func pages(for route: String, records: [String: Record]) -> [TaskDestination] {
        guard route != "structure" else { return [] }
        if route.hasPrefix("list:"), let directionID = records[route]?.directionID,
           let direction = records[directionID], direction.kind == "direction", !direction.trashed {
            return [.page(directionID), .page(route)]
        }
        return [.page(route)]
    }

    public static func opening(_ id: String, from path: [TaskDestination], projection: Projection) -> [TaskDestination] {
        guard let task = projection.records[id], task.kind == "task", !projection.isPurged(task) else { return path }
        if let index = path.firstIndex(of: .task(id)) { return Array(path.prefix(through: index)) }
        if case .page(let page) = path.last,
           !page.hasPrefix("direction:"), !page.hasPrefix("list:") || page == task.listID {
            return path + [.task(id)]
        }
        if case .task(let currentID) = path.last, projection.records[currentID]?.listID == task.listID {
            return path + [.task(id)]
        }
        let route = projection.isHidden(task) ? "trash" : task.listID
        return pages(for: route, records: projection.records) + [.task(id)]
    }
}
