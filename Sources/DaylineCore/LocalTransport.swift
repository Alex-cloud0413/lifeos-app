import Foundation
#if os(macOS)
import Darwin

public enum LocalTransport {
    public static var candidates: [String] {
        let home = String(cString: getpwuid(getuid()).pointee.pw_dir)
        let bundleID = ProcessInfo.processInfo.environment["LIFEOS_BUNDLE_ID"] ?? "com.example.LifeOS"
        return socketCandidates(home: home, bundleIdentifier: bundleID)
    }
    public static func socketCandidates(home: String, bundleIdentifier: String) -> [String] {
        [
            home + "/Library/Containers/" + bundleIdentifier + "/Data/Library/Application Support/DL/cli.sock",
            home + "/Library/Application Support/LifeOS/cli.sock"
        ]
    }

    public static func address(_ path: String) throws -> sockaddr_un {
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { throw CommandError("socket_path", "本地连接路径过长。") }
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in dest.copyBytes(from: bytes) }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return addr
    }
    public static func configure(_ fd: Int32) {
        var one: Int32 = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    }
    public static func sameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0; var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }
    public static func readLine(_ fd: Int32) throws -> Data {
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= 1_048_576 {
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { throw CommandError("connection_closed", "本地连接中断或超时；可使用同一 requestID 重试。") }
            if let newline = buffer.prefix(count).firstIndex(of: 10) { data.append(contentsOf: buffer[..<newline]); return data }
            data.append(contentsOf: buffer.prefix(count))
        }
        throw CommandError("too_large", "单次请求或响应超过 1 MB；请缩小查询范围。")
    }
    public static func writeLine(_ data: Data, to fd: Int32) throws {
        var payload = data; payload.append(10)
        try payload.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                let count = send(fd, bytes.baseAddress!.advanced(by: sent), bytes.count - sent, 0)
                guard count > 0 else { throw CommandError("write_failed", "本地连接写入失败。") }
                sent += count
            }
        }
    }
    public static func call(_ request: AgentRequest, path: String? = nil) throws -> AgentResponse {
        let selected = path ?? ProcessInfo.processInfo.environment["LIFEOS_SOCKET"] ?? candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? candidates[0]
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CommandError("socket_failed", "无法建立本地连接。") }
        defer { close(fd) }; configure(fd)
        var addr = try address(selected)
        let status = withUnsafePointer(to: &addr) { ptr in ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard status == 0, sameUser(fd) else { throw CommandError("app_unavailable", "请先打开 Life · OS，并在「设置 → 本地 Agent」启用连接。") }
        try writeLine(JSONEncoder().encode(request), to: fd)
        return try JSONDecoder().decode(AgentResponse.self, from: readLine(fd))
    }
}
#endif
