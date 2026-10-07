# Security Policy / 安全披露

**English** | [中文](#中文)

## Reporting a vulnerability / 漏洞上报

**Please do not open a public issue for security problems.** Instead, use GitHub's private vulnerability reporting:

👉 [github.com/ox01024/MacHead/security/advisories/new](https://github.com/ox01024/MacHead/security/advisories/new)

Please include: affected version (menu bar → About), macOS version, reproduction steps, and impact assessment. Reports are handled by the maintainer directly.

MacHead runs with elevated relevance on a user's machine — accessibility permissions, input interception, sudoers rules for battery control, and LAN/remote-tunnel exposure are all in scope and appreciated.

## Scope notes

- The relay/billing server side (tunnel orchestration) is **not** part of this open-source repository; reports about the `headlessmac.com` web service are still welcome via the same channel.
- The bundled third-party binaries (frp, nezha-agent, cloudflared) should be reported upstream; bundled-version issues can be reported here.

---

# 中文

## 漏洞上报

**安全问题请不要直接提公开 issue**(避免 0day 曝光)。请使用 GitHub 私密漏洞报告:

👉 [github.com/ox01024/MacHead/security/advisories/new](https://github.com/ox01024/MacHead/security/advisories/new)

请附上:受影响版本(菜单栏 → 关于)、macOS 版本、复现步骤与影响评估,由维护者直接处理。

MacHead 在用户机器上具有较高权限——辅助功能、输入拦截、电池控制的 sudoers 规则、局域网/远程隧道暴露面,均在欢迎范围内。
