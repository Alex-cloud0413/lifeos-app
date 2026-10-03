# Life · OS 隐私政策 / Privacy Policy

更新日期：2026-10-03。适用于本仓库发布的 Life · OS。维护者：[Alex-cloud0413](https://github.com/Alex-cloud0413)。

## 数据存储

方向、专项、任务、子任务、备注、标签、模板和操作历史保存在用户设备上。启用 iCloud 时，App 使用 Apple CloudKit **当前 Apple Account 的私有数据库**同步这些数据，不使用公共数据库存储任务。设备保留离线副本；跨设备同步需要同一 Apple Account、为 App 开启 iCloud、可用的网络及 iCloud 空间。

开发者不接收这些任务内容，没有任务存储服务器、自建用户账号、广告或行为分析 SDK。iCloud 服务由 Apple 提供，适用 Apple 的服务条款与隐私政策；存储占用计入用户的 iCloud 配额。同步由系统安排，不保证实时完成。

App 在设备内保存界面偏好、本地 Agent 开关和随机设备标识。随机标识用于合并操作历史，不用于广告或跟踪；它随操作历史同步到用户自己的 iCloud。

## 保留、备份与删除

数据由用户管理。离线修改保存在设备上，网络恢复后由系统同步。同步会传播修改与删除，**不能代替独立备份**。用户可以通过系统文件选择器导出完整备份，保存到 iCloud 云盘或自己选择的其他位置；App 不会替用户上传到其他备份服务。

回收站中的任务可以恢复。清空回收站后，界面不再提供恢复入口；由于 App 使用操作历史合并多端修改，原始内容仍可能保留在历史事件及完整导出文件中。**清空回收站不是安全抹除全部历史的功能。**

用户可在 Apple 系统的 iCloud 储存管理中删除该 App 的云端数据。各设备上的副本及已导出的备份需要分别处理；仍保存副本的设备可能再次上传数据。卸载 App 不代表删除 iCloud 数据。开发者无法代用户访问或删除其私有 iCloud 任务。

## 本地 Agent、分享与支持

Mac 上的本地 Agent 连接默认关闭，由用户主动启用或关闭。启用时，当前 Mac 登录用户下的本地程序可通过本机接口读取和修改全部任务与备注。App 不内置模型，不要求模型 API Key，也不会主动把任务发送给 AI 服务。

用户选用的 Agent 可能将读取内容传给其服务提供方；该行为取决于所选工具及其设置、隐私政策。关闭本地连接可阻止后续接口访问，但不能撤回已经被工具读取的内容。主动分享、导出或提交反馈的内容，由用户决定，按所选目标的规则处理。

支持页面与源代码托管在 GitHub。访问外部页面时，相关网站会按自己的政策处理访问。公开 Issue 不适合提交私人任务、完整备份、账号或设备凭据。开发者仅会看到用户主动提交的反馈；修复问题不需要用户提供完整任务库。用户可在 GitHub 编辑或删除自己提交的内容，并通过[支持页面](support.md)联系维护者。

## 更新

产品的数据处理方式变化时，本政策及 App 内说明会同步更新。政策发布不代表 App 已在 App Store 上架。

## English

Life · OS stores projects, tasks, notes, templates and change history on your devices and, when iCloud is enabled, in the current Apple Account's **private CloudKit database**. The developer does not receive this content and operates no task-storage or account server. There are no ads, analytics SDKs or tracking. Apple provides iCloud under its own terms and privacy policy; data uses your iCloud storage quota. Devices must use the same Apple Account with iCloud enabled for the app. Sync is scheduled by the system and is not guaranteed to be immediate.

Interface preferences and the Agent setting stay on device. A random device identifier is used in change history to merge edits; it syncs only as part of your private history and is not used for advertising or tracking.

Sync propagates edits and deletions and is not a separate backup. You choose where exported backups are saved. Emptying Trash removes recovery through the app interface, but **original content may remain in immutable change history and full backups**. It is not a secure erase of all history. Cloud data can be removed through Apple's iCloud storage management. Local copies on every device and exported backups must be handled separately; devices retaining data may upload it again. Uninstalling does not delete your iCloud data. The developer cannot access or delete it for you.

The Mac local Agent interface is off by default. When enabled, processes running as your current Mac user can read and modify tasks and notes. Life · OS does not send data to an AI provider; an Agent you choose may do so under its own policies. Disabling the interface stops future access but does not recall data already read. You control exports, sharing and support submissions. GitHub hosts the source and support pages; its own privacy policy applies to visits and submissions. Do not post private tasks, backups or credentials in public issues. Contact the maintainer through [Support](support.md).
