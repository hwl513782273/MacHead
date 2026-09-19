import Foundation
import AppKit

/// 应用内彻底卸载流程：停止服务 → 清理所有集成组件 → 移除应用本体
/// 用例：用户删除 App 时，确保捆绑/下载的第三方工具与配置不残留系统。
final class UninstallService {
    static let shared = UninstallService()

    /// 标记当前是否处于卸载流程，供 applicationWillTerminate 在最后清除偏好设置域
    private(set) var isUninstalling = false

    private init() {}

    /// 卸载确认与执行入口（需在主线程调用）
    func runUninstallFlow() {
        let alert = NSAlert()
        alert.messageText = "卸载 MacHead 并清理所有组件？"
        alert.informativeText = """
        将执行以下清理操作：
        • 停止所有穿透与监控服务 (frpc / 哪吒 / ServerStatus / Cloudflare Tunnel / Dev Tunnels)
        • 移除命令行工具 /usr/local/bin/machead
        • 注销 devtunnel 登录凭据，并删除其已安装的 CLI
        • 注销开机自启，清除全部配置与偏好设置

        完成后 MacHead 本体将被移入废纸篓。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "卸载并清理")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isUninstalling = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performCleanup()
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    /// 执行全部清理步骤（后台线程调用）
    private func performCleanup() {
        // 1. 停止所有集成服务，终止 frpc/nezha/cloudflared/devtunnel 等子进程，防止孤儿进程
        IntegrationManager.shared.stopAllServices()
        WebServer.shared.stop()

        // 2. 注销 devtunnel 登录凭据（清除 Keychain 中的微软/GitHub 授权，best-effort）
        DevTunnelService.shared.logout()

        // 3. 注销开机自启注册（best-effort）
        LaunchAtLoginHelper.shared.isEnabled = false

        // 4. 移除命令行工具软链接 (无权限时后台线程同步到主线程弹授权框)
        CLIToolInstaller.remove()

        // 5. 删除应用支持目录（含应用内一键安装的 devtunnel CLI）；根目录统一由 DevTunnelService 定义
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: DevTunnelService.userInstallRoot))

        // 6. 将应用本体移入废纸篓；等待回收完成（带超时兜底），偏好设置域在 applicationWillTerminate 的最后一步清除
        let semaphore = DispatchSemaphore(value: 0)
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
            // 移入废纸篓的结果不影响退出，失败时用户可手动删除
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
    }
}
