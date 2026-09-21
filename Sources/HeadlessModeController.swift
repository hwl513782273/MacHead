import Cocoa
import IOKit
import IOKit.pwr_mgt
import CoreGraphics

extension Notification.Name {
    static let headlessModeStateChanged = Notification.Name("com.waffle.MacHead.headlessModeStateChanged")
}

/// 全局/文件级的显示器重配置回调函数，符合 C 语言函数指针的调用约定
private func displayReconfigurationCallback(
    displayID: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo = userInfo else { return }
    let controller = Unmanaged<HeadlessModeController>.fromOpaque(userInfo).takeUnretainedValue()
    
    // 忽略配置起始阶段（kCGDisplayBeginConfigurationFlag）
    // 官方 CoreGraphics 规范明确指出：BeginConfiguration 仅代表事务开始，硬件拓扑与驱动状态处于未决中间态，
    // 不得在此期间调用显示配置修改接口；所有插拔、恢复与无头模式维持逻辑均在配置完成后（非 beginConfigurationFlag）统一处理。
    guard !flags.contains(.beginConfigurationFlag) else {
        return
    }
    
    guard controller.isDisplayMonitoringStarted else { return }

    let currentExternals = controller.currentExternalDisplays()
    let previousExternals = controller.activeExternalDisplays
    controller.activeExternalDisplays = currentExternals

    NSLog("MacHead: 显示配置变更完成。之前外接: %@, 当前外接: %@, 数量: %d, 无头模式: %d",
          previousExternals.description, currentExternals.description, currentExternals.count, controller.isHeadlessModeEnabled ? 1 : 0)

    // 所有外接显示器都已断开：按需安全恢复内屏
    if currentExternals.isEmpty {
        if controller.isHeadlessModeEnabled,
           UserDefaults.standard.bool(forKey: "AutoExitHeadlessOnDisconnect") {
            NSLog("MacHead: 检测到所有外接显示器已断开，直接退出无头模式！")
            DispatchQueue.main.async {
                controller.triggerSafeRecovery()
            }
        }
        return
    }

    // 无头模式下内屏被系统意外点亮（插拔/唤醒）：延迟片刻让系统稳定后重新切断
    if controller.isHeadlessModeEnabled {
        if controller.isBuiltInOnline() {
            NSLog("MacHead: 无头模式下检测到内屏处于在线状态，重新切断内屏以维持 Headless...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                controller.maintainBuiltInDisconnect()
            }
        }
        return
    }

    // 非无头模式：有新的外接显示器接入时，按需自动恢复 Headless
    let newDisplays = currentExternals.subtracting(previousExternals)
    guard !newDisplays.isEmpty,
          UserDefaults.standard.bool(forKey: "AutoRestoreHeadlessOnConnect") else { return }
    NSLog("MacHead: 检测到新外接显示器已接入: %@，自动恢复 Headless 模式...", newDisplays.description)
    DispatchQueue.main.async {
        controller.enableHeadlessMode()
    }
}

final class HeadlessModeController {
    static let shared = HeadlessModeController()
    
    private(set) var isHeadlessModeEnabled = false
    private var sleepAssertionID: IOPMAssertionID = 0
    private var activeAssertionType: String = ""
    private var isCallbackRegistered = false
    var isDisplayMonitoringStarted = false
    fileprivate(set) var activeExternalDisplays: Set<CGDirectDisplayID> = []
    
    // MARK: - Test Hooks
    /// 测试模式：动作函数只记录 was*Called 标志位，不触碰真实显示器/麦克风/电源断言/遥测
    var isTestMode = false
    var wasEnableHeadlessModeCalled = false
    var wasDisableHeadlessModeCalled = false
    var wasTriggerSafeRecoveryCalled = false
    var wasMaintainDisconnectCalled = false
    var mockExternalDisplays: Set<CGDirectDisplayID>? = nil
    /// nil = 读取真实在线状态；否则用该值替代（供测试模拟内屏被系统点亮）
    var mockBuiltInOnline: Bool? = nil
    
    private init() {}

    /// 内置屏是否在线（测试模式可被 mockBuiltInOnline 覆盖）
    func isBuiltInOnline() -> Bool {
        mockBuiltInOnline ?? DisplayManager.shared.isBuiltInOnline
    }

    /// 维持无头：仅当无头模式生效且仍有外接屏时，重新切断被系统意外点亮的内屏。
    /// 由显示器回调（0.3s 延迟）与 systemDidWake（0.5s 延迟）共用；0.3/0.5 秒的延迟
    /// 是有意留出的系统稳定窗口，因此这里重新读取实时外接屏状态而非用旧快照。
    func maintainBuiltInDisconnect() {
        guard isHeadlessModeEnabled, !currentExternalDisplays().isEmpty else { return }
        if isTestMode {
            wasMaintainDisconnectCalled = true
            return
        }
        DisplayManager.shared.disconnectBuiltIn()
    }

    func currentExternalDisplays() -> Set<CGDirectDisplayID> {
        if let mock = mockExternalDisplays {
            return mock
        }
        guard let online = DisplayManager.shared.onlineDisplayIDs() else { return [] }
        return Set(online.filter { CGDisplayIsBuiltin($0) == 0 && !DisplayManager.isVirtualDisplay($0) })
    }
    
    func enableHeadlessMode() {
        wasEnableHeadlessModeCalled = true
        guard !isHeadlessModeEnabled, !isTestMode else { return }
        isHeadlessModeEnabled = true
        UserDefaults.standard.set(true, forKey: "HeadlessModeEnabled")
        NSLog("MacHead: 正在启用无头模式...")
        
        // 1. 切断内屏
        DisplayManager.shared.disconnectBuiltIn()
        
        // 1.5. 自动静音内置麦克风
        MediaDeviceManager.shared.muteBuiltInMicrophone()
        
        // 2. 评估并获取电源断言状态
        evaluatePowerAssertion()
        
        // 4. 监听系统唤醒，确保唤醒后内屏仍被断开
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        
        NotificationCenter.default.post(name: .headlessModeStateChanged, object: nil)
        TelemetryManager.shared.track(event: "app_event", extraInfo: ["action": "enable_headless"])
    }
    
    func disableHeadlessMode() {
        wasDisableHeadlessModeCalled = true
        guard isHeadlessModeEnabled, !isTestMode else { return }
        isHeadlessModeEnabled = false
        UserDefaults.standard.set(false, forKey: "HeadlessModeEnabled")
        NSLog("MacHead: 正在关闭无头模式...")
        
        // 1. 重连内屏
        DisplayManager.shared.reconnectBuiltIn()
        
        // 1.5. 恢复内置麦克风的静音状态
        MediaDeviceManager.shared.unmuteBuiltInMicrophone()
        
        // 2. 释放所有电源断言
        updateSleepAssertion(enabled: false)
        
        // 4. 移除唤醒监听
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        
        NotificationCenter.default.post(name: .headlessModeStateChanged, object: nil)
        TelemetryManager.shared.track(event: "app_event", extraInfo: ["action": "disable_headless"])
    }
    
    /// 触发安全恢复，直接退出无头模式
    func triggerSafeRecovery() {
        wasTriggerSafeRecoveryCalled = true
        guard isHeadlessModeEnabled, !isTestMode else { return }
        NSLog("MacHead: 检测到外接屏断开，直接退出无头模式以恢复内屏")
        disableHeadlessMode()
    }
    
    /// 动态管理空闲与合盖睡眠断言
    func updateSleepAssertion(enabled: Bool) {
        let keepRunningOnLidClose = UserDefaults.standard.bool(forKey: "KeepRunningOnLidClose")
        let targetType = keepRunningOnLidClose ? (kIOPMAssertionTypePreventSystemSleep as String) : (kIOPMAssertionTypePreventUserIdleSystemSleep as String)
        
        if enabled {
            guard isHeadlessModeEnabled else { return }
            
            // 如果已有断言且类型不符，先释放
            if sleepAssertionID != 0 && activeAssertionType != targetType {
                IOPMAssertionRelease(sleepAssertionID)
                NSLog("MacHead: 释放旧类型电源断言，ID: %d", sleepAssertionID)
                sleepAssertionID = 0
                activeAssertionType = ""
            }
            
            if sleepAssertionID == 0 {
                let reason = "MacHead: Headless mode active" as CFString
                let result = IOPMAssertionCreateWithName(
                    targetType as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    reason,
                    &sleepAssertionID
                )
                if result != kIOReturnSuccess {
                    NSLog("MacHead: 无法创建电源断言 (%@) %d", targetType, result)
                } else {
                    NSLog("MacHead: 成功创建电源断言 (%@)，ID: %d", targetType, sleepAssertionID)
                    activeAssertionType = targetType
                }
            }
        } else {
            if sleepAssertionID != 0 {
                IOPMAssertionRelease(sleepAssertionID)
                NSLog("MacHead: 释放电源断言，ID: %d", sleepAssertionID)
                sleepAssertionID = 0
                activeAssertionType = ""
            }
        }
    }
    
    
    /// 重新评估电源断言状态
    func evaluatePowerAssertion() {
        guard isHeadlessModeEnabled else { return }
        
        let preventIdleSleep = UserDefaults.standard.bool(forKey: "PreventIdleSleep")
        let isBatteryLow = BatteryManager.shared.isBatteryProtectionActive
        
        // 只有在允许防止睡眠且电池不处于低电量保护状态时，才持有断言
        let shouldHoldAssertion = preventIdleSleep && !isBatteryLow
        updateSleepAssertion(enabled: shouldHoldAssertion)
    }
    
    // MARK: - 显示器变化守护
    
    func registerDisplayCallback() {
        guard !isCallbackRegistered else { return }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let result = CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, userInfo)
        if result == .success {
            isCallbackRegistered = true
            NSLog("MacHead: 成功注册显示器变化回调")
            // 延时 1 秒启动显示器插拔监测，避开 App 启动时的初始状态回调
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.activeExternalDisplays = self.currentExternalDisplays()
                self.isDisplayMonitoringStarted = true
                NSLog("MacHead: 显示器插拔监测已正式启动，当前外接显示器: %@", self.activeExternalDisplays.description)
            }
        } else {
            NSLog("MacHead: 注册显示器变化回调失败: %d", result.rawValue)
        }
    }
    
    
    @objc private func systemDidWake() {
        // 唤醒后系统可能重新枚举显示器，再次确保内屏断开
        guard isHeadlessModeEnabled else { return }
        NSLog("MacHead: 系统唤醒，检查并确保内置显示器断开...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.maintainBuiltInDisconnect()
        }
    }
    
    static func runTests() {
        print("Running HeadlessModeController Unit Tests...")
        let controller = HeadlessModeController.shared
        
        // 测试模式：动作只记录标志位，绝不触碰真实显示器/麦克风/遥测
        controller.isTestMode = true

        // Save current real state
        let originalIsHeadless = controller.isHeadlessModeEnabled
        let originalIsMonitoring = controller.isDisplayMonitoringStarted
        let originalActiveExternals = controller.activeExternalDisplays

        defer {
            // Restore original state
            controller.isHeadlessModeEnabled = originalIsHeadless
            controller.isDisplayMonitoringStarted = originalIsMonitoring
            controller.activeExternalDisplays = originalActiveExternals
            controller.mockExternalDisplays = nil
            controller.mockBuiltInOnline = nil
            controller.isTestMode = false
        }

        // Helper to reset hooks
        func resetHooks() {
            controller.wasEnableHeadlessModeCalled = false
            controller.wasDisableHeadlessModeCalled = false
            controller.wasTriggerSafeRecoveryCalled = false
            controller.wasMaintainDisconnectCalled = false
        }

        // 回调里的动作经 DispatchQueue.main.async 派发，而 CLI 进程没有常驻 runloop，
        // 必须排水主队列，被派发的动作才会真正执行、标志位才会被记录。
        // 注意：用 precondition 而非 assert —— assert 在 -O 下会被整体编译移除，测试将永远"假绿"。
        func drainMainQueue(seconds: Double = 0.05) {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
        }

        // 模拟一次"显示器配置变更完成"事件：重置钩子、设置 mock 状态并触发回调
        func fireChange(headless: Bool,
                        previous: Set<CGDirectDisplayID>,
                        current: Set<CGDirectDisplayID>,
                        builtInOnline: Bool = false,
                        displayID: CGDirectDisplayID = 101,
                        flags: CGDisplayChangeSummaryFlags = []) {
            resetHooks()
            controller.isHeadlessModeEnabled = headless
            controller.activeExternalDisplays = previous
            controller.mockExternalDisplays = current
            controller.mockBuiltInOnline = builtInOnline
            displayReconfigurationCallback(displayID: displayID, flags: flags,
                                           userInfo: Unmanaged.passUnretained(controller).toOpaque())
        }

        controller.isDisplayMonitoringStarted = true

        // Test 1: Manually turning off headless mode when an external display is connected.
        // We want to make sure AutoRestoreHeadlessOnConnect does NOT trigger.
        print("Test 1: Manually turning off headless mode when an external display is connected...")
        fireChange(headless: false, previous: [101], current: [101]) // external display remains connected
        drainMainQueue()

        precondition(!controller.wasEnableHeadlessModeCalled, "FAIL: Auto-restore was incorrectly triggered when manually disabling headless mode!")
        precondition(!controller.wasMaintainDisconnectCalled, "FAIL: Maintain-disconnect was incorrectly triggered when headless mode is off!")
        print("Test 1: PASS")

        // Test 2: Unplugging the last external display when headless mode is active.
        // We expect triggerSafeRecovery to be called.
        print("Test 2: Unplugging the last external display when headless mode is active...")
        // Make sure user defaults has AutoExitHeadlessOnDisconnect set to true for test consistency
        let originalAutoExit = UserDefaults.standard.bool(forKey: "AutoExitHeadlessOnDisconnect")
        UserDefaults.standard.set(true, forKey: "AutoExitHeadlessOnDisconnect")
        defer {
            UserDefaults.standard.set(originalAutoExit, forKey: "AutoExitHeadlessOnDisconnect")
        }

        fireChange(headless: true, previous: [101], current: []) // unplugged
        drainMainQueue()

        precondition(controller.wasTriggerSafeRecoveryCalled, "FAIL: Safe recovery was not triggered when all external displays were disconnected!")
        print("Test 2: PASS")

        // Test 3: Plugging in a new external display when headless mode is inactive.
        // We expect enableHeadlessMode to be called.
        print("Test 3: Plugging in a new external display when headless mode is inactive...")
        let originalAutoRestore = UserDefaults.standard.bool(forKey: "AutoRestoreHeadlessOnConnect")
        UserDefaults.standard.set(true, forKey: "AutoRestoreHeadlessOnConnect")
        defer {
            UserDefaults.standard.set(originalAutoRestore, forKey: "AutoRestoreHeadlessOnConnect")
        }

        fireChange(headless: false, previous: [], current: [101]) // plugged in
        drainMainQueue()

        precondition(controller.wasEnableHeadlessModeCalled, "FAIL: Headless mode was not auto-restored when new display connected!")
        print("Test 3: PASS")

        // Test 4: Plugging in a second external display when headless mode is active.
        // We expect no action.
        print("Test 4: Plugging in a second external display when headless mode is active...")
        fireChange(headless: true, previous: [101], current: [101, 102], builtInOnline: false) // 内屏本应离线
        drainMainQueue()

        precondition(!controller.wasEnableHeadlessModeCalled, "FAIL: Incorrect action when adding second external display in headless mode!")
        precondition(!controller.wasDisableHeadlessModeCalled, "FAIL: Headless mode disabled when adding second external display!")
        precondition(!controller.wasMaintainDisconnectCalled, "FAIL: Maintain-disconnect triggered when adding second external display!")
        print("Test 4: PASS")

        // Test 5: Built-in display begins configuration when no external displays are connected.
        // Protect built-in display from being mistakenly disconnected.
        print("Test 5: Built-in display begins configuration when no external displays are connected...")
        fireChange(headless: true, previous: [], current: [], displayID: 1, flags: [.beginConfigurationFlag])
        drainMainQueue()

        precondition(controller.isHeadlessModeEnabled, "FAIL: Headless mode should not be corrupted by beginConfigurationFlag!")
        precondition(!controller.wasMaintainDisconnectCalled, "FAIL: Maintain-disconnect triggered during beginConfigurationFlag!")
        print("Test 5: PASS")

        // Test 6: Headless mode is active, the system unexpectedly re-lit the built-in display,
        // and external displays are still connected. Expect the built-in to be re-disconnected.
        print("Test 6: Headless mode with built-in unexpectedly re-lit and externals present...")
        fireChange(headless: true, previous: [101], current: [101], builtInOnline: true) // 模拟系统把内屏点亮

        // 维持断开带有 0.3 秒延迟，需要更长的排水窗口
        drainMainQueue(seconds: 0.4)

        precondition(controller.wasMaintainDisconnectCalled, "FAIL: Built-in display was not re-disconnected while headless mode is active with externals present!")
        precondition(controller.isHeadlessModeEnabled, "FAIL: Maintain-disconnect should not turn off headless mode!")
        print("Test 6: PASS")

        print("All Tests Passed Successfully! 🎉")
    }
}
