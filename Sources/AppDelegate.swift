import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover?
    private let controller = HeadlessModeController.shared
    private var preferencesWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as an accessory (menu-bar only) app
        NSApp.setActivationPolicy(.accessory)
        
        // Register default preferences
        UserDefaults.standard.register(defaults: [
            "PreventIdleSleep": true,
            "KeepRunningOnLidClose": false,
            "AutoEnableHeadlessOnLaunch": false,
            "DisableTrackpadWhenExternalMouseConnected": false,
            "DisableKeyboardInHeadless": false,
            "DisableKeyboardWhenExternalKeyboardConnected": false,
            "DisableTrackpadInHeadless": false,
            "EnableBatteryProtection": true,
            "BatteryThreshold": 20,
            "MuteMicrophoneInHeadlessMode": false,
            "EnableWebServer": false,
            "DisableKeyboardAndTrackpadInHeadlessMode": false,
            "AutoExitHeadlessOnDisconnect": true,
            "AutoRestoreHeadlessOnConnect": true,
            "nezhaEnabled": false,
            "nezhaServer": "",
            "nezhaSecret": "",
            "nezhaTls": false,
            "serverStatusEnabled": false,
            "serverStatusAddr": "",
            "serverStatusUser": "",
            "serverStatusPassword": "",
            "kumaEnabled": false,
            "kumaPushUrl": "",
            "kumaInterval": 60.0,
            "frpEnabled": false,
            "frpMode": "quick",
            "frpServerAddr": "",
            "frpServerPort": "7000",
            "frpToken": "",
            "frpProxyName": "machead-ssh",
            "frpProxyType": "tcp",
            "frpLocalIP": "127.0.0.1",
            "frpLocalPort": "22",
            "frpRemotePort": "6022",
            "frpCustomDomains": "",
            "frpSubdomain": "",
            "frpCustomConfig": "# frpc.toml\nserverAddr = \"127.0.0.1\"\nserverPort = 7000\nauth.token = \"\"\n\n[[proxies]]\nname = \"machead-ssh\"\ntype = \"tcp\"\nlocalIP = \"127.0.0.1\"\nlocalPort = 22\nremotePort = 6022\n",
            "notificationsEnabled": false,
            "barkEnabled": false,
            "barkKey": "",
            "telegramEnabled": false,
            "telegramBotToken": "",
            "telegramChatId": "",
            "overheatAlertEnabled": false,
            "overheatThreshold": 85.0,
            "telemetryEnabled": true
        ])
        
        // Generate random default WebServerPassword if not present
        if UserDefaults.standard.string(forKey: "WebServerPassword") == nil ||
           UserDefaults.standard.string(forKey: "WebServerPassword")?.isEmpty == true {
            let randomPass = "MH-" + String((0..<4).map { _ in "0123456789ABCDEF".randomElement()! })
            UserDefaults.standard.set(randomPass, forKey: "WebServerPassword")
        }
        
        // Start monitoring input devices
        InputDeviceManager.shared.start()
        
        // Start monitoring battery/power status
        BatteryManager.shared.start()
        
        // Start Web Server if enabled in preferences
        WebServer.shared.start()
        
        // Start monitoring display plug/unplug events globally
        controller.registerDisplayCallback()
        
        // Start all active integrations (Nezha, ServerStatus, Uptime Kuma, SMC)
        IntegrationManager.shared.startAllServices()
        
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateIcon()
        
        // Observe headless mode state changes (such as auto-restoration)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStateChanged),
            name: .headlessModeStateChanged,
            object: nil
        )
        // Observe Distributed Notifications from CLI Client
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleCLIEngage),
            name: NSNotification.Name("com.waffle.MacHead.CLI.enable"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleCLIDisengage),
            name: NSNotification.Name("com.waffle.MacHead.CLI.disable"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        
        // CLI 软链接为 opt-in 组件：仅在偏好设置中开启后维护，默认零包外写入；
        // 异步执行，提权弹窗不得阻塞启动流程
        DispatchQueue.main.async { CLIToolInstaller.setupIfEnabled() }
        
        // Auto-reconnect if headless mode was previously enabled and autoEnableOnLaunch is true
        let autoEnable = UserDefaults.standard.bool(forKey: "AutoEnableHeadlessOnLaunch")
        let previouslyEnabled = UserDefaults.standard.bool(forKey: "HeadlessModeEnabled")
        if autoEnable && previouslyEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.controller.enableHeadlessMode()
                self.updateIcon()
            }
        }
        
        // Silent background check for updates 3 seconds after launch & send telemetry heartbeat
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            UpdateManager.shared.checkForUpdates(silent: true)
            TelemetryManager.shared.track(event: "app_heartbeat")
        }
    }
    
    private func updateIcon() {
        let autoEnable = UserDefaults.standard.bool(forKey: "AutoEnableHeadlessOnLaunch")
        let previouslyEnabled = UserDefaults.standard.bool(forKey: "HeadlessModeEnabled")
        let isHeadless = controller.isHeadlessModeEnabled || (autoEnable && previouslyEnabled)
        
        let imageName = isHeadless ? "macmini" : "laptopcomputer"
        if let image = NSImage(systemSymbolName: imageName, accessibilityDescription: "MacHead") {
            image.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.title = ""
        } else {
            statusItem.button?.image = nil
            statusItem.button?.title = isHeadless ? "●" : "○"
        }
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }
    
    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if let popover = popover, popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(sender)
        }
    }
    
    private func showPopover(_ sender: NSStatusBarButton) {
        if popover == nil {
            let popoverInstance = NSPopover()
            popoverInstance.behavior = .transient
            popoverInstance.animates = true
            self.popover = popoverInstance
        }
        
        let popoverView = StatusPopoverView(
            onOpenPreferences: { [weak self] in
                self?.popover?.performClose(nil)
                self?.openPreferences()
            },
            onQuitApp: { [weak self] in
                self?.popover?.performClose(nil)
                self?.quitApp()
            }
        )
        
        popover?.contentViewController = NSHostingController(rootView: popoverView)
        popover?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover?.contentViewController?.view.window?.makeKey()
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        let toggleItem = NSMenuItem(
            title: controller.isHeadlessModeEnabled ? "恢复内置屏显示" : "开启 Headless 模式",
            action: #selector(toggleHeadlessModeMenuAction),
            keyEquivalent: "h"
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let preferencesItem = NSMenuItem(
            title: "偏好设置...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)
        
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "退出 MacHead",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    
    @objc private func toggleHeadlessModeMenuAction() {
        if controller.isHeadlessModeEnabled {
            controller.disableHeadlessMode()
        } else {
            controller.enableHeadlessMode()
        }
    }

    @objc func openPreferences() {
        if preferencesWindow == nil {
            let view = PreferencesView()
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "MacHead 偏好设置"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .clear
            window.contentViewController = controller
            window.center()
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("MacHeadPreferencesWindow")
            self.preferencesWindow = window
        }
        
        // Bring window to front
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
    
    @objc private func handleStateChanged() {
        updateIcon()
        InputDeviceManager.shared.evaluateTrackpadAndKeyboardState()
    }
    
    
    @objc private func handleCLIEngage() {
        NSLog("MacHead: 收到来自 CLI 的启用命令，正在启用 Headless 模式...")
        if !controller.isHeadlessModeEnabled {
            controller.enableHeadlessMode()
        }
    }
    
    @objc private func handleCLIDisengage() {
        NSLog("MacHead: 收到来自 CLI 的禁用命令，正在关闭 Headless 模式...")
        if controller.isHeadlessModeEnabled {
            controller.disableHeadlessMode()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        IntegrationManager.shared.stopAllServices()
        WebServer.shared.stop()
        if controller.isHeadlessModeEnabled {
            controller.disableHeadlessMode()
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
