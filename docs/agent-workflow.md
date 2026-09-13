# Agent 协作：从归类到推进

Agent 是你选择的本地工具。Life · OS 提供可读写的任务接口，不内置模型、聊天服务或远程代理服务器。只要 Agent 可以运行本地命令，就可以接入。

## 连接

1. 构建并打开 Mac App，在「设置 → 本地 Agent」启用连接。
2. 运行 `./build/lifeos status`。自定义签名包按 [构建说明](building.md) 设置 `LIFEOS_BUNDLE_ID`。
3. 给 Agent 可执行文件的位置和允许操作的专项。App 可以在菜单栏继续运行；完全退出后 CLI 不可用。

所有响应是 JSON。成功时 `ok:true`、退出码 0；失败时 `ok:false`、退出码 1。读取失败时应处理错误，不要把空响应当作空任务列表。

## 一轮协作的例子

用户提出：“把我待整理的语言学习事项放进合适的专项，拆出下一步，但不要自动安排日期。”

Agent 先读取现有结构：

```sh
./build/lifeos directions
./build/lifeos projects --direction DIRECTION_ID
./build/lifeos tasks --view inbox
./build/lifeos tasks --project PROJECT_ID
```

若已有“学习一门新语言”专项，应复用它。只有在用户允许新建且没有合适专项时，才创建新的专项：

```sh
./build/lifeos new-project "学习一门新语言" --direction DIRECTION_ID --request-id language-project-01
```

拿到返回的完整 ID 后，把任务放入该专项，并拆出具体行动：

```sh
./build/lifeos update TASK_ID --project PROJECT_ID --revision CURRENT_REVISION --request-id classify-01
./build/lifeos add "整理核心表达" --parent TASK_ID --request-id language-step-01
./build/lifeos add "完成一次录音" --parent TASK_ID --request-id language-step-02
./build/lifeos get TASK_ID
./build/lifeos tasks --project PROJECT_ID
```

这里的 ID 和 revision 都来自查询结果，不能照抄占位符。移动父任务时后代会跟随，子任务继承父任务所属专项。日期可以留空。

实际完成部分工作后，Agent 可以记录证据和下一步：

```sh
./build/lifeos update TASK_ID --progress 40 --status doing --notes "表达素材已整理。下一步：录制一次两分钟表达，再标记需要改进的位置。" --revision LATEST_REVISION --request-id progress-01
```

`--notes` 会替换备注字段。已有重要正文时，先读取并保留需要保留的内容；已有富文本时，按 [CLI 说明](cli.md) 同步维护 `richNotes` 与纯文本，避免格式与内容不一致。修改后回读，确认归属、正文和子任务都符合预期。

## 可交给 Agent 的工作约定

```text
用 Life · OS 的 CLI 协助整理和推进我指定的专项。
先查询方向、专项和相关任务，优先复用已有结构。
依据我给出的范围归类，拆成可执行子任务；保留已有正文和手动添加的子任务。
不确定归属时提出建议，不凭空补充事实或截止日期。
每次更新前读取最新 revision；遇到冲突，重新读取并比较，不直接覆盖。
同一次写入重试使用同一 request-id；回读确认后再报告完成。
完成状态只依据实际完成证据；阶段进展用状态、进度和备注表达。
删除、清空回收站、对外发布或发消息需要我明确授权。
CLI 的成功只说明本机保存成功，不声称其他设备已经同步。
```

这些是给 Agent 的工作约定，App 不会把自然语言约定转换成权限隔离。连接可读写当前 Mac 用户的全部 App 任务，没有按 Agent 或专项划分的权限令牌。请只连接你信任且已授权的本地工具。

## 并发与恢复

- 相同 `requestID` 防止一次写入因重试而重复执行。
- `expectedRevision` / `--revision` 检测已发生的修改，冲突时重新读取。
- 更新会产生不可变事件，`history` 可查，`undo` 在不存在冲突时撤回。
- Mac App 按顺序处理命令并保存，再交由 CloudKit 异步同步。
- 每个 Agent 的查询范围、行动权限和结果验证由使用者与该 Agent 配置；App 不会替外部工具发布内容。

完整命令、批量请求和排序协议见 [CLI 文档](cli.md)。
