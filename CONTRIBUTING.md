# 贡献指南 / Contributing

感谢你愿意为 MacHead 出力!这个项目刻意保持小而美:纯 Swift、零第三方依赖、单 target。

## 开发环境

只需要 macOS 自带的 **Xcode Command Line Tools**(无需完整 Xcode):

```bash
xcode-select --install        # 如未安装
git clone https://github.com/ox01024/MacHead.git
cd MacHead
./build.sh --no-install       # 编译通用二进制,产物在当前目录 ./MacHead.app
./build.sh                    # 编译并安装到 /Applications(会覆盖已有版本并重启 App)
```

- 无 SwiftPM / CocoaPods 依赖,`Sources/*.swift` 直接由 `swiftc` 编译。
- 无需 Apple Developer 证书:构建使用 ad-hoc 签名。
- `Resources/` 下的第三方二进制(nezha-agent、frpc、cloudflared、serverstatus-client)**不在仓库内**,缺失时构建依然成功,仅相关可选功能不可用;正式发布由 GitHub Actions(`release.yml`)自动拉取合并。

## 项目结构

```
Sources/            # Swift 源代码(菜单栏 App、machead CLI、各功能模块)
Resources/          # Info.plist、图标、Web 面板页面
Scripts/            # 构建辅助脚本(图标生成等)
website/            # 官网 headlessmac.com(Vite + Cloudflare Pages)
docs/               # 深入文档(遥测 schema 等)
```

## 提交规范

- Commit message 使用约定式前缀:`feat:` / `fix:` / `docs:` / `chore:` / `refactor:` …,中英文均可。
- 一个 PR 只做一件事;功能分支命名 `feat/xxx`、`fix/xxx`。
- 涉及 UI 的改动请附截图;涉及权限(辅助功能/输入监听/sudoers)的改动请说明测试路径。

## Issue

- Bug 反馈请附 macOS 版本与机型、MacHead 版本(菜单栏 → 关于)、复现步骤。
- 功能建议请先描述**使用场景**,而不仅是实现方式。
- 安全问题请勿提公开 issue,走 [私密漏洞报告](https://github.com/ox01024/MacHead/security/advisories/new)(见 [SECURITY.md](SECURITY.md))。

## 行为准则

保持友善与对事不对人。维护者以业余时间处理反馈,响应慢请多包涵。

---

Issues and PRs in Chinese or English are both welcome.
