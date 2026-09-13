import SwiftUI

struct CalendarPlanner: View {
    @Environment(DaylineStore.self) private var store
    @Binding var selectedTask: String?
    let tasks: [Record]
    @State private var focusDate = Date()
    @State private var display = "month"
    @State private var listSelection = "all"
    @ScaledMetric(relativeTo: .caption2) private var hourFont = 10.0
    @ScaledMetric(relativeTo: .caption) private var pillFont = 11.0
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    private var compact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }
    private var plannedTasks: [Record] { listSelection == "all" ? tasks : tasks.filter { $0.listID == listSelection } }
    private var calendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private var firstMonth: Date { calendar.date(from: calendar.dateComponents([.year, .month], from: focusDate))! }
    private var firstWeek: Date { calendar.dateInterval(of: .weekOfYear, for: focusDate)!.start }
    private func day(_ offset: Int, from date: Date) -> Date { calendar.date(byAdding: .day, value: offset, to: date)! }
    private var visibleDays: [Date] { display == "day" ? [calendar.startOfDay(for: focusDate)] : (0..<7).map { day($0, from: firstWeek) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(focusDate.formatted(.dateTime.year().month(.wide))).font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.ink).accessibilityLabel("上一页")
                Button("今天") { focusDate = Date() }.buttonStyle(.ink)
                Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.ink).accessibilityLabel("下一页")
            }.padding(14)
            HStack {
                Picker("日历视图", selection: $display) {
                    Text("月").tag("month"); Text("周").tag("week"); Text("日").tag("day"); Text("议程").tag("agenda"); Text("年").tag("year"); Text("两周").tag("multiweek"); Text("时间轴").tag("timeline")
                }.frame(maxWidth: 160)
                Picker("专项", selection: $listSelection) {
                    Text("全部专项").tag("all"); Text("待整理").tag("inbox")
                    ForEach(store.projection.lists.filter { !$0.archived }) { Text($0.title).tag($0.id) }
                }.frame(maxWidth: 260)
                Spacer()
            }.padding(.horizontal, 14).padding(.bottom, 10)
            if plannedTasks.contains(where: { $0.due == nil }) {
                ScrollView(.horizontal) { HStack { Text("待安排").font(.caption).foregroundStyle(.secondary); ForEach(plannedTasks.filter { $0.due == nil }) { pill($0).frame(maxWidth: 180).draggable($0.id) } }.padding(.horizontal, 14).padding(.bottom, 10) }
            }
            Divider()
            switch display {
            case "day", "week": timeGrid
            case "agenda": agenda
            case "year": yearGrid
            case "timeline": ProjectTimeline(tasks: plannedTasks, start: firstWeek, selectedTask: $selectedTask)
            default: monthGrid
            }
        }
    }
    private var monthGrid: some View {
        let weeks = display == "multiweek" ? 2 : 6
        let start = display == "multiweek" ? firstWeek : day(-((calendar.component(.weekday, from: firstMonth) + 5) % 7), from: firstMonth)
        return GeometryReader { geo in
            ScrollView {
                HStack { ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) } }.padding(.vertical, 10)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                    ForEach(0..<(weeks * 7), id: \.self) { index in
                        let date = day(index, from: start)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Spacer(); Text("\(calendar.component(.day, from: date))").font(.caption).frame(width: 25, height: 25).foregroundStyle(calendar.isDateInToday(date) ? .white : .primary).background(calendar.isDateInToday(date) ? Color.ink : .clear, in: Circle()) }
                            let items = on(date)
                            if compact {
                                if !items.isEmpty { Text("\(items.count) 项").font(.caption).foregroundStyle(.secondary) }
                            } else {
                                ForEach(items.prefix(3)) { pill($0).draggable($0.id) }
                                if items.count > 3 { Text("另 \(items.count - 3) 项").font(.caption2).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                        }.padding(5).frame(height: max(compact ? 82 : 135, (geo.size.height - 42) / CGFloat(weeks)))
                            .background(calendar.isDateInToday(date) ? Color.ink.opacity(0.04) : Color.clear)
                            .opacity(display == "multiweek" || calendar.isDate(date, equalTo: focusDate, toGranularity: .month) ? 1 : 0.4)
                            .overlay(Rectangle().stroke(.secondary.opacity(0.12), lineWidth: 0.5))
                            .contentShape(Rectangle()).onTapGesture { focusDate = date; display = "day" }
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                            .accessibilityAction(named: Text("查看当天")) { focusDate = date; display = "day" }
                            .dropDestination(for: String.self) { ids, _ in drop(ids, date: date, minute: nil) }
                    }
                }
            }
        }
    }
    private var timeGrid: some View {
        GeometryReader { geo in
            let width = max(display == "day" ? 260 : 105, (geo.size.width - 44) / CGFloat(visibleDays.count))
            ScrollViewReader { reader in
                ScrollView([.vertical, .horizontal]) {
                    VStack(spacing: 0) {
                        HStack(alignment: .top, spacing: 0) {
                            Text("全天").font(.caption2).frame(width: 44).padding(.top, 12)
                            ForEach(visibleDays, id: \.self) { date in
                                VStack(spacing: 5) { Text(date.formatted(.dateTime.weekday(.abbreviated).day())).font(.caption.bold()); ForEach(on(date).filter(\.allDay)) { pill($0).draggable($0.id) } }.padding(5).frame(width: width)
                                    .dropDestination(for: String.self) { ids, _ in drop(ids, date: date, minute: nil) }
                            }
                        }.padding(.vertical, 8)
                        HStack(alignment: .top, spacing: 0) {
                            VStack(spacing: 0) { ForEach(0..<24) { hour in Text(String(format: "%02d:00", hour)).font(.system(size: hourFont, design: .monospaced)).foregroundStyle(.secondary).frame(width: 44, height: 60, alignment: .top).id(hour) } }
                            ForEach(visibleDays, id: \.self) { date in
                                ZStack(alignment: .topLeading) {
                                    VStack(spacing: 0) { ForEach(0..<24) { hour in
                                        Rectangle().fill(Color.clear).frame(height: 60).contentShape(Rectangle()).overlay(alignment: .top) { Divider() }
                                            .overlay(alignment: .trailing) { Rectangle().fill(.secondary.opacity(0.15)).frame(width: 0.5) }
                                            .dropDestination(for: String.self) { ids, point in drop(ids, date: date, minute: hour * 60 + max(0, min(45, CalendarLayout.snap(minutes: point.y)))) }
                                            .onTapGesture(count: 2) { let due = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)!; if let id = store.perform("task.add", fields: ["title": .string("新任务"), "due": .date(due), "end": .date(due.addingTimeInterval(3600)), "allDay": .flag(false)])?.records.first?.id { selectedTask = id } }
                                    } }
                                    ForEach(CalendarLayout.blocks(plannedTasks, day: date, calendar: calendar)) { block in
                                        CalendarTimeBlock(block: block, columnWidth: width) { selectedTask = block.id }
                                            .frame(width: max(32, width / CGFloat(block.lanes) - 5))
                                            .offset(x: CGFloat(block.lane) * width / CGFloat(block.lanes) + 2, y: block.start)
                                    }
                                }.frame(width: width, height: 1440)
                            }
                        }
                    }
                }.onAppear { reader.scrollTo(8, anchor: .top) }
            }
        }
    }
    private var agenda: some View {
        List {
            ForEach(0..<30, id: \.self) { offset in
                let date = day(offset, from: calendar.startOfDay(for: focusDate)); let items = on(date)
                if !items.isEmpty { Section(date.formatted(date: .complete, time: .omitted)) { ForEach(items) { task in TaskRow(task: task, select: { selectedTask = task.id }).listRowBackground(Color.clear) } } }
            }
        }.scrollContentBackground(.hidden).overlay { if !(0..<30).contains(where: { !on(day($0, from: focusDate)).isEmpty }) { ContentUnavailableView("未来 30 天暂无安排", systemImage: "calendar") } }
    }
    private var yearGrid: some View {
        let year = calendar.component(.year, from: focusDate)
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 310 : 280))], spacing: 18) {
                ForEach(1...12, id: \.self) { month in
                    let date = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
                    let offset = (calendar.component(.weekday, from: date) + 5) % 7
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(month)月").font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                            ForEach(0..<42, id: \.self) { index in
                                let d = day(index - offset, from: date)
                                VStack(spacing: 2) { Text("\(calendar.component(.day, from: d))").font(.caption); Circle().fill(on(d).isEmpty ? Color.clear : Color.ink).frame(width: 4, height: 4) }
                                    .opacity(calendar.component(.month, from: d) == month ? 1 : 0.35).frame(height: compact ? 44 : 32)
                                    .contentShape(Rectangle()).onTapGesture { focusDate = d; display = "day" }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(d.formatted(date: .complete, time: .omitted))
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction { focusDate = d; display = "day" }
                            }
                        }
                    }.padding(14).background(Color.daylineSecondary, in: RoundedRectangle(cornerRadius: 12))
                        .contextMenu { Button("查看这个月") { focusDate = date; display = "month" } }
                }
            }.padding(18)
        }
    }
    private func on(_ date: Date) -> [Record] {
        let start = calendar.startOfDay(for: date), end = day(1, from: start)
        return plannedTasks.filter { task in guard let due = task.due else { return false }; return due < end && (task.end.map { $0 > start } ?? (due >= start)) }
    }
    private func pill(_ task: Record) -> some View {
        Button { selectedTask = task.id } label: { Text(task.title).font(.system(size: pillFont)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(5).foregroundStyle(Color.ink).background(Color.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 4)) }.buttonStyle(.ink)
    }
    private func shift(_ delta: Int) {
        let component: Calendar.Component = display == "year" ? .year : display == "month" ? .month : .day
        let count = ["week":7, "multiweek":14, "agenda":30, "timeline":28][display] ?? 1
        focusDate = calendar.date(byAdding: component, value: delta * count, to: focusDate)!
    }
    private func drop(_ ids: [String], date: Date, minute: Int?) -> Bool {
        guard let id = ids.first, let task = store.projection.records[id], !task.completed else { return false }
        let oldTime = task.due.map { calendar.dateComponents([.hour, .minute], from: $0) }
        let minutes = minute ?? (oldTime?.hour ?? 0) * 60 + (oldTime?.minute ?? 0)
        guard let due = calendar.date(bySettingHour: min(23, minutes / 60), minute: minutes % 60, second: 0, of: date) else { return false }
        var fields: [String: Value] = ["due": .date(due)]
        if let old = task.due, let end = task.end { fields["end"] = .date(due.addingTimeInterval(end.timeIntervalSince(old))) }
        if minute != nil { fields["allDay"] = .flag(false); if task.end == nil { fields["end"] = .date(due.addingTimeInterval(3600)) } }
        return store.perform("task.update", id: id, fields: fields) != nil
    }
}

struct CalendarTimeBlock: View {
    @Environment(DaylineStore.self) private var store
    let block: TimeBlock
    let columnWidth: CGFloat
    let selected: () -> Void
    @State private var movement = CGSize.zero
    @State private var resize = 0.0
    @ScaledMetric(relativeTo: .caption) private var titleFont = 11.0
    @ScaledMetric(relativeTo: .caption2) private var timeFont = 10.0
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(block.task.title).font(.system(size: titleFont, weight: .medium)).lineLimit(2)
            if block.end - block.start > 40 { Text(block.task.due!.formatted(date: .omitted, time: .shortened)).font(.system(size: timeFont)).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            Capsule().fill(Color.ink.opacity(0.5)).frame(width: 22, height: 3).frame(maxWidth: .infinity).padding(.vertical, 4).contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 2, coordinateSpace: .global).onChanged { resize = $0.translation.height }.onEnded { value in
                    let due = block.task.due!; let end = block.task.end ?? due.addingTimeInterval(3600)
                    let updated = max(due.addingTimeInterval(900), end.addingTimeInterval(Double(CalendarLayout.snap(minutes: value.translation.height)) * 60))
                    store.update(block.id, ["end": .date(updated)]); resize = 0
                }).accessibilityLabel("拖动调整时长")
        }.padding(.horizontal, 5).padding(.top, 4).frame(height: max(20, block.end - block.start + resize), alignment: .topLeading)
            .background(Color.ink.opacity(0.14), in: RoundedRectangle(cornerRadius: 5)).overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(Color.ink).frame(width: 3) }
            .offset(movement).onTapGesture(perform: selected)
            .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .global).onChanged { movement = $0.translation }.onEnded { value in
                let days = Int((value.translation.width / columnWidth).rounded())
                let minutes = CalendarLayout.snap(minutes: value.translation.height)
                if let date = Calendar.current.date(byAdding: .day, value: days, to: block.task.due!) { store.reschedule(block.task, to: date.addingTimeInterval(Double(minutes) * 60)) }
                movement = .zero
            })
            .accessibilityElement(children: .combine).accessibilityLabel("\(block.task.title)，\(Int(block.end - block.start)) 分钟")
            .accessibilityAddTraits(.isButton).accessibilityAction(named: Text("查看与编辑时间"), selected)
    }
}

struct ProjectTimeline: View {
    @Environment(DaylineStore.self) private var store
    let tasks: [Record]
    let start: Date
    @Binding var selectedTask: String?
    private let unit = 46.0
    private var dated: [Record] {
        let limit = Calendar.current.date(byAdding: .day, value: 42, to: start)!
        return tasks.filter { guard let due = $0.due else { return false }; return due < limit && ($0.end ?? due.addingTimeInterval($0.allDay ? 86400 : 3600)) > start }
    }
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) { Text("任务").frame(width: 180, alignment: .leading); ForEach(0..<42) { index in Text(Calendar.current.date(byAdding: .day, value: index, to: start)!.formatted(.dateTime.month().day())).font(.caption).frame(width: unit) } }.frame(height: 36)
                ForEach(dated) { task in
                    HStack(spacing: 0) {
                        Button { selectedTask = task.id } label: { Text(task.title).lineLimit(2).frame(width: 180, alignment: .leading) }.buttonStyle(.ink)
                        TimelineTrack(task: task, start: start, unit: unit) { selectedTask = task.id }
                    }.frame(height: 54).overlay(alignment: .bottom) { Divider() }
                }
            }.padding(16)
        }.overlay { if dated.isEmpty { ContentUnavailableView("暂无已排期任务", systemImage: "chart.bar.xaxis") } }
    }
}
struct TimelineTrack: View {
    @Environment(DaylineStore.self) private var store
    let task: Record
    let start: Date
    let unit: Double
    let select: () -> Void
    @State private var offset = 0.0
    @State private var resize = 0.0
    var body: some View {
        let due = task.due!, end = task.end ?? due.addingTimeInterval(task.allDay ? 86400 : 3600)
        let x = due.timeIntervalSince(start) / 86400 * unit
        let width = max(22, end.timeIntervalSince(due) / 86400 * unit)
        return ZStack(alignment: .leading) {
            HStack(spacing: 0) { ForEach(0..<42) { _ in Rectangle().fill(Color.clear).frame(width: unit).overlay(alignment: .leading) { Divider() } } }
            HStack(spacing: 0) {
                Text(task.title).font(.caption).lineLimit(1).padding(.leading, 7); Spacer(minLength: 0)
                Rectangle().fill(Color.ink.opacity(0.45)).frame(width: 9).contentShape(Rectangle()).highPriorityGesture(DragGesture(coordinateSpace: .global).onChanged { resize = $0.translation.width }.onEnded { value in
                    let days = Int((value.translation.width / unit).rounded()); let updated = Calendar.current.date(byAdding: .day, value: days, to: end)!
                    store.update(task.id, ["end": .date(max(due.addingTimeInterval(900), updated))]); resize = 0
                })
            }.frame(width: max(22, width + resize), height: 30).background(Color.ink.opacity(0.16), in: RoundedRectangle(cornerRadius: 5)).offset(x: x + offset)
                .onTapGesture(perform: select).gesture(DragGesture(coordinateSpace: .global).onChanged { offset = $0.translation.width }.onEnded { value in
                    let days = Int((value.translation.width / unit).rounded()); store.reschedule(task, to: Calendar.current.date(byAdding: .day, value: days, to: due)!); offset = 0
                })
                .accessibilityElement(children: .ignore).accessibilityLabel(task.title)
                .accessibilityAddTraits(.isButton).accessibilityAction(named: Text("查看与编辑时间"), select)
        }.frame(width: 42 * unit, height: 50).clipped()
    }
}

struct BoardView: View {
    @Environment(DaylineStore.self) private var store
    let tasks: [Record]
    @Binding var selectedTask: String?
    var listID: String? = nil
    private var custom: Bool { !(store.projection.records[listID ?? ""]?.sections ?? []).isEmpty }
    private var columns: [String] {
        if custom { let defined = store.projection.records[listID!]!.sections; return [""] + defined + Array(Set(tasks.map(\.section)).subtracting(Set([""] + defined))).sorted() }
        return ["todo", "doing", "done"]
    }
    private func items(_ column: String) -> [Record] { tasks.filter { custom ? $0.section == column : $0.status == column } }
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(columns, id: \.self) { column in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(custom ? (column.isEmpty ? "未分组" : column) : ["todo":"待办", "doing":"进行中", "done":"已完成"][column]!).font(.headline)
                            Spacer()
                            if listID == nil { Text("\(items(column).count)").foregroundStyle(.secondary) }
                        }
                        ForEach(items(column)) { task in TaskRow(task: task, select: { selectedTask = task.id }).padding(10).background(Color.daylineBackground, in: RoundedRectangle(cornerRadius: 10)) }
                        Spacer(minLength: 150)
                    }.padding(14).frame(width: 260).background(Color.daylineSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                        .dropDestination(for: String.self) { ids, _ in
                            guard let id = ids.first, let task = store.projection.records[id] else { return false }
                            if custom { store.update(id, ["section": .string(column)]) }
                            else if column == "done" { guard !task.isNote else { return false }; store.perform("task.complete", id: id) }
                            else { if task.completed, store.perform("task.reopen", id: id) == nil { return false }; store.update(id, ["status": .string(column)]) }
                            return true
                        }
                }
            }.padding(18)
        }
    }
}
