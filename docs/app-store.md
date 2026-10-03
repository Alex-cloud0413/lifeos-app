# App Store 1.0 上架资料与发布流程

状态：准备中，未提交审核。定价：免费（用户于 2026-10-03 确认）；无订阅、无内购、无广告。保留方向优先的默认首页和可选的 Mac 本地 Agent 接口。

## 商店文案草稿

- 名称：Life · OS
- 副标题：以专项推进，与 Agent 协作
- 分类：效率 / Productivity
- 主要语言：简体中文（界面当前以中文为主）
- 隐私政策 URL：`https://github.com/Alex-cloud0413/lifeos-app/blob/main/docs/privacy.md`
- 支持 URL：`https://github.com/Alex-cloud0413/lifeos-app/blob/main/docs/support.md`
- 关键词：专项,任务,项目,子任务,日程,待办,笔记,iCloud,个人管理,Agent
- 宣传文本：从方向到专项，再到每一个具体行动。多层子任务、专注备注与个人 iCloud 同步，让事项有归属，也有下一步。

描述：

> Life · OS 是以专项推进的个人日程与任务管理工具。
>
> 先建立长期关注的方向，在方向下组织专项，再把具体事情拆成任务与多层子任务。默认首页从方向开始，日期按需安排。
>
> • 用方向、专项与多层子任务整理工作、生活与学习。
> • 通过备注、全屏编辑、进度、标签、模板和拖动排序持续推进。
> • 从今天、未来 7 天、本月、本季度或日历查看排期。
> • 在自己的 iCloud 私有数据库同步；同一 Apple Account 的设备共享记录，离线也能继续记录。
> • Mac 可主动开启本地接口，配合单独构建的开源 CLI 与自选 Agent 整理分类、拆解任务、更新进度。无需 Agent 也可使用任务管理功能。
>
> 免费使用，无广告、无内购，不需要另建账号。App 不内置 AI 模型或提醒功能。
>
> 跨设备同步需要为 App 开启 iCloud、可用网络与足够的个人 iCloud 空间；同步不是独立备份，可在设置中导出完整备份。当前界面以中文为主。

## 审核备注草稿

No app-specific account or sign-in is required. The app remains usable locally without iCloud. To test sync, sign into the same Apple Account in system settings on two devices, enable iCloud for the app, then create a direction, project and task. CloudKit uses only the current user's private database; there is no developer task backend or public task database.

The optional Mac local Agent interface is off by default and requires explicit user activation in Settings. It uses a local Unix-domain socket restricted to the current operating-system user. It accepts validated task commands; it does not download or execute code, install helpers, launch on login or require an AI provider. The separately built open-source CLI is optional, not necessary for the app's task-management features. Background remote notifications are used only for iCloud synchronization; there are no scheduled task reminders.

Privacy policy is available offline in Settings → 隐私与数据 and at the public URL above. The app is free, without purchases, subscriptions, ads or analytics SDKs. Screenshots must contain synthetic examples only.

## 隐私申报依据

拟选择「不收集数据」：App 没有开发者任务服务器、广告、分析 SDK 或开发者可访问的用户内容库。Apple 为用户提供的私有 iCloud 存储与用户主动使用外部 Agent/导出/反馈的行为，在政策中分别说明。发布前必须再检查最终二进制与第三方依赖，并在后台按实际问题作答；此文件不是已提交的隐私申报。

主 App 隐私清单：UserDefaults / CA92.1（自己的偏好）；FileTimestamp / C617.1（本机容器内 socket 文件类型、属主等元数据检查）。分享扩展无已发现的 required-reason API。App 使用 Apple 提供的加密通信，没有自定义加密实现，`ITSAppUsesNonExemptEncryption = NO`。

## 构建与环境

1. 将自己的签名信息放入被忽略的 `Config/Local.xcconfig`。代码仓库不保存凭据、个人设备信息或数据。
2. `Debug` / `Release` / `scripts/build.sh cloud` 仍使用 Development；`Preview` 不联网。正式构建必须使用 `Config/AppStore.xcconfig`。
3. `zsh scripts/archive-app-store.sh macos` 或 `ios` 生成 Production 数据环境的 archive。归档阶段遵循 Xcode 自动开发签名，分发阶段再转换为 App Store 签名及 Production 推送权限；开发签名 archive 不能直接提交。可用 `--unsigned` 仅检查编译和包内容。
4. 检查 archive：版本、Bundle ID、容器、Production 环境、App 与扩展的隐私清单、签名及 profile。
5. 在 CloudKit Console 部署 schema；只复制类型、字段与索引，不复制个人 Development 数据。Production 使用独立 `Cloud-Production.store`，不会自动读取旧 `Cloud.store` 或 `Preview.store`。
6. 使用 Xcode Organizer → Distribute App → App Store Connect / TestFlight 转换分发签名。或运行 `xcodebuild -exportArchive -archivePath build/AppStore-macos.xcarchive -exportPath build/AppStore-macos-export -exportOptionsPlist Config/AppStore-Export.plist -allowProvisioningUpdates`，iOS 替换路径中的平台名。此配置仅导出，不上传；实际分发包的签名及权限还需检查。上传后需等待后台处理及检查，不能以构建通过代替后台验证。

## 发布前必须完成的验收

- Production 同一账号 Mac ↔ iPhone 双向新增、编辑、排序、删除同步；离线重连和冲突合并。
- 第二个 Apple Account 的独立数据库；账号登出/切换后不把原账号记录带给另一账号。必须真机验证，不以代码里 `.private` 替代。
- 新用户空库、未登录 iCloud、空间不足、同步失败；本地保存和恢复提示正确。
- iPhone/iPad/Mac 适配、分享扩展、快捷指令、可选 Agent、隐私页和支持链接。
- 同账号正式安装升级与个人 Development 数据迁移单独验收。不能直接替换既有个人安装；先导出备份，经过用户同意后向 Production 合并导入。
- 完善年龄分级、审核联系人、版权、分发地区、适用的备案/法律信息、最终免费价格；不猜测或代签声明。
- 上传当前构建的合成数据截图，确认无私人内容、设备信息或未经实现的功能承诺。
- 向用户展示最终保存的版本、定价、地区、隐私与待测项；收到明确「提交审核」后再提交。

## 官方依据

- [CloudKit private database](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)
- [部署 schema](https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema)
- [App 隐私详情](https://developer.apple.com/app-store/app-privacy-details/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Required-reason API 清单](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
