# 公开源码验证

日期：2026-09-14。版本：0.6.0（14）。本次使用 Xcode 27 RC，在 macOS 上验证。

| 检查 | 结果 |
| --- | --- |
| `swift test` | 46 项通过；包括任务结构、事件投影、重复、模板、回收站、导航、排序及 Fork 配置回归 |
| Mac Preview + CLI | 通过 `scripts/build.sh preview` 构建；App 实际启动，显示独立空任务库；CLI 帮助可执行 |
| iOS Preview | iOS 模拟器目标及分享扩展构建通过 |
| Apple 配置 | 主 App 和扩展的生成 Info.plist 使用公开配置变量；自定义 Bundle ID、CloudKit 与 App Group 的构建设置解析通过 |
| 公开内容 | 只发布源码、资源、测试、通用配置和文档；不含个人任务、运行库、私人历史验收资料或签名文件 |

本次未替换原有个人安装，也未使用其他人的 Apple 账号做云端验收。公开默认 Preview 不连接 iCloud。Fork 后的签名、真实设备安装、两端同步和正式分发需要使用自己的配置重新验证。iPad 保留布局兼容，但没有本次 iPad 真机验收。

代码的前身已在个人 Mac/iPhone 使用；公开整理不把此前个人配置的成功等同于所有 Fork 的同步保证。iOS 富文本委托仍有系统 API 弃用警告，当前编译通过。

GitHub Actions 检查核心测试及 Mac Preview；云端 CI 状态以仓库实际运行结果为准，不把本地通过视为 CI 已通过。
