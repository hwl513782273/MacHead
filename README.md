# MacHead

<p align="center">
  <img src="Resources/logo.svg" width="128" height="128" alt="MacHead Logo" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013.0%2B-blue.svg" alt="Platform: macOS 13.0+" />
  <img src="https://img.shields.io/badge/arch-Apple%20Silicon%20%7C%20Intel-orange.svg" alt="Architecture: Apple Silicon | Intel" />
  <img src="https://img.shields.io/badge/language-Swift%205.7%2B-red.svg" alt="Language: Swift 5.7+" />
  <img src="https://img.shields.io/badge/license-Apache%202.0-green.svg" alt="License: Apache 2.0" />
</p>

**MacHead** 是一款轻量、零依赖的 macOS 开源原生实用工具。它专门用于将内屏损坏、或作为专用桌面服务器/软路由使用的 MacBook，重塑并转换为一台高效、稳定、安全的 **Headless（无头模式）工作站/服务器**（其表现类似于 Mac Studio 或 Mac mini）。

---

## 📖 相关文档

* **[产品设计与需求规范 (PRD)](docs/PRD.md)**：包含开发历程与底层系统 API 的分析设计。
* **[功能演练与技术概览 (Walkthrough)](docs/walkthrough.md)**：包含详细的私有 API 原理、键盘时序差值拦截机制和端口调试等技术细节。

---

## 🌟 核心特性

- 🖥️ **无头工作站模式 (Headless Mode)**：利用 macOS `SkyLight.framework` 私有 API 逻辑层切断内置显示器信号。支持合盖运行，避免内屏玻璃长亮发热损害排线。
- ⚙️ **偏好设置面板 (GUI)**：基于 SwiftUI 编写的高清偏好设置交互窗口，提供实时外接显示器列表与电量传感器显示。
- ⌨️ **内置输入设备物理屏蔽 (Anti-Accidental Input)**：
  - **内置触控板**：检测到外接鼠标连接或进入无头模式时，自动独占（Seize）并完全锁死内置触控板。
  - **内置键盘**：独创**“时序差值拦截算法”**，结合底层 `IOHIDManager` 硬件中断时间戳与 `CGEventTap` 全局钩子。在无头模式激活时屏蔽笔记本自带键盘的误触，同时保证外接键盘百分之百正常打字。
- 🔇 **隐私麦克风自动静音**：在进入无头模式时自动将系统默认的麦克风输入置为物理静音，防范窃听风险，退出时自动还原原始音量状态。
- 🔋 **智能低电量电池保护**：实时监听 `IOPowerSources` 传感器通知。当外接电源意外断电且电池电量低于安全阈值（例如 20%）时，自动解除防睡眠断言并允许系统进入物理深度休眠，防止电池深度放电损耗。
- 🔌 **开机自动启动 (Launch at Login)**：使用 macOS 新版 `SMAppService` 守护服务，无需常驻守护后台也能在登录系统时安全自启。
- 💻 **命令行客户端 (CLI)**：支持终端或 SSH 远程控制操作（`--enable` / `--disable` / `--status`），通过 DistributedNotificationCenter 与主程序进程低延迟 IPC 通信。
- 📊 **远程 Web 控制面板 (Web Dashboard)**：内置无第三方框架依赖的 `NWListener` HTTP 高性能服务器，提供精致毛玻璃质感的实时系统 CPU/RAM 监控仪表盘、功能状态开关。
- 🔒 **Web 安全 Basic 鉴权**：在首次启动时自动随机生成高强度管理密码（可通过偏好设置面板修改），强制执行 HTTP Basic 认证，防止内网恶意劫持或远程越权控制。
- ↔️ **内网穿透套件**：内置 **Cloudflare Tunnel**、**Microsoft Dev Tunnels** 与 **FRP** 三套穿透方案的统一管理界面，将本机 SSH/Web 服务安全暴露到公网，随时随地远程接管设备。穿透组件不随安装包捆绑，构建期自动拉取开源组件，专有组件由用户一键自装。
- 📡 **监控与告警集成**：原生接入 **哪吒监控**、**ServerStatus** 探针与 **Uptime Kuma** 心跳推送，配合 SMC 温度告警（Bark/Telegram 通知），打造无人值守的托管节点。
- 🧹 **干净卸载**：所有集成组件默认留在应用沙盒目录内，支持应用内一键卸载——停止服务、移除软链接、清理配置并将应用移入废纸篓，不向系统残留任何文件。

---

## 🚀 快速安装与构建

### 1. 下载 DMG 镜像安装（推荐）

您可以直接前往 [GitHub Releases](https://github.com/ox01024/MacHead/releases) 页面，下载最新发布的带有 CPU 架构后缀的 `MacHead-v0.1.0-macos-universal.dmg`。双击打开并直接拖拽应用到应用程序文件夹即可完成安装。

### 2. 本地命令行手动编译

项目具备极简的“零包管理器依赖”设计，只需 macOS 系统自带的 Swift 命令行工具包（Command Line Tools）即可原地编译并自动打包部署：

```bash
# 1. 克隆代码库
git clone https://github.com/ox01024/MacHead.git
cd MacHead

# 2. 运行构建部署脚本（将自动清空旧版本并重新编译安装到 /Applications）
./build.sh
```

---

## ⚙️ 使用说明

### 1. GUI 交互
- 启动应用后，状态栏右上角将出现  菜单项图标。
- 点击图标，选择 **“偏好设置...”** 即可打开配置窗口，自由开关各项辅助管理属性并配置远程管理密码。

### 2. CLI 命令行控制
主可执行文件同时作为 CLI 客户端工作。您可以将其配置到系统的 `$PATH` 中或直接调用：

```bash
# 查询当前无头模式运行状态 (返回值包括 headless / normal / offline)
/Applications/MacHead.app/Contents/MacOS/MacHead --status

# 强制开启 Headless 模式（切断内屏、开启防睡眠断言）
/Applications/MacHead.app/Contents/MacOS/MacHead --enable

# 恢复 Normal 模式（唤醒内屏、释放防睡眠断言）
/Applications/MacHead.app/Contents/MacOS/MacHead --disable

# 查看帮助
/Applications/MacHead.app/Contents/MacOS/MacHead --help
```

### 3. 远程 Web 控制面板
- 在偏好设置中勾选 **“开启远程 Web 控制面板”**。
- 输入面板中显示的本机局域网 IP（例如 `http://192.168.1.100:8080`）。
- 浏览器访问时会弹出密码框，用户名输入 `admin`，密码输入您在偏好设置中配置（或系统初次启动随机生成）的管理密码即可进入动态毛玻璃仪表盘。

---

## 🔒 权限设置说明

由于本软件涉及底层硬件输入信号的主动屏蔽，macOS 安全沙盒机制要求用户在系统设置中完成授权：

1. **辅助功能权限 (Accessibility)**：
   - 目的：用于启用 Quartz Event Tap 拦截并丢弃内置键盘的物理按键输入。
   - 设置：若该功能生效，偏好设置面板将显示警告。点击“去系统设置开启”，在“系统设置 -> 隐私与安全性 -> 辅助功能”中允许 **MacHead**。
2. **输入监听权限 (Input Monitoring)**：
   - 目的：用于通过 `IOHIDDeviceOpen` 对内置触控板进行独占并屏蔽。
   - 设置：在“系统设置 -> 隐私与安全性 -> 输入监听”中允许 **MacHead**。

---

## 📂 项目结构

```
MacHead/
├── .github/workflows/            # CI/CD：release.yml（发布流水线）/ deploy.yml（官网部署）
├── README.md                     # 项目使用说明
├── LICENSE                       # Apache License 2.0
├── NOTICE                        # 第三方组件许可声明
├── build.sh                      # 本地自动化一键编译与部署脚本
├── docs/                         # 项目文档归档
│   ├── PRD.md                    # 底层设计与系统 API 选型分析
│   └── walkthrough.md            # 时序防误触拦截原理与功能演练总结
├── Sources/                      # Swift 源代码
│   ├── main.swift                # CLI 参数解析与 GUI 统一入口
│   ├── AppDelegate.swift         # 菜单栏常驻/通知 IPC 与默认设置配置
│   ├── PreferencesView.swift     # SwiftUI 偏好设置管理界面
│   ├── DisplayManager.swift      # SkyLight 驱动封装
│   ├── HeadlessModeController.swift # 无头模式状态 assertion 管理
│   ├── InputDeviceManager.swift  # 触控板 Seize 及键盘 EventTap 时序拦截器
│   ├── BatteryManager.swift      # IOPowerSources 电池感知
│   ├── MediaDeviceManager.swift  # CoreAudio 硬件音量隐私管理器
│   ├── WebServer.swift           # NWListener 自建 Web 鉴权服务器
│   ├── IntegrationManager.swift  # 集成服务生命周期总管
│   ├── CloudflareService.swift   # Cloudflare Tunnel 穿透
│   ├── DevTunnelService.swift    # Microsoft Dev Tunnels 穿透（含一键安装）
│   ├── FrpService.swift          # FRP 穿透
│   ├── NezhaAgentService.swift   # 哪吒监控探针
│   ├── ServerStatusService.swift # ServerStatus 探针
│   ├── UptimeKumaService.swift   # Uptime Kuma 心跳推送
│   ├── NotificationService.swift # Bark/Telegram 告警通知
│   ├── UninstallService.swift    # 应用内彻底卸载清理
│   └── TelemetryManager.swift    # 匿名使用统计（可关闭）
├── website/                      # 官网 (headlessmac.com)：Vite + Cloudflare Pages
├── Resources/                    # 原生应用资源
└── Scripts/                      # 构建开发脚本
```

---

## 🔐 隐私与遥测

MacHead 尊重用户隐私：

- **遥测完全匿名**：仅收集随机生成的本地 UUID、系统/应用版本、CPU 架构与功能开关状态（布尔值），**不含**任何硬件序列号、网络地址、账号凭据或使用内容。
- **一键退出**：偏好设置 → 常规设置 → 「匿名使用统计」，关闭即不再发送任何数据。
- **零第三方 SDK**：遥测为自建轻量 HTTP 上报，无任何广告/分析 SDK。

---

## 📄 开源协议

本项目源代码采用 **Apache License 2.0** 许可协议，详情请参阅 [LICENSE](LICENSE)。

- **客户端完全开源**：本仓库包含 macOS 客户端的全部源代码。
- **第三方组件**：构建期拉取的 frp、nezha-agent、cloudflared 等开源组件归属其原作者，许可信息见 [NOTICE](NOTICE)；Microsoft Dev Tunnels CLI 为专有组件，不分发、不捆绑，由用户按微软条款自行安装。
- **服务端组件**：内网穿透中继、计费等 SaaS 服务端代码不在本仓库开源范围内。
