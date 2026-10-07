---
name: release-guide
description: Step-by-step guide for releasing new versions of MacHead via GitHub Actions (push an annotated vX tag; CI builds, uploads DMG to R2, updates appcast, creates GitHub Release, deploys website).
---
# MacHead 版本发布指南

本技能规定 MacHead 的标准发版流程。**规范流程是 GitHub Actions 自动发版**(`.github/workflows/release.yml`):推送 `v*` 附注标签即触发,云端完成构建、DMG、R2、appcast、GitHub Release 与官网部署全流程。本地发布脚本 `Scripts/release-local.sh` 已于 2026-10 删除,不再使用。

## 0. 前置条件

- 工作区干净、在 `main` 分支,所有待发布提交已推送
- GitHub Actions 可用(仓库 Settings → Actions 未被禁用)
- 仓库 Secrets 已配置:`CLOUDFLARE_API_TOKEN`、`CLOUDFLARE_ACCOUNT_ID`(R2 桶 `headlessmac-releases` 写权限)

## 1. 触发发布

```bash
# 附注标签,tag message 即用户可读的发布说明(会写入 appcast.json 的 releaseNotes)
git tag -a v0.1.24 -m "1. 新增首次启动遥测告知；2. 修复若干问题"
git push origin main --tags
```

发布说明留空时,CI 自动取上一个 tag 到当前 tag 的 commit 标题(过滤 chore(release)/merge)。

## 2. CI 自动执行(release.yml,共 7 步)

1. **拉三方二进制**:nezha-agent / ServerStatus client / frpc / cloudflared,双架构下载后 `lipo` 合并 universal;devtunnel 因微软 EULA 不捆绑
2. **编译**:`./build.sh <version> <build>`,build 号自动取 appcast.json 当前值 +1
3. **DMG**:`hdiutil` 打包 `MacHead-v<version>-macos-universal.dmg`
4. **R2 上传**:`wrangler r2 object put headlessmac-releases/<DMG>`
5. **appcast**:更新 `website/public/appcast.json` 五字段 → bot 提交 `chore(release): update appcast.json for vX` 并推 main
6. **GitHub Release**:自动创建,标题为裸 `vX`(tag 名,不带 "MacHead" 前缀——仓库上下文已有产品名,与 GitHub 生态惯例一致),DMG 挂为资产,附自动生成的技术提交日志
7. **官网部署**(级联):appcast 提交推送到 main 后,由 **Cloudflare Pages 的 Git 集成**自动构建部署 headlessmac.com,OTA 立即生效。注意:该提交由 GITHUB_TOKEN 产生,按 GitHub 设计**不会**级联触发 Actions,`deploy.yml`→gh-pages 这条路对发版提交不生效(gh-pages 为遗留分支,不服务线上域名)

## 3. 发布后核验

- Actions 页面确认 release.yml 与级联的 deploy.yml 均绿
- `https://headlessmac.com/appcast.json` 的 version/build 已更新
- `https://releases.headlessmac.com/MacHead-vX-macos-universal.dmg` 可下载

## 4. 禁止事项

- 严禁跳过发版流程手动改 appcast.json 版本字段后直接推 main(会触发 OTA 推给全量用户)
- 严禁把 DMG 直接 commit 进仓库
- devtunnel 严禁下载捆绑(微软专有 EULA)

## 5. 开发构建(非发布)

```bash
./build.sh --no-install   # 只编译,产物 ./MacHead.app,不装 /Applications、不重启
./build.sh                # 编译 + 安装 + 重启(开发者日常)
```

注意:`Resources/` 下的第三方二进制不入 git,worktree 环境跑 `build.sh` 前需先从主 checkout 复制。
