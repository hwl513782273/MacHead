import Foundation
import AppKit
import Darwin

public struct RemoteSharingStatus {
    public let isSSHEnabled: Bool
    public let isVNCEnabled: Bool
    public let isSMBEnabled: Bool
}

public final class RemoteSharingService: ObservableObject {
    public static let shared = RemoteSharingService()

    @Published public private(set) var isSSHRunning: Bool = false
    @Published public private(set) var isVNCRunning: Bool = false
    @Published public private(set) var isSMBRunning: Bool = false
    @Published public private(set) var isChecking: Bool = false

    public var currentUser: String {
        return NSUserName()
    }

    public var localIP: String {
        return WebServer.shared.getLocalIPAddress()
    }

    public var sshCommand: String {
        return "ssh \(currentUser)@\(localIP)"
    }

    public var vncURL: String {
        return "vnc://\(localIP)"
    }

    public var smbURL: String {
        return "smb://\(localIP)"
    }

    private init() {
        refresh()
    }

    public func refresh(completion: ((RemoteSharingStatus) -> Void)? = nil) {
        isChecking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let ssh = Self.isPortListening(port: 22)
            let vnc = Self.isPortListening(port: 5900)
            let smb = Self.isPortListening(port: 445)
            let status = RemoteSharingStatus(isSSHEnabled: ssh, isVNCEnabled: vnc, isSMBEnabled: smb)
            DispatchQueue.main.async {
                self.isSSHRunning = ssh
                self.isVNCRunning = vnc
                self.isSMBRunning = smb
                self.isChecking = false
                completion?(status)
            }
        }
    }

    public static func isPortListening(port: in_port_t) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var tv = timeval(tv_sec: 0, tv_usec: 150_000) // 150ms timeout
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let res = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return res == 0
    }

    public func openSystemSharingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension"),
           NSWorkspace.shared.open(url) {
            return
        }
        let fallbackPath = "/System/Library/PreferencePanes/SharingPref.prefPane"
        if FileManager.default.fileExists(atPath: fallbackPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: fallbackPath))
        }
    }
}
