#if os(macOS)
import Foundation
import Darwin

final class AgentServer {
    private var listener: Int32 = -1
    private var socketPath = ""
    private let queue = DispatchQueue(label: "dayline.agent.accept")
    func start(handler: @escaping @MainActor @Sendable (AgentRequest) -> AgentResponse) throws {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        let directory = base.appendingPathComponent(sandboxed ? "DL" : "LifeOS", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent("cli.sock").path
        var st = stat()
        if lstat(directory.path, &st) == 0 {
            guard st.st_uid == getuid(), (st.st_mode & S_IFMT) == S_IFDIR else { throw CommandError("unsafe_directory", "本地连接目录的所有者或类型异常。") }
        }
        chmod(directory.path, 0o700)
        if lstat(path, &st) == 0 {
            guard st.st_uid == getuid(), (st.st_mode & S_IFMT) == S_IFSOCK else { throw CommandError("unsafe_socket", "连接路径被其他文件占用。") }
            let probe = socket(AF_UNIX, SOCK_STREAM, 0)
            var addr = try LocalTransport.address(path)
            let active = withUnsafePointer(to: &addr) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 } }
            close(probe)
            guard !active else { throw CommandError("already_running", "已有一个 Life · OS 实例提供本地连接。") }
            unlink(path)
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CommandError("socket_failed", "无法创建本地连接。") }
        var addr = try LocalTransport.address(path)
        let bound = withUnsafePointer(to: &addr) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard bound == 0 else { close(fd); throw CommandError("bind_failed", "无法开启本地连接：\(String(cString: strerror(errno)))") }
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else { close(fd); unlink(path); throw CommandError("listen_failed", "无法监听本地连接。") }
        listener = fd; socketPath = path
        queue.async {
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { break }
                guard LocalTransport.sameUser(client) else { close(client); continue }
                LocalTransport.configure(client)
                // Serialize clients with bounded I/O; database mutations always execute on MainActor.
                do {
                    let data = try LocalTransport.readLine(client)
                    let request = try JSONDecoder().decode(AgentRequest.self, from: data)
                    let done = DispatchSemaphore(value: 0)
                    Task { @MainActor in
                        let response = handler(request)
                        do { try LocalTransport.writeLine(JSONEncoder().encode(response), to: client) } catch { }
                        close(client); done.signal()
                    }
                    done.wait()
                } catch {
                    let response = AgentResponse(ok: false, message: error.localizedDescription, errorCode: "invalid_request")
                    if let data = try? JSONEncoder().encode(response) { try? LocalTransport.writeLine(data, to: client) }
                    close(client)
                }
            }
        }
    }
    func stop() {
        guard listener >= 0 else { return }
        shutdown(listener, SHUT_RDWR); close(listener); listener = -1
        if !socketPath.isEmpty { unlink(socketPath) }
    }
    deinit { stop() }
}
#endif
