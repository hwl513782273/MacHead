import Foundation
import CoreGraphics
import ApplicationServices

typealias CGSConfigureDisplayEnabledFunc = @convention(c) (
    OpaquePointer?, // CGDisplayConfigRef
    CGDirectDisplayID,
    Bool
) -> Int32

final class DisplayManager {
    static let shared = DisplayManager()

    private let setMode: CGSConfigureDisplayEnabledFunc?

    /// 内存中的内置屏 ID 缓存，避免每次查询都写 UserDefaults
    private var cachedBuiltInID: CGDirectDisplayID?

    private init() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY
        ) else {
            setMode = nil
            NSLog("MacHead: 无法加载 SkyLight 框架")
            return
        }

        let sym = dlsym(handle, "CGSConfigureDisplayEnabled")
        setMode = sym.map { unsafeBitCast($0, to: CGSConfigureDisplayEnabledFunc.self) }
        if setMode == nil {
            NSLog("MacHead: 无法在 SkyLight 中找到 CGSConfigureDisplayEnabled 符号")
        }
    }

    // MARK: - 显示器域查询原语

    /// 单次枚举当前在线显示器列表（CGGetOnlineDisplayList 的 count/fill 两段式调用）
    func onlineDisplayIDs() -> [CGDirectDisplayID]? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays
    }

    /// 检查是否为虚拟/软件显示屏（如系统在无物理显示器时创建的 unkn virt，或远程工具生成的虚拟屏）
    static func isVirtualDisplay(_ displayID: CGDirectDisplayID) -> Bool {
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        // 0x756e6b6e = "unkn", 0x76697274 = "virt"
        return vendor == 0x756e6b6e || model == 0x76697274 || vendor == 0xF0F0 || model == 0xF0F0
    }

    /// 获取当前或缓存的内置显示器 ID；返回 nil 表示既不在线也无缓存
    var builtInDisplayID: CGDirectDisplayID? {
        if let id = onlineDisplayIDs()?.first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            persistBuiltInID(id)
            return id
        }

        // Fallback to cached ID if display is already disabled and thus offline
        if let cached = cachedBuiltInID { return cached }
        let persisted = UserDefaults.standard.integer(forKey: "BuiltInDisplayID")
        if persisted != 0 {
            let id = CGDirectDisplayID(persisted)
            cachedBuiltInID = id
            return id
        }

        return nil
    }

    /// 检查内置显示器是否当前在线（通过系统在线显示器权威列表验证，在线时顺带刷新缓存）
    var isBuiltInOnline: Bool {
        guard let online = onlineDisplayIDs(),
              let id = online.first(where: { CGDisplayIsBuiltin($0) != 0 }) else { return false }
        persistBuiltInID(id)
        return true
    }

    private func persistBuiltInID(_ id: CGDirectDisplayID) {
        guard cachedBuiltInID != id else { return }
        cachedBuiltInID = id
        UserDefaults.standard.set(Int(id), forKey: "BuiltInDisplayID")
    }

    // MARK: - 内置屏断开/恢复

    /// 断开内置显示器（已离线时为幂等空操作）
    func disconnectBuiltIn() {
        guard let setMode = setMode else {
            NSLog("MacHead: CGSConfigureDisplayEnabled API 不可用")
            return
        }

        guard let id = onlineDisplayIDs()?.first(where: { CGDisplayIsBuiltin($0) != 0 }) else {
            NSLog("MacHead: 内置显示屏不在线，无需重复断开")
            return
        }
        persistBuiltInID(id)

        NSLog("MacHead: 正在断开内置显示屏 ID: %d", id)
        var configRef: CGDisplayConfigRef? = nil
        let beginErr = CGBeginDisplayConfiguration(&configRef)
        if beginErr == .success {
            let configureErr = setMode(configRef, id, false)
            let completeErr = CGCompleteDisplayConfiguration(configRef, .permanently)
            NSLog("MacHead: 断开内置屏结果 - 设定: %d, 提交: %d", configureErr, completeErr.rawValue)
        } else {
            NSLog("MacHead: CGBeginDisplayConfiguration 失败: %d", beginErr.rawValue)
        }
    }

    /// 重新连接内置显示器
    func reconnectBuiltIn(retriesRemaining: Int = 5) {
        // 如果内屏已在权威在线列表中，无需重复开启
        if let online = onlineDisplayIDs(),
           let id = online.first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            NSLog("MacHead: 内置显示屏 ID: %d 已处于在线状态", id)
            return
        }

        guard let setMode = setMode else {
            NSLog("MacHead: CGSConfigureDisplayEnabled API 不可用")
            return
        }

        // 内屏离线时使用缓存 ID；无缓存时按 Apple Silicon 惯例以 ID 1 兜底（仅此恢复路径需要猜测）
        let id: CGDirectDisplayID
        if let cached = builtInDisplayID {
            id = cached
        } else {
            NSLog("MacHead: 本地无内置屏缓存 ID，以默认 ID 1 兜底尝试恢复")
            id = CGDirectDisplayID(1)
        }

        NSLog("MacHead: 正在重新连接内置显示屏 ID: %d (剩余重试: %d)", id, retriesRemaining)
        var configRef: CGDisplayConfigRef? = nil
        let beginErr = CGBeginDisplayConfiguration(&configRef)
        if beginErr == .success {
            let configureErr = setMode(configRef, id, true)
            let completeErr = CGCompleteDisplayConfiguration(configRef, .permanently)
            NSLog("MacHead: 启用内置屏结果 - 设定: %d, 提交: %d", configureErr, completeErr.rawValue)
            if completeErr == .success { return }
            NSLog("MacHead: 提交启用显示配置未成功，将在 0.2 秒后重试...")
        } else {
            NSLog("MacHead: CGBeginDisplayConfiguration 失败: %d", beginErr.rawValue)
        }

        guard retriesRemaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.reconnectBuiltIn(retriesRemaining: retriesRemaining - 1)
        }
    }
}
