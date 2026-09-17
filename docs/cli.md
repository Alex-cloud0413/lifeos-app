# Life · OS CLI 与本地 Agent（0.7.0）

`lifeos` 通过当前用户专属的 Unix socket 读写运行中的 Mac App；不会直接修改数据库，也不监听互联网端口。连接目录权限 0700、socket 0600，双方核对用户身份。在「设置 → 本地 Agent」启用后可用。自定义签名版本先设置 `LIFEOS_BUNDLE_ID`，或使用 `--socket PATH` / `LIFEOS_SOCKET`；详见 [构建说明](building.md)。

显示名称为 Life · OS；终端使用连续的命令名 `lifeos`。旧命令 `dayline` 保留兼容。统计与固定复盘摘要、所有提醒已移除。`stats`、`--reminder` 和写入 reminder 字段均被拒绝。旧历史字段只保留用于兼容，不再触发通知。

`lifeos empty-trash --confirm true` 清空整个回收站，先回读全部待清空记录及修订，再执行带精确快照的 `trash.empty`。缺少确认、回收站在此期间发生变化时拒绝执行。此操作无法通过恢复或撤回找回；同一请求 ID 重试不清空之后新增的回收站内容。清空标记经 iCloud 同步，历史事件和既有备份仍保留。所有设备需升级到 0.5.3。

## 常用操作

```sh
lifeos status
lifeos directions
lifeos new-direction 工作
lifeos projects --direction DIRECTION_ID
lifeos new-project 产品迭代 --direction DIRECTION_ID
lifeos update-project PROJECT_ID --direction DIRECTION_ID
lifeos tasks --direction DIRECTION_ID
lifeos tasks --view notes
lifeos tasks --view today
lifeos tasks --view next7days
lifeos tasks --view month
lifeos tasks --view quarter
lifeos tasks --project PROJECT_ID --search 周报
lifeos add "写周报" --project PROJECT_ID --due "2026-09-14 09:00" --priority 3 --tags 工作 --repeat weekly
lifeos add "研究笔记" --type note --notes "正文"
lifeos add "收集材料" --parent TASK_ID
lifeos get TASK_ID
lifeos update TASK_ID --due "2026-09-14 10:00" --end "2026-09-14 11:00"
lifeos update TASK_ID --progress 45 --pinned true --section 准备
lifeos complete TASK_ID
lifeos reopen TASK_ID
lifeos trash TASK_ID
lifeos restore TASK_ID
lifeos duplicate TASK_ID
lifeos save-template TASK_ID --title "周报流程"
lifeos templates
lifeos use-template TEMPLATE_ID --anchor "2026-10-01" --project PROJECT_ID
lifeos convert TASK_ID --type note
lifeos convert TASK_ID --type task
lifeos link TASK_ID
lifeos history TASK_ID --limit 20 --offset 0
lifeos undo EVENT_ID
```

标题原样保存，没有日期、时间、标签或优先级的自然语言识别。`--priority` 为 0 无、1 低、2 中、3 高。日期参数接受 `YYYY-MM-DD`、`YYYY-MM-DD HH:mm`（Mac 时区）或带时区的 ISO 8601。`--due none` 清除日期时，应同时清除结束时间及重复规则。笔记不能设置日期或重复；改变类型用 `convert`。

所有响应为 JSON。成功退出码 0，错误退出码 1，返回 `ok:false`、`errorCode` 和原因。任务 ID 需完整使用。

时间视图按任务自身的排期日期和设备当地时区筛选：`today` 包括今天及逾期未完成事项；`next7days` 从今天起共 7 个日历日；`month` 从今天到本自然月月底；`quarter` 从今天到本自然季度末（1–3、4–6、7–9、10–12 月）。结束边界不包含次日零点，不采用滚动 30/90 天。后三种视图排除今天之前的日期；没有排期的任务不出现。默认不含已完成、回收站、归档专项或笔记。App 中未命中日期的父任务仅作为淡显的层级上下文，不代表父任务也在该时间范围内。旧 `upcoming` 筛选保留原先包含逾期的行为。

## 方向与专项

方向是 kind=direction 的独立记录；专项沿用 kind=list 及原 list: ID，通过 directionID 归属方向。任务用 listID 归属专项（CLI 新名称为 --project），子任务用 parentID 关联父任务。

新建子任务时省略专项会继承父任务归属；不允许父子跨专项。移动父任务会一次移动全部后代，并可整次撤回。日期不是必填项，新增任务没有自动排期。方向查询包含所属专项内的任务；任务查询也会返回子任务，可用 parentID 还原树。

方向可更新 title、notes；专项可更新 title、directionID、sections、archived 等已有字段。direction.update 的 trashed=true 只允许空方向；含归档专项的方向也需先移动或删除专项。删除为可恢复变更，可通过修改历史撤回。

旧命令 lists/new-list/--list 继续兼容。原文件夹迁移为稳定 ID 的方向；旧专项 ID、任务和不可变历史不改写。未分配专项的任务使用 listID=inbox，在界面显示「待整理」。

## 重试与撤回

```sh
lifeos add "准备材料" --request-id stable-action-id
lifeos update TASK_ID --title "更新标题" --revision PREVIOUS_REVISION
```

同一次写入重试沿用同一 requestID，避免重复创建。revision 不匹配时返回 `revision_conflict`；应先重新读取。

`history` 默认最近 50 条，支持 1–100 条和 offset；可按任务 ID 缩小范围。当前响应的 message 是事件数组 JSON，正文过长时预览截断，完整内容保留在 App 和完整备份中。`undo` 逐字段检查后续修改，有冲突时整次拒绝；原始事件保留。App 内「修改历史」可查看及撤回。

## JSON RPC

`lifeos rpc` 从标准输入读取请求，版本默认 1、requestID 默认自动生成。

```json
{"command":"task.add","requestID":"agent-plan-01","fields":{"title":"写周报","due":"2026-09-14T09:00:00+08:00","allDay":false,"priority":3,"tags":["工作"]}}
```

```json
{"command":"task.batch","fields":{"ids":["TASK_A","TASK_B"],"action":"update","priority":3,"progress":40}}
```

```json
{"command":"task.batch","fields":{"ids":["TASK_A","TASK_B"],"action":"postpone","days":2}}
```

批量支持 update/postpone/complete/reopen/trash/restore，1–300 个不同 ID。所有项一次保存；任一失败则不写入。postpone 保留时间和时长，要求每项已有日期。绝对日期批量修改也保留原时长，除非明确传入 end。

```json
{"command":"task.reorder","fields":{"ids":["TASK_B","TASK_A"]}}
```

同级任务的相对移动使用 `task.move`，`orderedIDs` 是当前显示的同级任务顺序，最多 300 项。`placement` 为 `before` 或 `after`。跨专项、跨父任务、跨置顶分区的移动会拒绝；筛选隐藏的同级任务保留原来的排序位置。只修改排序字段，父子关联和正文不变。`viewID` 可选，传入后将对应视图切换为手动排序；整个动作可撤回。

```json
{"command":"task.move","id":"TASK_B","fields":{"targetID":"TASK_A","placement":"before","orderedIDs":["TASK_A","TASK_B"],"viewID":"view:LIST_ID"}}
```

```json
{"command":"list.update","id":"LIST_ID","fields":{"sections":["准备","执行","交付"]}}
```

```json
{"command":"view.update","id":"view:all","fields":{"sort":"manual","group":"section"}}
```

sort 为 manual/priority/date/title/created；group 为 none/section/list/priority；置顶始终在前。任务 rank 为手动排序整数。专项 sections 最多 30 个唯一名称，任务 section 可为空。

```json
{"command":"task.list","filter":{"view":"all","listIDs":["LIST_ID"],"tags":["工作","写作"],"matchAny":true,"excludedTags":["等待"],"excludedLists":[],"priority":3,"pinnedOnly":false,"itemType":"task","search":"周报"}}
```

matchAny=false 时包含条件 AND，true 时 OR。排除、文字、日期和置顶始终同时生效。itemType 为 task/note/all，includeCompleted 可包含已完成项。保存筛选使用 filter.add/update 的 query 文本字段，内容为上述 filter 对象序列化的 JSON。兼容旧版 listID/tag 单条件。

当前 filter.dueFrom/dueThrough 使用 Foundation Date 的数值编码（自 2001-01-01T00:00:00Z 起的秒数），区间两端均包含；App 编辑器负责生成。任务的日期字段仍使用 ISO 8601。不要把任务日期字符串直接放入筛选日期字段。

支持的命令：direction.list/add/update；project.list/add/update（兼容 list.list/add/update）；task.list/get/add/update/complete/reopen/trash/restore/batch/reorder/move/duplicate/convert；filter.list/add/update；template.list/save/use/trash；view.update；history.list；event.undo；status。

任务可编辑字段：title、notes、richNotes（RTF 的 Base64）、itemType（新增时）、listID、parentID、tags、priority、due、end、allDay、recurrence、status、progress、pinned、rank、section。富文本同时更新 notes，且应与 RTF 中的纯文字一致。completed/trashed 用专用命令。模板和复制返回新根任务，子任务可从任务查询结果的 parentID 找到。

## 数据与同步

每次修改生成不可变事件。不同字段的并发修改合并；同一字段按逻辑时钟、设备标识和事件 ID 排序。撤回只能检查本机已收到的历史，不能提前判断离线设备尚未上传的变化。

写入成功仅表示本机已保存，iCloud 异步传输。备份保留全部事件。单次请求/响应上限 1 MB，超时 15 秒；大查询请按专项、搜索或标签缩小范围。任务查询目前没有分页，历史查询有分页。

完成重复任务会按确定的下一次 ID 创建后继，避免多设备重复生成；恢复本次之前先将未完成后继移入回收站。进度设置到 100% 不等于完成，下一次重复任务的进度重置为 0。

`scripts/verify_cli.py /path/to/lifeos` 验证实际运行的 App。脚本的测试任务、模板、筛选和专项最终可恢复地隐藏或移入回收站，不删除真实任务。

`scripts/verify_structure_cli.py /path/to/lifeos /tmp/structure-qa.json` 验证方向、专项与子树移动，输出验收实体 ID 供同步核对，并可恢复清理自己的记录。
