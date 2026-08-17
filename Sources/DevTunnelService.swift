import Foundation

extension Notification.Name {
    public static let devTunnelStatusChanged = Notification.Name("com.waffle.MacHead.devTunnelStatusChanged")
}

public struct DevTunnelPortRule: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var port: String
    public var protocolType: String // "auto", "http", "https"
    public var isEnabled: Bool
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        port: String,
        protocolType: String = "auto",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.port = port
        self.protocolType = protocolType
        self.isEnabled = isEnabled
    }
}

public struct DevTunnelQuotaInfo {
    public var bandwidthUsedBytes: Int64 = 0
    public var bandwidthLimitBytes: Int64 = 5 * 1024 * 1024 * 1024 // 5 GB
    public var currentTunnels: Int = 0
    public var maxTunnels: Int = 10
    public var rawDetails: String = ""
    
    public var bandwidthUsedGB: Double {
        return Double(bandwidthUsedBytes) / (1024.0 * 1024.0 * 1024.0)
    }
    
    public var bandwidthLimitGB: Double {
        return Double(bandwidthLimitBytes) / (1024.0 * 1024.0 * 1024.0)
    }
    
    public var bandwidthPercent: Double {
        guard bandwidthLimitBytes > 0 else { return 0.0 }
        return min(100.0, (Double(bandwidthUsedBytes) / Double(bandwidthLimitBytes)) * 100.0)
    }
}

public enum DevTunnelStatus: Equatable {
    case stopped
    case connecting
    case connected(webUrl: String, sshUrl: String?)
    case error(message: String)
    
    public var displayText: String {
        switch self {
        case .stopped:
            return "未启用 Dev Tunnels 穿透"
        case .connecting:
            return "正在向微软 Azure 申请穿透隧道..."
        case .connected(let webUrl, _):
            return "已成功建立 Dev Tunnels: \(webUrl)"
        case .error(let msg):
            return "穿透失败: \(msg)"
        }
    }
}

public final class DevTunnelService {
    public static let shared = DevTunnelService()
    
    private var process: Process?
    private var isServiceRunning = false
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    public private(set) var activePortUrls: [String: String] = [:]
    
    public private(set) var currentStatus: DevTunnelStatus = .stopped {
        didSet {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .devTunnelStatusChanged, object: self.currentStatus)
            }
        }
    }
    
    private init() {}
    
    public static func loadPortRules() -> [DevTunnelPortRule] {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "devTunnelPortRulesJSON"),
           let rules = try? JSONDecoder().decode([DevTunnelPortRule].self, from: data),
           !rules.isEmpty {
            return rules
        }
        
        let defaultRules = [
            DevTunnelPortRule(name: "MacHead Web 控制台", port: "8080", protocolType: "http", isEnabled: true),
            DevTunnelPortRule(name: "SSH 远程登录", port: "22", protocolType: "auto", isEnabled: true)
        ]
        savePortRules(defaultRules)
        return defaultRules
    }
    
    public static func savePortRules(_ rules: [DevTunnelPortRule]) {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: "devTunnelPortRulesJSON")
        }
    }
    
    public func findBinaryPath() -> String? {
        let defaults = UserDefaults.standard
        if let customPath = defaults.string(forKey: "devTunnelBinaryPath"), !customPath.isEmpty, FileManager.default.fileExists(atPath: customPath) {
            return customPath
        }
        
        let binaryName = "devtunnel"
        let possiblePaths: [String?] = [
            Bundle.main.path(forResource: binaryName, ofType: nil),
            "/Applications/MacHead.app/Contents/Resources/\(binaryName)",
            "\(FileManager.default.currentDirectoryPath)/Resources/\(binaryName)",
            "\(Bundle.main.bundlePath)/Contents/Resources/\(binaryName)",
            "/opt/homebrew/bin/\(binaryName)",
            "/usr/local/bin/\(binaryName)",
            "\(NSHomeDirectory())/bin/\(binaryName)",
            "\(NSHomeDirectory())/.local/bin/\(binaryName)"
        ]
        
        for path in possiblePaths.compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let fullPath = "\(dir)/\(binaryName)"
                if FileManager.default.fileExists(atPath: fullPath) {
                    return fullPath
                }
            }
        }
        
        return nil
    }
    
    public func checkUserLoginStatus() -> String? {
        guard let path = findBinaryPath() else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["user", "show"]
        
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                if output.lowercased().contains("not logged in") || output.isEmpty {
                    return nil
                }
                return output
            }
        } catch {
            return nil
        }
        return nil
    }
    
    public func queryUserLimits(completion: @escaping (DevTunnelQuotaInfo?) -> Void) {
        guard let path = findBinaryPath() else {
            completion(nil)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = ["limits", "-j"]
            
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            
            do {
                try p.run()
                p.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                var info = DevTunnelQuotaInfo()
                var parsed = false
                
                if let jsonData = output.data(using: .utf8),
                   let jsonArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                    for item in jsonArray {
                        let name = (item["name"] as? String ?? "").lowercased()
                        let limit = (item["limit"] as? NSNumber)?.int64Value ?? 0
                        let current = (item["current"] as? NSNumber)?.int64Value ?? 0
                        if name.contains("bandwidth") {
                            info.bandwidthLimitBytes = limit > 0 ? limit : (5 * 1024 * 1024 * 1024)
                            info.bandwidthUsedBytes = current
                            parsed = true
                        } else if name.contains("tunnel") {
                            info.maxTunnels = Int(limit > 0 ? limit : 10)
                            info.currentTunnels = Int(current)
                            parsed = true
                        }
                    }
                }
                
                if !parsed && output.lowercased().contains("bandwidth") {
                    info.rawDetails = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    parsed = true
                }
                
                DispatchQueue.main.async {
                    completion(parsed ? info : nil)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    public func loginWithBrowser(provider: String = "github", completion: @escaping (Bool, String) -> Void) {
        guard let path = findBinaryPath() else {
            completion(false, "未找到 devtunnel 可执行文件")
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            let flag = (provider.lowercased() == "github" || provider.lowercased() == "g") ? "-g" : "-e"
            p.arguments = ["user", "login", flag, "-b"]
            
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            
            do {
                try p.run()
                p.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: data, encoding: .utf8) ?? ""
                if p.terminationStatus == 0 {
                    DispatchQueue.main.async {
                        completion(true, "登录成功")
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(false, out.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }
    
    public func logout() {
        guard let path = findBinaryPath() else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["user", "logout"]
        try? p.run()
    }
    
    public func start() {
        guard !isServiceRunning else { return }
        
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "devTunnelEnabled") else {
            currentStatus = .stopped
            killOrphanedProcesses()
            return
        }
        
        guard let path = findBinaryPath() else {
            currentStatus = .error(message: "未找到 devtunnel 可执行文件")
            return
        }
        
        self.activePortUrls.removeAll()
        
        let mode = defaults.string(forKey: "devTunnelMode") ?? "login"
        let token = (defaults.string(forKey: "devTunnelToken") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let tunnelId = (defaults.string(forKey: "devTunnelId") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let allowAnonymous = defaults.object(forKey: "devTunnelAllowAnonymous") != nil ? defaults.bool(forKey: "devTunnelAllowAnonymous") : true
        
        var args: [String] = ["host"]
        if !tunnelId.isEmpty {
            args.append(tunnelId)
        }
        
        if mode == "token" {
            if token.isEmpty {
                currentStatus = .error(message: "未填写 Dev Tunnel Access Token")
                return
            }
            args.append(contentsOf: ["-t", token])
        } else {
            if checkUserLoginStatus() == nil && token.isEmpty {
                currentStatus = .error(message: "尚未登录微软/GitHub 账号，请在设定中点击登录或填入 Token")
                return
            }
        }
        
        // Multi-port forwarding from custom rules
        let rules = DevTunnelService.loadPortRules().filter { $0.isEnabled && !$0.port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if rules.isEmpty {
            args.append(contentsOf: ["-p", "8080"])
        } else {
            for rule in rules {
                let cleanPort = rule.port.trimmingCharacters(in: .whitespacesAndNewlines)
                if rule.protocolType != "auto" && !rule.protocolType.isEmpty {
                    args.append(contentsOf: ["-p", cleanPort, "--protocol", rule.protocolType])
                } else {
                    args.append(contentsOf: ["-p", cleanPort])
                }
            }
        }
        
        if allowAnonymous {
            args.append("-a")
        }
        
        currentStatus = .connecting
        
        let newProcess = Process()
        newProcess.executableURL = URL(fileURLWithPath: path)
        newProcess.arguments = args
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        newProcess.standardOutput = outPipe
        newProcess.standardError = errPipe
        self.outputPipe = outPipe
        self.errorPipe = errPipe
        
        setupPipeObserver(outPipe)
        setupPipeObserver(errPipe)
        
        newProcess.terminationHandler = { [weak self] proc in
            print("DevTunnelService: devtunnel process terminated with code \(proc.terminationStatus)")
            self?.isServiceRunning = false
            
            DispatchQueue.main.async {
                if self?.currentStatus == .connecting {
                    self?.currentStatus = .error(message: "进程退出 (Code \(proc.terminationStatus))")
                }
            }
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self = self else { return }
                let stillEnabled = UserDefaults.standard.bool(forKey: "devTunnelEnabled")
                if stillEnabled && !self.isServiceRunning {
                    print("DevTunnelService: Attempting auto-restart...")
                    self.start()
                }
            }
        }
        
        do {
            try newProcess.run()
            self.process = newProcess
            self.isServiceRunning = true
            print("DevTunnelService: Launched devtunnel host successfully with \(rules.count) ports")
        } catch {
            print("DevTunnelService: Failed to run devtunnel - \(error.localizedDescription)")
            currentStatus = .error(message: "启动失败: \(error.localizedDescription)")
        }
    }
    
    private func setupPipeObserver(_ pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            self?.parseLogLine(line)
        }
    }
    
    private func parseLogLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        
        // Exact regex match: https://<tunnelid>-<port>.<region>.devtunnels.ms
        if let regex = try? NSRegularExpression(pattern: "https://([a-zA-Z0-9]+)-(\\d+)\\.[a-zA-Z0-9.-]+\\b") {
            let nsString = trimmed as NSString
            let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                let fullUrl = nsString.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
                let port = nsString.substring(with: match.range(at: 2))
                
                if !fullUrl.contains("-inspect") && !fullUrl.contains("tunnels.api.") {
                    self.activePortUrls[port] = fullUrl
                }
            }
        }
        
        if !self.activePortUrls.isEmpty {
            let web = self.activePortUrls["8080"] ?? self.activePortUrls.values.first ?? ""
            self.currentStatus = .connected(webUrl: web, sshUrl: self.activePortUrls["22"])
        }
        
        if lower.contains("unauthorized") || lower.contains("not permitted") || lower.contains("request not permitted") {
            currentStatus = .error(message: "鉴权失败：请点击「登录 GitHub 账号」或填入有效 Token")
        } else if lower.contains("connection refused") || lower.contains("failed to connect") {
            currentStatus = .error(message: "无法连接微软 Azure 边缘中继节点")
        }
    }
    
    public func testConnection(mode: String, tunnelId: String, token: String, allowAnonymous: Bool, rules: [DevTunnelPortRule], completion: @escaping (Bool, String) -> Void) {
        guard let path = findBinaryPath() else {
            completion(false, "未找到 devtunnel 可执行文件")
            return
        }
        
        var args = ["host"]
        if !tunnelId.isEmpty {
            args.append(tunnelId)
        }
        if mode == "token" {
            if token.isEmpty {
                completion(false, "Token 不能为空")
                return
            }
            args.append(contentsOf: ["-t", token])
        } else {
            if checkUserLoginStatus() == nil && token.isEmpty {
                completion(false, "未检测到微软/GitHub 登录凭据，请先点击「登录 GitHub 账号」")
                return
            }
        }
        
        let activeRules = rules.filter { $0.isEnabled && !$0.port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if activeRules.isEmpty {
            args.append(contentsOf: ["-p", "8080"])
        } else {
            for rule in activeRules {
                let cleanPort = rule.port.trimmingCharacters(in: .whitespacesAndNewlines)
                if rule.protocolType != "auto" && !rule.protocolType.isEmpty {
                    args.append(contentsOf: ["-p", cleanPort, "--protocol", rule.protocolType])
                } else {
                    args.append(contentsOf: ["-p", cleanPort])
                }
            }
        }
        
        if allowAnonymous {
            args.append("-a")
        }
        
        let testProcess = Process()
        testProcess.executableURL = URL(fileURLWithPath: path)
        testProcess.arguments = args
        
        let pipe = Pipe()
        testProcess.standardError = pipe
        testProcess.standardOutput = pipe
        
        var finished = false
        var capturedUrl = ""
        let lock = NSLock()
        
        func finish(success: Bool, message: String) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            pipe.fileHandleForReading.readabilityHandler = nil
            if testProcess.isRunning {
                testProcess.terminate()
            }
            DispatchQueue.main.async {
                completion(success, message)
            }
        }
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            lock.lock()
            if let urlMatch = line.range(of: "https://[a-zA-Z0-9.-]+\\.devtunnels\\.ms/?", options: .regularExpression) {
                capturedUrl = String(line[urlMatch])
            }
            let lower = line.lowercased()
            lock.unlock()
            
            if !capturedUrl.isEmpty {
                finish(success: true, message: "连通性测试成功：已就绪 (\(capturedUrl))")
            } else if lower.contains("unauthorized") || lower.contains("not permitted") || lower.contains("request not permitted") {
                finish(success: false, message: "测试失败：未授权或 Token 无效")
            } else if lower.contains("connection refused") || lower.contains("timed out") {
                finish(success: false, message: "测试失败：连接微软中继节点超时")
            }
        }
        
        do {
            try testProcess.run()
        } catch {
            completion(false, "启动测试失败: \(error.localizedDescription)")
            return
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
            lock.lock()
            let isDone = finished
            let url = capturedUrl
            lock.unlock()
            if !isDone {
                if !url.isEmpty {
                    finish(success: true, message: "连通性测试成功：\(url)")
                } else {
                    finish(success: false, message: "测试超时：未在 5 秒内收到 Azure 中继就绪信号")
                }
            }
        }
    }
    
    public func stop() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        
        print("DevTunnelService: Stopping devtunnel...")
        let procToStop = self.process
        self.process = nil
        self.isServiceRunning = false
        self.currentStatus = .stopped
        self.activePortUrls.removeAll()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            procToStop?.terminationHandler = nil
            if let proc = procToStop, proc.isRunning {
                proc.terminate()
            }
            self?.killOrphanedProcesses()
        }
    }
    
    private func killOrphanedProcesses() {
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["devtunnel"]
        try? task.run()
    }
    
    public func isRunning() -> Bool {
        return isServiceRunning && (process?.isRunning ?? false)
    }
}
