# 从 GitHub 恢复开发

项目自 2026-11-08 起暂停主动开发；GitHub `main` 是继续开发的源码入口。最新 Mac 审核修复为 1.0.0 build 17，已移除不必要的入站网络权限，并保留本地 Agent 通信。

```sh
git clone https://github.com/Alex-cloud0413/lifeos-app.git
cd lifeos-app
swift test
zsh scripts/build.sh preview
```

需要完整 Xcode。Preview 使用独立本地任务库，不连接个人 iCloud。正式签名和同步配置见 [构建与 iCloud](building.md)。

## 源码之外的内容

- 仓库保留源码、图标与纸纹原始资源、测试、配置模板、MIT 许可证和开发文档。
- `Config/Local.xcconfig`、证书、私钥、描述文件及账号登录状态不进入 GitHub。恢复时重新配置 Apple 开发者账号和自己的应用标识。
- 个人任务、iCloud 数据和本地数据库不是源码备份的一部分。继续访问已有数据时须保持原应用标识、CloudKit 容器与环境；Development 和 Production 不共用数据。
- `.build/`、`build/`、导出安装包和日志可重新生成，不作为恢复源码的前提。

## 重新发行前

先在 App Store Connect 核对当前版本、销售范围和审核状态，再决定是否恢复发行。源码存档或重新构建不会自动恢复商店销售；新版本仍需按 Apple 当前要求验证签名、隐私、同步和提交审核。

历史上已执行的检查见 [验证记录](verification.md)。这些记录不能替代恢复后使用当前工具链和真实设备重新验收。
