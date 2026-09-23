#!/bin/bash
# MacHead 本地发布流水线 — GitHub Actions (release.yml) 的本地等价实现
# 用途：GitHub 账号受限导致 Actions 不可用时，在本机完成完整发版
# 用法：./Scripts/release-local.sh <version> [发布说明] [--no-push]
# 示例：./Scripts/release-local.sh 0.1.20 "新增内网穿透设置分区；网站部署恢复直传"
#
# 前置条件：wrangler 已登录（npx wrangler whoami 可见账号），对 R2 桶 headlessmac-releases 有写权限
set -euo pipefail
export NODE_OPTIONS="--dns-result-order=ipv4first ${NODE_OPTIONS:-}"
cd "$(dirname "$0")/.."

VERSION="${1:?用法: $0 <version> [发布说明] [--no-push]}"
shift || true
PUSH=1
NOTES=""
for arg in "$@"; do
  case "$arg" in
    --no-push) PUSH=0 ;;
    *) NOTES="${NOTES}${NOTES:+ }${arg}" ;;
  esac
done

TAG="v${VERSION}"
DMG_NAME="MacHead-${TAG}-macos-universal.dmg"

# ── 发布说明：未显式给出时，沿用 CI 逻辑自动取上一个 tag 之后的提交 ──
if [ -z "$NOTES" ]; then
  PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
  RANGE="${PREV_TAG:+${PREV_TAG}..HEAD}"
  NOTES=$(git log ${RANGE:-HEAD} --pretty=format:"%s" \
    | grep -viE "chore\(release\)|Merge pull request|Merge branch|\[skip ci\]" \
    | awk '{print NR ". " $0}' || true)
  [ -n "$NOTES" ] || NOTES="1. 优化了系统运行效率，修复了部分已知问题。"
fi

echo "==> 发布 MacHead ${TAG} (build 将自动递增)"
echo "    发布说明："
echo "${NOTES}" | sed 's/^/    /'

# ── 1. 拉取第三方二进制并合并通用架构（同 release.yml）──
echo "==> [1/6] 拉取最新 frp / nezha / ServerStatus / cloudflared ..."
TEMP_DIR="temp_binaries"
trap 'rm -rf "${TEMP_DIR}"' EXIT
mkdir -p Resources "${TEMP_DIR}"

# 探测 GitHub 最新版本号；失败时给出明确错误而非静默退出
latest_ver() {
  local ver
  ver=$(curl -sI --retry 3 --connect-timeout 10 "https://github.com/$1/releases/latest" | grep -i '^location' | awk -F'/' '{print $NF}' | tr -d '\r\n')
  [ -n "$ver" ] || { echo "错误：无法获取 $1 的最新版本号，请检查网络后重试" >&2; exit 1; }
  echo "$ver"
}

NEZHA_VER=$(latest_ver nezhahq/agent)
curl -sL --retry 3 --connect-timeout 15 -o "${TEMP_DIR}/nezha_amd64.zip" "https://github.com/nezhahq/agent/releases/download/${NEZHA_VER}/nezha-agent_darwin_amd64.zip"
curl -sL --retry 3 --connect-timeout 15 -o "${TEMP_DIR}/nezha_arm64.zip" "https://github.com/nezhahq/agent/releases/download/${NEZHA_VER}/nezha-agent_darwin_arm64.zip"
unzip -oq "${TEMP_DIR}/nezha_amd64.zip" -d "${TEMP_DIR}/nezha_amd64"
unzip -oq "${TEMP_DIR}/nezha_arm64.zip" -d "${TEMP_DIR}/nezha_arm64"
lipo -create "${TEMP_DIR}/nezha_amd64/nezha-agent" "${TEMP_DIR}/nezha_arm64/nezha-agent" -output Resources/nezha-agent

STATUS_VER=$(latest_ver zdz/ServerStatus-Rust)
curl -sL --retry 3 --connect-timeout 15 -o "${TEMP_DIR}/status_amd64.zip" "https://github.com/zdz/ServerStatus-Rust/releases/download/${STATUS_VER}/client-x86_64-apple-darwin.zip"
curl -sL --retry 3 --connect-timeout 15 -o "${TEMP_DIR}/status_arm64.zip" "https://github.com/zdz/ServerStatus-Rust/releases/download/${STATUS_VER}/client-aarch64-apple-darwin.zip"
unzip -oq "${TEMP_DIR}/status_amd64.zip" -d "${TEMP_DIR}/status_amd64"
unzip -oq "${TEMP_DIR}/status_arm64.zip" -d "${TEMP_DIR}/status_arm64"
lipo -create "${TEMP_DIR}/status_amd64/stat_client" "${TEMP_DIR}/status_arm64/stat_client" -output Resources/serverstatus-client

FRP_VER=$(latest_ver fatedier/frp)
FRP_RAW_VER="${FRP_VER#v}"
curl -sL --retry 3 --connect-timeout 15 -o "${TEMP_DIR}/frp_amd64.tar.gz" "https://github.com/fatedier/frp/releases/download/${FRP_VER}/frp_${FRP_RAW_VER}_darwin_amd64.tar.gz"
curl -sL --retry 3 --connect-timeout 15 -o "${TEMP_DIR}/frp_arm64.tar.gz" "https://github.com/fatedier/frp/releases/download/${FRP_VER}/frp_${FRP_RAW_VER}_darwin_arm64.tar.gz"
tar -xzf "${TEMP_DIR}/frp_amd64.tar.gz" -C "${TEMP_DIR}"
tar -xzf "${TEMP_DIR}/frp_arm64.tar.gz" -C "${TEMP_DIR}"
lipo -create "${TEMP_DIR}/frp_${FRP_RAW_VER}_darwin_amd64/frpc" "${TEMP_DIR}/frp_${FRP_RAW_VER}_darwin_arm64/frpc" -output Resources/frpc

CFD_VER=$(latest_ver cloudflare/cloudflared)
curl -sL --retry 3 --connect-timeout 15 -o "${TEMP_DIR}/cloudflared_amd64.tgz" "https://github.com/cloudflare/cloudflared/releases/download/${CFD_VER}/cloudflared-darwin-amd64.tgz"
curl -sL --retry 3 --connect-timeout 15 -o "${TEMP_DIR}/cloudflared_arm64.tgz" "https://github.com/cloudflare/cloudflared/releases/download/${CFD_VER}/cloudflared-darwin-arm64.tgz"
# 两个压缩包内层文件同名，必须分目录解压后再合并
mkdir -p "${TEMP_DIR}/cfd_amd64" "${TEMP_DIR}/cfd_arm64"
tar -xzf "${TEMP_DIR}/cloudflared_amd64.tgz" -C "${TEMP_DIR}/cfd_amd64"
tar -xzf "${TEMP_DIR}/cloudflared_arm64.tgz" -C "${TEMP_DIR}/cfd_arm64"
lipo -create "${TEMP_DIR}/cfd_amd64/cloudflared" "${TEMP_DIR}/cfd_arm64/cloudflared" -output Resources/cloudflared

# devtunnel 为微软专有 EULA 组件，禁止捆绑再分发，不在此下载；
# 用户可在 App 内通过一键安装从微软官方获取

# ── 2. 构建通用二进制 App ──
echo "==> [2/6] 编译 ${TAG} ..."
BUILD=$(python3 -c "import json; print(json.load(open('website/public/appcast.json')).get('build', 1) + 1)")
./build.sh "${VERSION}" "${BUILD}"

# ── 3. 打包 DMG ──
echo "==> [3/6] 打包 ${DMG_NAME} ..."
rm -rf dist-dmg "${DMG_NAME}"
mkdir -p dist-dmg
cp -R "MacHead.app" dist-dmg/
ln -s /Applications dist-dmg/Applications
hdiutil create -fs HFS+ -srcfolder dist-dmg -volname "MacHead" "${DMG_NAME}" >/dev/null
rm -rf dist-dmg

# ── 4. 上传 Cloudflare R2 ──
echo "==> [4/6] 上传 R2 (headlessmac-releases) ..."
npx wrangler r2 object put "headlessmac-releases/${DMG_NAME}" --file="${DMG_NAME}" --remote

# ── 5. 更新 appcast.json（OTA 更新通道）──
echo "==> [5/6] 更新 appcast.json ..."
PUB_DATE=$(date +%Y-%m-%d)
export TAG VERSION NOTES PUB_DATE BUILD
python3 - <<'PY'
import json, os

tag = os.environ['TAG']
data = json.load(open('website/public/appcast.json'))
data['version'] = os.environ['VERSION']
data['build'] = int(os.environ['BUILD'])
data['pubDate'] = os.environ['PUB_DATE']
data['url'] = f'https://releases.headlessmac.com/MacHead-{tag}-macos-universal.dmg'
data['releaseNotes'] = os.environ['NOTES']
json.dump(data, open('website/public/appcast.json', 'w'), indent=2, ensure_ascii=False)
PY

git add website/public/appcast.json
git commit -m "chore(release): update appcast.json for ${TAG}"
# 附注 tag 以发布说明为消息：未来账号恢复后，release.yml 可复用同一约定
git tag -a "${TAG}" -m "${NOTES}"

if [ "$PUSH" -eq 1 ]; then
  git push origin main --tags
  echo "==> 已推送 main 与 ${TAG}"
else
  echo "==> (未推送；稍后手动执行: git push origin main --tags)"
fi

# ── 6. 部署官网（appcast.json 随官网静态资源下发，Pages Git 集成失效时必须直传）──
echo "==> [6/6] 部署官网 (发布 appcast) ..."
(cd website && npm run build >/dev/null && npx wrangler pages deploy dist --branch=main >/dev/null && echo "    官网已部署")

echo ""
echo "✅ 发布完成：${TAG} (build ${BUILD})"
echo "   DMG: ${DMG_NAME} (已上传 R2，本地副本保留)"
echo "   OTA: appcast 已随官网发布，用户端下次检查更新即可收到"
echo "   注：GitHub Release 页面未创建（Actions 受限），账号恢复后可补发"
