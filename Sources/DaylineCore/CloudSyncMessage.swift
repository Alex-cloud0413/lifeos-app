import Foundation
import CloudKit

/// Keeps server diagnostics out of the interface while preserving a useful recovery action.
public enum CloudSyncMessage {
    public static func failure(_ error: Error) -> String {
        let codes = cloudCodes(error)
        if codes.contains(CKError.quotaExceeded.rawValue) {
            return "iCloud 空间不足 · 修改已保存在本机，请释放 iCloud 空间后重试"
        }
        if codes.contains(CKError.notAuthenticated.rawValue) {
            return "iCloud 尚未登录 · 修改已保存在本机，请在系统设置中登录"
        }
        if codes.contains(CKError.networkUnavailable.rawValue) || codes.contains(CKError.networkFailure.rawValue) {
            return "网络暂不可用 · 修改已保存在本机，连接恢复后自动同步"
        }
        if codes.contains(CKError.serviceUnavailable.rawValue) || codes.contains(CKError.requestRateLimited.rawValue) || codes.contains(CKError.zoneBusy.rawValue) {
            return "iCloud 暂时繁忙 · 修改已保存在本机，系统会稍后重试"
        }
        return "暂未完成 iCloud 同步 · 修改已保存在本机，请稍后检查状态"
    }

    private static func cloudCodes(_ error: Error, depth: Int = 0) -> Set<Int> {
        guard depth < 5 else { return [] }
        let ns = error as NSError
        var codes: Set<Int> = ns.domain == CKErrorDomain ? [ns.code] : []
        if let nested = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            codes.formUnion(cloudCodes(nested, depth: depth + 1))
        }
        if let partial = ns.userInfo[CKPartialErrorsByItemIDKey] as? NSDictionary {
            for case let nested as NSError in partial.allValues {
                codes.formUnion(cloudCodes(nested, depth: depth + 1))
            }
        }
        return codes
    }
}
