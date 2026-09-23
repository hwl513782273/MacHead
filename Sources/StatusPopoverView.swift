import SwiftUI
import AppKit

struct StatusPopoverView: View {
    @ObservedObject private var battery = BatteryManager.shared
    @ObservedObject private var smc = SMCManager.shared
    @State private var isHeadless = HeadlessModeController.shared.isHeadlessModeEnabled
    @State private var externalDisplaysCount = HeadlessModeController.shared.currentExternalDisplays().count
    @State private var webServerIP = WebServer.shared.getLocalIPAddress()
    @State private var copiedServerInfo = false
    
    var onOpenPreferences: () -> Void
    var onQuitApp: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // MARK: - Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: isHeadless ? "macmini.fill" : "laptopcomputer")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isHeadless ? .purple : .green)
                    
                    Text("MacHead")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(isHeadless ? Color.purple : Color.green)
                        .frame(width: 8, height: 8)
                    Text(isHeadless ? "无头模式" : "正常运行")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isHeadless ? Color.purple.opacity(0.15) : Color.green.opacity(0.15))
                )
            }
            
            // MARK: - Hero Mode Toggle Button
            Button(action: {
                if isHeadless {
                    HeadlessModeController.shared.disableHeadlessMode()
                } else {
                    HeadlessModeController.shared.enableHeadlessMode()
                }
                isHeadless = HeadlessModeController.shared.isHeadlessModeEnabled
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: isHeadless ? "sun.max.fill" : "moon.stars.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isHeadless ? "恢复内置屏幕显示" : "开启 Headless 无头模式")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(isHeadless ? "内屏已断开 · 再次点击即可恢复" : "安全断开内屏 · 降温省电挂机")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isHeadless ? [Color.green, Color.teal] : [Color.purple, Color.indigo],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .shadow(color: (isHeadless ? Color.green : Color.purple).opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(PlainButtonStyle())
            
            // MARK: - Metrics Cards Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                // Card 1: 屏幕与外设
                MetricTileView(
                    icon: "display",
                    iconColor: .blue,
                    title: "显示器",
                    value: isHeadless ? "内屏已熄灭" : "内屏亮起",
                    subtitle: externalDisplaysCount > 0 ? "外接屏: \(externalDisplaysCount) 台" : "未接入外设屏"
                )
                
                // Card 2: 电池与电源状态
                MetricTileView(
                    icon: powerTileIcon,
                    iconColor: powerTileColor,
                    title: battery.isUPSActive ? "UPS 供电中" : "电源状态",
                    value: "\(battery.currentCapacity)%",
                    subtitle: powerTileSubtitle
                )

                // Card 3: CPU 与热度
                MetricTileView(
                    icon: "thermometer.medium",
                    iconColor: smc.currentTemperature > 75 ? .red : .teal,
                    title: "CPU 温度",
                    value: smc.currentTemperature > 0 ? String(format: "%.1f °C", smc.currentTemperature) : "-- °C",
                    subtitle: smc.fanSpeed > 0 ? "风扇: \(smc.fanSpeed) RPM" : "静音被动散热"
                )

                // Card 4: 电池健康/寿命
                MetricTileView(
                    icon: battery.powerWatts > 0 ? "bolt.fill" : "heart.fill",
                    iconColor: battery.isUPSActive ? .orange : (battery.batteryHealth >= 80 ? .green : .orange),
                    title: battery.powerWatts > 0 ? "即时功耗" : "电池健康度",
                    value: battery.powerWatts > 0 ? String(format: "%.1f W", battery.powerWatts) : (battery.batteryHealth > 0 ? String(format: "%.0f%%", battery.batteryHealth) : "正常"),
                    subtitle: battery.powerWatts > 0 ? "健康: \(Int(battery.batteryHealth))% · \(battery.cycleCount)次" : batteryHealthSubtitle
                )
            }
            
            // MARK: - Web Server & Quick Access Banner
            if UserDefaults.standard.bool(forKey: "EnableWebServer") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.blue)
                            Text("Web 控制台与 API")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        Text(verbatim: "http://\(webServerIP):\(WebServer.shared.portString)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: {
                        let urlStr = "http://\(webServerIP):\(WebServer.shared.portString)"
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(urlStr, forType: .string)
                        copiedServerInfo = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            copiedServerInfo = false
                        }
                    }) {
                        Text(copiedServerInfo ? "已复制" : "复制链接")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }
            
            Divider()
            
            // MARK: - Footer Actions
            HStack {
                Button(action: onOpenPreferences) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape.fill")
                        Text("偏好设置...")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()

                Button(action: onQuitApp) {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                        Text("退出")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(14)
        .frame(width: 330)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.15), value: isHeadless)
        .onAppear {
            self.webServerIP = WebServer.shared.getLocalIPAddress()
        }
        .onReceive(NotificationCenter.default.publisher(for: .headlessModeStateChanged)) { _ in
            self.isHeadless = HeadlessModeController.shared.isHeadlessModeEnabled
            self.externalDisplaysCount = HeadlessModeController.shared.currentExternalDisplays().count
            self.webServerIP = WebServer.shared.getLocalIPAddress()
        }
        .onReceive(NotificationCenter.default.publisher(for: .webServerStateChanged)) { _ in
            self.webServerIP = WebServer.shared.getLocalIPAddress()
        }
    }

    // MARK: - Computed Properties for Metrics Cards
    private var powerTileIcon: String {
        if battery.isCharging { return "bolt.batteryblock.fill" }
        if battery.isUPSActive { return "bolt.slash.fill" }
        if battery.isChargeLimitEnabled { return "checkmark.shield.fill" }
        return "battery.100"
    }

    private var powerTileColor: Color {
        if battery.isCharging { return .green }
        if battery.isUPSActive { return .orange }
        if battery.isChargeLimitEnabled { return .green }
        return .blue
    }

    private var powerTileSubtitle: String {
        if battery.isUPSActive {
            let time = battery.timeRemainingFormatted.isEmpty ? "测算中" : battery.timeRemainingFormatted
            return "🔋 UPS (\(time))"
        }
        let adapterStr = battery.adapterWatts > 0 ? "\(battery.adapterWatts)W" : "AC"
        if battery.isCharging {
            return "⚡️ 充电中 (\(adapterStr))"
        }
        if battery.isChargeLimitEnabled {
            return "⚡️ AC 直供 (\(battery.chargeLimitPercent)% 限充)"
        }
        return "⚡️ AC 直供 (\(adapterStr))"
    }

    private var batteryHealthSubtitle: String {
        let tempStr = battery.batteryTemperature > 0 ? String(format: "%.1f°C", battery.batteryTemperature) : "良好"
        return "循环 \(battery.cycleCount) 次 · \(tempStr)"
    }
}

struct MetricTileView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(iconColor)
                
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
