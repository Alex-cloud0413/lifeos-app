import Foundation
import DaylineCore

let help = """
Life · OS — 本地任务与日历 CLI（JSON 输出）

lifeos status
lifeos tasks [--direction ID] [--project ID] [--view all|today|next7days|month|quarter|completed|trash] [--tag TAG] [--search TEXT]
lifeos get ID
lifeos add "写周报" [--due "2026-09-14 09:00"] [--project ID] [--repeat weekly]
lifeos update ID [--title TEXT] [--notes TEXT] [--due DATE|none] [--end DATE|none]
                  [--priority 0..3] [--tags a,b] [--parent ID|none]
                  [--repeat none|daily|weekdays|weekly|biweekly|monthly|yearly] [--status todo|doing]
                  [--revision REVISION]
lifeos complete ID | reopen ID | trash ID | restore ID
lifeos empty-trash --confirm true
lifeos directions | new-direction NAME | update-direction ID --title NAME
lifeos projects [--direction ID] | new-project NAME --direction ID | update-project ID --direction ID
lifeos duplicate ID | save-template ID | use-template TEMPLATE_ID
lifeos templates | history [TASK_ID] [--offset N] [--limit 50]
lifeos undo EVENT_ID | link ID
lifeos convert ID --type task|note
更新可加：--progress 0..100 --pinned true|false --section NAME
使用模板可加：--anchor DATE --title TEXT
lifeos rpc < request.json

通用参数：--request-id ID（变更重试沿用同一 ID）、--socket PATH
--priority 3 为高优先级。标题原样保存，不解析任何自然语言、#标签或 !优先级。
日期使用本机时区，或带时区的 ISO 8601。JSON 响应 ok=false 时退出码为 1。
所有写入都经过 App；不会直接编辑数据库。Mac App 需要保持运行。
"""

func run() throws -> AgentResponse? {
    var args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first, !["help", "--help", "-h"].contains(command) else { print(help); return nil }
    args.removeFirst()
    var opts: [String: String] = [:]; var positional: [String] = []
    while !args.isEmpty {
        let arg = args.removeFirst()
        if arg.hasPrefix("--") {
            guard !args.isEmpty, !args[0].hasPrefix("--") else { throw CommandError("missing_option", "\(arg) 缺少参数。") }
            opts[arg] = args.removeFirst()
        } else { positional.append(arg) }
    }
    let allowed: Set<String> = ["--direction", "--project", "--view", "--list", "--tag", "--search", "--title", "--notes", "--due", "--end", "--priority", "--tags", "--parent", "--repeat", "--status", "--revision", "--request-id", "--socket", "--color", "--progress", "--pinned", "--section", "--type", "--anchor", "--limit", "--offset", "--confirm"]
    for option in opts.keys where !allowed.contains(option) { throw CommandError("unknown_option", "未知选项：\(option)") }
    if command == "rpc" {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard input.count <= 1_048_576 else { throw CommandError("too_large", "输入超过 1 MB。") }
        return try LocalTransport.call(JSONDecoder().decode(AgentRequest.self, from: input), path: opts["--socket"])
    }
    if command == "empty-trash" {
        guard opts["--confirm"] == "true", positional.isEmpty else { throw CommandError("confirmation_required", "清空后无法在 App 中恢复。确认后使用 empty-trash --confirm true。") }
        let preview = try LocalTransport.call(AgentRequest(command: "trash.list"), path: opts["--socket"])
        guard preview.ok else { return preview }
        return try LocalTransport.call(AgentRequest(command: "trash.empty", requestID: opts["--request-id"] ?? UUID().uuidString,
            fields: ["confirm": .flag(true), "ids": .strings(preview.records.map(\.id)), "revisions": .strings(preview.records.map(\.revision))]), path: opts["--socket"])
    }
    let mapping = ["directions":"direction.list", "new-direction":"direction.add", "update-direction":"direction.update", "projects":"project.list", "new-project":"project.add", "update-project":"project.update", "status": "status", "tasks": "task.list", "get": "task.get", "add": "task.add", "update": "task.update", "complete": "task.complete", "reopen": "task.reopen", "trash": "task.trash", "restore": "task.restore", "lists": "list.list", "new-list": "list.add", "duplicate": "task.duplicate", "templates": "template.list", "save-template": "template.save", "use-template": "template.use", "history": "history.list", "undo": "event.undo", "link": "task.get", "convert": "task.convert"]
    guard let operation = mapping[command] else { throw CommandError("unknown_command", "未知命令：\(command)。运行 lifeos help 查看用法。") }
    var request = AgentRequest(command: operation, requestID: opts["--request-id"] ?? UUID().uuidString, expectedRevision: opts["--revision"])
    if ["update-direction", "update-project", "get", "update", "complete", "reopen", "trash", "restore", "duplicate", "save-template", "use-template", "undo", "link", "convert"].contains(command) {
        guard positional.count == 1 else { throw CommandError("missing_id", "需要一个完整任务 ID。") }; request.id = positional[0]
    }
    if command == "history", let id = positional.first { request.id = id }
    for option in ["--offset", "--limit"] { if let raw = opts[option] { guard let n = Int(raw) else { throw CommandError("invalid_page", "分页参数应为整数。") }; request.fields[String(option.dropFirst(2))] = .number(n) } }
    if command == "add" {
        guard !positional.isEmpty else { throw CommandError("missing_title", "请输入任务标题。") }
        request.fields = ["title": .string(positional.joined(separator: " "))]
    } else if ["new-list", "new-project", "new-direction"].contains(command) {
        request.fields["title"] = .string(positional.joined(separator: " "))
        if command == "new-list" { request.fields["color"] = .string(opts["--color"] ?? "blue") }
    }
    if let project = opts["--project"] { request.fields["listID"] = .string(project) }
    if let direction = opts["--direction"], command != "tasks" { request.fields["directionID"] = direction == "none" ? .null : .string(direction) }
    for (option, field) in ["--title": "title", "--notes": "notes", "--list": "listID", "--repeat": "recurrence", "--status": "status", "--section": "section", "--type": "itemType"] {
        if let value = opts[option], command != "tasks" { request.fields[field] = .string(value) }
    }
    for (option, field) in ["--due": "due", "--end": "end", "--anchor": "anchor"] {
        if let value = opts[option] {
            if value == "none" { request.fields[field] = .null }
            else {
                guard let date = ExplicitDate.parseDate(value) else { throw CommandError("invalid_date", "无法识别日期：\(value)") }
                request.fields[field] = .date(date)
                if field == "due" { request.fields["allDay"] = .flag(value.count == 10) }
            }
        }
    }
    if let value = opts["--priority"] {
        guard let priority = Int(value) else { throw CommandError("invalid_priority", "优先级必须是 0–3 的整数。") }; request.fields["priority"] = .number(priority)
    }
    if let value = opts["--progress"] {
        guard let n = Int(value), (0...100).contains(n) else { throw CommandError("invalid_progress", "进度必须为 0–100。") }
        request.fields["progress"] = .number(n)
    }
    if let value = opts["--pinned"] {
        guard ["true", "false"].contains(value) else { throw CommandError("invalid_flag", "置顶请使用 true 或 false。") }
        request.fields["pinned"] = .flag(value == "true")
    }
    if command == "link", let id = request.id { let result = try LocalTransport.call(request, path: opts["--socket"]); return result.ok ? AgentResponse(message: TaskLink.url(id).absoluteString) : result }
    if let tags = opts["--tags"] { request.fields["tags"] = .strings(tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }) }
    if let parent = opts["--parent"] { request.fields["parentID"] = parent == "none" ? .null : .string(parent) }
    if command == "tasks" { request.filter = TaskFilter(view: opts["--view"] ?? "all", listID: opts["--project"] ?? opts["--list"], tag: opts["--tag"], search: opts["--search"] ?? ""); request.filter?.directionID = opts["--direction"] }
    return try LocalTransport.call(request, path: opts["--socket"])
}

do {
    if let response = try run() {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(response), as: UTF8.self))
        if !response.ok { exit(1) }
    }
} catch {
    let e = error as? CommandError
    let response = AgentResponse(ok: false, message: error.localizedDescription, errorCode: e?.code ?? "error")
    if let data = try? JSONEncoder().encode(response) { print(String(decoding: data, as: UTF8.self)) }
    exit(1)
}
