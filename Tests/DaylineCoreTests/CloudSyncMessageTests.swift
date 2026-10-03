import XCTest
import CloudKit
@testable import DaylineCore

final class CloudSyncMessageTests: XCTestCase {
    func testNestedQuotaFailureProvidesActionInsteadOfServerDetails() {
        let quota = NSError(domain: CKErrorDomain, code: CKError.quotaExceeded.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: "private server diagnostic"])
        let partial = NSError(domain: CKErrorDomain, code: CKError.partialFailure.rawValue,
                              userInfo: [CKPartialErrorsByItemIDKey: ["record": quota]])
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134400, userInfo: [NSUnderlyingErrorKey: partial])
        let message = CloudSyncMessage.failure(wrapped)
        XCTAssertTrue(message.contains("空间不足"))
        XCTAssertTrue(message.contains("保存在本机"))
        XCTAssertFalse(message.contains("private server diagnostic"))
    }
    func testAuthenticationAndOfflineHaveDifferentRecoveryInstructions() {
        let auth = CloudSyncMessage.failure(CKError(.notAuthenticated))
        let offline = CloudSyncMessage.failure(CKError(.networkUnavailable))
        XCTAssertTrue(auth.contains("系统设置中登录"))
        XCTAssertTrue(offline.contains("连接恢复后自动同步"))
    }
    func testUnknownFailureDoesNotClaimCloudSuccess() {
        let message = CloudSyncMessage.failure(NSError(domain: "unknown", code: 1))
        XCTAssertTrue(message.contains("暂未完成"))
        XCTAssertFalse(message.contains("同步成功"))
    }
}
