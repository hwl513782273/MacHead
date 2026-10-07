# Privacy Policy / 隐私声明

**English** | [中文](#中文)

---

MacHead is a native macOS application developed by an independent developer. This page describes exactly what data the app and the website collect, why, and how to turn it off. MacHead contains **no third-party analytics SDK, no ads, and no trackers**.

## What we collect

**App telemetry** (anonymous usage statistics, sent to `https://headlessmac.com/api/telemetry`):

| Field | Example | Purpose |
|---|---|---|
| `event` | `app_heartbeat`, `app_event` | Distinguish event types |
| `anonymous_id` | `8F3A…-UUID` | Random UUID generated locally on first launch; **not** derived from any hardware identifier |
| `app_version` / `build_number` | `0.1.23` / `26` | Version adoption, crash correlation |
| `os_version` / `arch` | `Version 15.6 (Build…)` / `arm64` | Platform distribution |
| `is_headless`, `is_launch_at_login`, `is_web_dashboard_enabled`, `auth_accessibility` | `true/false` | Feature usage booleans |
| `uptime_seconds` | `86400` | System uptime in seconds |
| `country` | `US` | Injected automatically by Cloudflare Edge; no IP address is stored |

**Website analytics** (headlessmac.com): standard `page_view` / `click_download` events with `utm_*` and `referrer` for traffic-source attribution. No cookies, no fingerprinting.

## What we never collect

Hardware serial numbers, MAC addresses, hostname, file paths, window titles, keystrokes, account credentials, or any user content. IP addresses are not written to the database.

## Opting out

Preferences → General → turn off **「匿名使用统计 / Anonymous usage statistics」**. No further events are sent, immediately. Existing app behavior is unaffected.

## Data handling

Events are stored in a single Cloudflare D1 table used solely to answer "how many active installs, on which versions, using which features". Data is never sold, shared, or used for advertising. Aggregated numbers may be published (e.g. install counts).

---

# 中文

MacHead 是独立开发者维护的 macOS 原生应用。本页完整说明应用与官网收集的数据、用途与关闭方式。**不含任何第三方分析 SDK、广告与跟踪器**。

## 收集什么

**应用遥测**(匿名使用统计,发送至 `https://headlessmac.com/api/telemetry`):

| 字段 | 示例 | 用途 |
|---|---|---|
| `event` | `app_heartbeat`、`app_event` | 区分事件类型 |
| `anonymous_id` | `8F3A…-UUID` | 首次启动本地随机生成的 UUID,**与任何硬件标识无关** |
| `app_version` / `build_number` | `0.1.23` / `26` | 版本分布、故障关联 |
| `os_version` / `arch` | `Version 15.6` / `arm64` | 平台分布 |
| `is_headless`、`is_launch_at_login`、`is_web_dashboard_enabled`、`auth_accessibility` | `true/false` | 功能开关使用率 |
| `uptime_seconds` | `86400` | 系统已运行秒数 |
| `country` | `US` | Cloudflare 边缘自动注入的国家代码,**不存 IP** |

**官网统计**(headlessmac.com):标准 `page_view` / `click_download` 事件,带 `utm_*` 与 `referrer` 用于渠道归因。无 Cookie、无指纹。

## 永不收集

硬件序列号、MAC 地址、主机名、文件路径、窗口标题、按键内容、账号凭据及任何用户内容;IP 地址不写库。

## 如何关闭

偏好设置 → 常规设置 → 关闭「匿名使用统计」,**立即**不再发送任何事件,应用功能不受影响。

## 数据如何处理

事件仅存于一张 Cloudflare D1 表,只用于回答「有多少活跃安装、用什么版本、开哪些功能」;不出售、不共享、不用于广告;聚合数字(如安装量)可能公开发布。
