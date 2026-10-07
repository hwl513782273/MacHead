---
name: release-guide
description: Step-by-step guide for releasing new versions of MacHead via the local pipeline Scripts/release-local.sh (build, DMG, R2, appcast, tag, website deploy).
---
# MacHead 版本发布指南

本技能规定 MacHead 的标准发版流程。**规范流程是本地流水线 `Scripts/release-local.sh`**(2026-09 起生效);`.github/workflows/release.yml` 是同构的云端等价实现,账号恢复后可用,但以本地流水线为准。

## 0. 前置条件

- macOS 本机,已装 Xcode CLT、Node、Python3、wrangler(`npx wrangler whoami` 已登录,对 R2 桶 `headlessmac-releases` 有写权限)
- 工作区干净、在 `main` 分支
- worktree 环境需先从主 checkout 复制 `Resources/` 下不入 git 的二进制(如已跑过一次流水线会自动生成)

## 1. 一键发布

```bash
./Scripts/release-local.sh <version> "1. 用户可读的升级说明；2. 多条用分号分隔"
# 示例
./Scripts/release-local.sh 0.1.24 "新增首次启动遥测告知；修复若干问题"
```

可选 `--no-push`:本地完成构建/R2/appcast,不推送远程(稍后手动 `git push origin main --tags`)。

流水线 6 步(全自动):
1. **拉三方二进制**:nezha-agent / ServerStatus client / frpc / cloudflared,双架构下载后 `lipo` 合并 universal(探测上游 latest 失败会明确报错);devtunnel 因微软 EULA 不捆绑
2. **编译**:`./build.sh <version> <build>`,build 号自动取 appcast.json 当前值 +1
3. **DMG**:`hdiutil` 打包 `MacHead-v<version>-macos-universal.dmg`
4. **R2 上传**:`wrangler r2 object put headlessmac-releases/<DMG>`
5. **appcast + tag**:更新 `website/public/appcast.json` 五字段 → commit(`chore(release): update appcast.json for vX`)→ 附注 tag `vX`(tag message = 用户可读发布说明)
6. **官网部署**:`cd website && npm run build && npx wrangler pages deploy dist --branch=main`(appcast.json 随静态资源发布,OTA 立即生效)

发布说明未显式给出时,自动取上一个 tag 之后的 commit 标题(过滤 chore(release)/merge)。

## 2. 发布后补建 GitHub Release(可选)

本地流水线不创建 GitHub Release 页面。账号恢复后可补挂:

```bash
gh release create vX --title "MacHead vX" --latest --notes "…(与 appcast releaseNotes 一致)" "MacHead-vX-macos-universal.dmg"
```

## 3. 禁止事项

- 严禁跳过流水线手动改 appcast.json 版本字段后直接推 main(会触发 OTA 推给全量用户)
- 严禁把 DMG 直接 commit 进仓库
- devtunnel 严禁下载捆绑(微软专有 EULA)

## 4. 开发构建(非发布)

```bash
./build.sh --no-install   # 只编译,产物 ./MacHead.app,不装 /Applications、不重启
./build.sh                # 编译 + 安装 + 重启(开发者日常)
```
