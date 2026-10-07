import Foundation
import ServiceManagement

/// 开机自启管理：macOS 13+ 使用 SMAppService，macOS 12 回落到传统 LaunchAgents plist。
final class LaunchAtLoginHelper {
    static let shared = LaunchAtLoginHelper()

    private init() {}

    private static let legacyAgentLabel = "com.waffle.MacHead"

    private var legacyPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.legacyAgentLabel).plist")
    }

    var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                migrateLegacyAgentIfNeeded()
                return SMAppService.mainApp.status == .enabled
            } else {
                return FileManager.default.fileExists(atPath: legacyPlistURL.path)
            }
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        if SMAppService.mainApp.status == .enabled {
                            return
                        }
                        try SMAppService.mainApp.register()
                        NSLog("MacHead: 成功开启开机自启")
                    } else {
                        if SMAppService.mainApp.status != .enabled {
                            return
                        }
                        try SMAppService.mainApp.unregister()
                        NSLog("MacHead: 成功关闭开机自启")
                    }
                } catch {
                    NSLog("MacHead: 设置开机自启状态失败: %@", error.localizedDescription)
                }
            } else {
                if newValue {
                    enableLegacyAgent()
                } else {
                    disableLegacyAgent()
                }
            }
        }
    }

    // MARK: - macOS 12 回落方案

    /// 写入 LaunchAgents plist，登录时由 launchd 拉起本应用。
    /// 仅落盘、不立即 launchctl load，避免应用已运行时被二次拉起，下次登录自然生效。
    private func enableLegacyAgent() {
        guard let executablePath = Bundle.main.executableURL?.path else {
            NSLog("MacHead: 开启开机自启失败，无法获取应用可执行文件路径")
            return
        }
        do {
            let agentsDir = legacyPlistURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "Label": Self.legacyAgentLabel,
                "ProgramArguments": [executablePath],
                "RunAtLoad": true,
                "LaunchOnlyOnce": true,
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: legacyPlistURL)
            NSLog("MacHead: 成功开启开机自启(LaunchAgent)")
        } catch {
            NSLog("MacHead: 写入 LaunchAgent plist 失败: %@", error.localizedDescription)
        }
    }

    /// 移除 plist 即可关闭登录拉起。
    /// 不调用 launchctl bootout：应用本身可能正由该 Agent 拉起，bootout 会杀死正在运行的自己；
    /// LaunchOnlyOnce 保证 launchd 不会重启任务，当前会话残留的空闲任务记录在注销后消失。
    private func disableLegacyAgent() {
        do {
            try FileManager.default.removeItem(at: legacyPlistURL)
            NSLog("MacHead: 成功关闭开机自启(LaunchAgent)")
        } catch {
            NSLog("MacHead: 移除 LaunchAgent plist 失败: %@", error.localizedDescription)
        }
    }

    // MARK: - 旧方案迁移

    private static var didAttemptLegacyMigration = false

    /// 用户从 macOS 12 升级到 13+ 后，把旧 LaunchAgent 迁移到 SMAppService。
    @available(macOS 13.0, *)
    private func migrateLegacyAgentIfNeeded() {
        guard !Self.didAttemptLegacyMigration else { return }
        Self.didAttemptLegacyMigration = true
        guard FileManager.default.fileExists(atPath: legacyPlistURL.path) else { return }
        do {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
            try FileManager.default.removeItem(at: legacyPlistURL)
            NSLog("MacHead: 开机自启已从 LaunchAgent 迁移至 SMAppService")
        } catch {
            NSLog("MacHead: 开机自启迁移失败，保留原 LaunchAgent: %@", error.localizedDescription)
        }
    }
}
