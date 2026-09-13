# 构建与 iCloud / Build and iCloud

## 本机预览

需要完整 Xcode，工程使用文件夹同步组与 Swift 6 工具链（Xcode 16 或更新版本）。部署目标为 macOS 14、iOS/iPadOS 17。当前公开源码的验证工具链见 [验证说明](verification.md)。

```sh
swift test
zsh scripts/build.sh preview
```

此命令构建 Mac App 和 CLI。App 输出路径为 `build/PreviewDerivedData/Build/Products/Preview/Dayline.app`，CLI 为 `build/lifeos`。Preview 使用本机 `LifeOS/Preview.store`，不连接 CloudKit；无需开发者账号。预览数据不会自动迁移到 CloudKit。

在 Xcode 中打开 `Dayline.xcodeproj`。选择 `Dayline-Mac` 或 `Dayline-iOS`，在 Edit Scheme → Run 中将 Build Configuration 设置为 **Preview**。iOS 选择已安装的模拟器。实体设备请使用下方签名配置。

## 自己的 Apple 配置

不要复用其他人的应用标识、证书或云容器。复制模板：

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

在被 Git 忽略的 `Config/Local.xcconfig` 填写自己的值：

```xcconfig
LIFEOS_TEAM_ID = YOUR_TEAM_ID
LIFEOS_BUNDLE_ID = com.yourname.LifeOS
LIFEOS_CLOUD_CONTAINER = iCloud.com.yourname.LifeOS
LIFEOS_APP_GROUP = group.com.yourname.LifeOS
LIFEOS_URL_SCHEME = lifeos
```

1. 在 Xcode 登录自己的 Apple 开发者账号。需要使用 CloudKit 的签名能力；账号及分发方式以 Apple 当前要求为准。
2. 在 Apple Developer 中为主 App 注册所填 Bundle ID，并为分享扩展注册相同 ID 加 `.Share`。两个平台的主 App 使用同一主标识。
3. 为主 App 启用 iCloud/CloudKit，并创建、关联所填容器。为 iOS 主 App 和分享扩展启用同一个 App Group。检查 Xcode 的 Signing & Capabilities 与配置一致。
4. 选择 **Debug** 或 **Release**，开启自动签名；设备构建时由 Xcode 取得匹配的描述文件。分享扩展也需要正确的团队与签名。
5. 在 Mac 和 iPhone 登录相同 iCloud 账号，构建同一容器、同一 CloudKit 环境的 App。先双向创建一条测试任务，并检查「设置与同步」的上传、下载及错误状态。

Mac 可执行 `zsh scripts/build.sh cloud`；iPhone 在 Xcode 选择设备运行。脚本使用 Apple Development 签名，适用于你登记的开发设备。公开仓库没有任何可供他人复用的签名文件或作者的云端账户。

`Shared.xcconfig` 将上述值同时传给主 App、分享扩展的 Info.plist 和 entitlements。运行时通过 `AppConfiguration` 读取，避免只改签名却仍访问旧容器。不要直接编辑 `.pbxproj` 中的个人标识；常规个人配置只放在 Local.xcconfig。

## Development 与 Production

本项目的云配置默认使用 **Development**。同一 Apple 账号、容器和环境是跨设备访问同一份私有数据的前提。Development 和 Production 数据互相独立；部署 schema 不会复制已有任务记录。准备正式分发时，需要自己设计并验证数据迁移、生产 schema 和签名方案，不能仅切换环境来替代迁移。

CloudKit 的后台通知用于同步，不是任务提醒。应用没有日程到时提醒功能。

## CLI 连接自己的构建

Preview 可直接运行 `./build/lifeos status`。开启 App 的本地 Agent 连接后，自定义签名版本请使用：

```sh
export LIFEOS_BUNDLE_ID=com.yourname.LifeOS
./build/lifeos status
```

可用 `LIFEOS_SOCKET` 或命令的 `--socket PATH` 明确指定连接位置；`--socket` 优先。沙盒版通常位于 `~/Library/Containers/<Bundle ID>/Data/Library/Application Support/DL/cli.sock`；非沙盒 Preview 位于 `~/Library/Application Support/LifeOS/cli.sock`。Unix socket 路径有长度限制，过长的用户目录或 Bundle ID 会返回明确错误。

自定义 URL Scheme 后，CLI 也需设置相同的 `LIFEOS_URL_SCHEME`。同时运行多份 Fork 时，用显式 socket 路径选择要操作的 App。

## Apple 参考

- [使用构建配置文件](https://developer.apple.com/documentation/xcode/adding-a-build-configuration-file-to-your-project)
- [在 App 中启用 CloudKit](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app)
- [部署 iCloud 容器 schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)
- [向登记设备分发开发 App](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)

English: use Preview for local-only development. For iCloud, copy the local configuration template, supply your own Apple team, bundle ID, CloudKit container and App Group, then sign both the app and iOS share extension. All devices must use the same account, container and environment. Production deployment and data migration are separate tasks.
