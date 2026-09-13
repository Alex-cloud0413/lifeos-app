# Contributing / 参与贡献

欢迎围绕专项推进、层级操作、可读的任务内容和可靠的 Agent 协作改进 Life · OS。较大的产品方向变化请先开 Issue 讨论。你也可以直接 Fork，按自己的需求独立演化。

1. 从 `main` 创建分支，说明具体问题与修改后的行为。
2. 使用 Preview 配置和自建的示例任务开发。自己的签名设置只放在 `Config/Local.xcconfig`。
3. 修改任务规则、数据结构、导航或排序时，补充能体现实际失败场景的回归测试。
4. 运行 `swift test`，按平台构建并检查相关界面。仅在自己的测试任务库中运行 `scripts/verify_cli.py` 或 `scripts/verify_structure_cli.py`，这些脚本会创建和修改测试记录。
5. 提交前检查变更范围，不提交数据库、任务导出、签名、账号、构建日志或私人截图。
6. 在 PR 中写明改变了什么、验证了什么及尚未验证的设备。不要把编译通过表述为真机同步已验证。

提交贡献表示同意以仓库的 MIT 许可证提供该贡献。新增依赖或资源需注明来源与许可证。不要复制其他产品的专有代码、图标或截图。

English: please include the problem, resulting behavior, and validation in your PR. Use the local Preview and synthetic data; keep all signing credentials and private task content out of commits. Contributions are under MIT.
