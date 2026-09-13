// Compile alongside Sources/DaylineCore/*.swift; name this file main.swift in a temporary directory.
import Foundation
let n = Int(CommandLine.arguments.dropFirst().first ?? "200")!
let date = Date(timeIntervalSince1970: 1789272000)
let events = (0..<(n * 10)).map { i in ChangeEvent(id: "e\(i)", actor: "benchmark", clock: i + 1, createdAt: date, changes: [Change(entity: "task:\(i % n)", fields: ["title": .string("Task \(i % n)"), "due": .date(date.addingTimeInterval(Double(i % n) * 900)), "priority": .number(i % 4)])]) }
let data = try events.map { try JSONEncoder().encode($0) }
func sample(_ name: String, _ body: () throws -> Int) rethrows {
    var durations: [Double] = []; var value = 0
    for _ in 0..<7 { let start = DispatchTime.now().uptimeNanoseconds; value = try body(); durations.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000) }
    durations.sort(); print("\(name): median=\(String(format: "%.3f", durations[3]))ms max=\(String(format: "%.3f", durations.last!))ms result=\(value)")
}
try sample("history decode+replay \(events.count) events") { Projection(events: try data.map { try JSONDecoder().decode(ChangeEvent.self, from: $0) }).eventIDs.count }
let projection = Projection(events: events)
sample("task query+children \(n) tasks") { projection.query(TaskFilter()).count + projection.children(of: "task:0").count }
sample("calendar year date reads \(n) tasks x 366") { var count=0; for d in 0..<366 { let start=date.addingTimeInterval(Double(d)*86400); count += projection.records.values.filter { ($0.due ?? .distantPast) >= start && ($0.due ?? .distantFuture) < start.addingTimeInterval(86400) }.count }; return count }
