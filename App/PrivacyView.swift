import SwiftUI

enum ProductLinks {
    static let privacy = URL(string: "https://github.com/Alex-cloud0413/lifeos-app/blob/main/docs/privacy.md")!
    static let support = URL(string: "https://github.com/Alex-cloud0413/lifeos-app/blob/main/docs/support.md")!
}

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("你的设备与 iCloud") {
                    Text("方向、专项、任务、备注、模板与操作历史保存在设备上；开启 iCloud 时，由 Apple CloudKit 同步至当前 Apple Account 的私有数据库。多台设备需要登录同一账号，并为 Life · OS 开启 iCloud。")
                    Text("开发者不接收这些内容，也没有用于存储任务的服务器。App 没有广告、行为分析 SDK 或自建账号。iCloud 服务由 Apple 提供，使用你的 iCloud 存储空间。")
                }
                Section("同步、备份与删除") {
                    Text("离线时可以继续记录，联网后由系统同步。同步会传播修改和删除，不是独立备份；请按需在设置中导出备份，保存位置由你选择。")
                    Text("移入回收站可以恢复；清空回收站后不能通过界面恢复。为支持历史合并，旧内容仍可能保留在操作记录及完整备份中，清空回收站不等于抹除全部历史。")
                    Text("iCloud 数据可在系统的 iCloud 储存管理中删除。设备上的副本、其他设备和已导出的备份需分别处理；仍保留副本的设备可能再次上传数据。卸载 App 不等于删除 iCloud 数据。")
                }
                Section("本地 Agent 与主动分享") {
                    Text("Mac 的本地 Agent 连接默认关闭。启用后，同一 Mac 登录用户下的本地程序可通过接口读取和修改任务；你可以随时关闭连接。")
                    Text("App 不会主动把任务发送给 AI 服务。你选择的 Agent、导出的备份或主动提交的反馈可能把内容传至相应服务，请自行决定提供哪些内容。已被这些工具读取的内容不会因关闭连接而撤回。")
                }
                Section("联系与更新") {
                    Text("本说明更新于 2026 年 10 月 3 日。支持页面提供问题反馈渠道；请勿在公开反馈中附上私人任务、备份或账号资料。")
                    Link("在线隐私政策", destination: ProductLinks.privacy)
                    Link("支持与反馈", destination: ProductLinks.support)
                }
            }
            .formStyle(.grouped).paperSurface().navigationTitle("隐私与数据")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.frame(idealWidth: 600, idealHeight: 700)
    }
}
