#!/usr/bin/env bash
# Copyright (C) 2026 Nipher
# SPDX-License-Identifier: AGPL-3.0-only
#
# 分别构建 arm64 与 x86_64 的 OhNews 安装包（DMG）。
#
# 产物输出到 dist/OhNews-<版本>/，按版本号分目录：
# 不同版本的包不会混在一起，也不会因为文件名相同而互相覆盖。
#
# 用法：
#   scripts/build-dmg.sh              # 两个架构都打
#   scripts/build-dmg.sh arm64        # 只打 Apple Silicon
#   scripts/build-dmg.sh x86_64       # 只打 Intel
#
# 可选环境变量（正式分发时使用；不设置则产出未公证的开发包）：
#   SIGN_IDENTITY     Developer ID 签名身份，例如
#                     "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE    notarytool 凭据 profile 名，事先用
#                     `xcrun notarytool store-credentials <名>` 存好
#
# 凭据一律通过环境变量与钥匙串传入，不写进仓库。

set -euo pipefail

APP_NAME="OhNews"
SCHEME="OhNews"
PROJECT="OhNews.xcodeproj"
CONFIGURATION="Release"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

DIST_ROOT="$PROJECT_ROOT/dist"
BUILD_ROOT="$PROJECT_ROOT/build"

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

# ---------- 输出辅助 ----------

info() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m警告:\033[0m %s\n' "$1" >&2; }
fail() { printf '\033[1;31m错误:\033[0m %s\n' "$1" >&2; exit 1; }

# ---------- 参数 ----------

ARCHS_TO_BUILD=()
case "${1:-all}" in
  all)     ARCHS_TO_BUILD=(arm64 x86_64) ;;
  arm64)   ARCHS_TO_BUILD=(arm64) ;;
  x86_64)  ARCHS_TO_BUILD=(x86_64) ;;
  *)       fail "未知参数：$1（可用：all、arm64、x86_64）" ;;
esac

# ---------- 前置检查 ----------

command -v xcodebuild >/dev/null || fail "找不到 xcodebuild，请先安装 Xcode。"
command -v hdiutil >/dev/null || fail "找不到 hdiutil。"
[ -d "$PROJECT" ] || fail "找不到 $PROJECT。若源码有增删，请先运行 xcodegen generate。"

if [ -n "$SIGN_IDENTITY" ]; then
  security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY" \
    || fail "钥匙串里找不到签名身份：$SIGN_IDENTITY"
  info "签名身份：$SIGN_IDENTITY"
else
  warn "未设置 SIGN_IDENTITY，将使用 ad-hoc 签名。这样的安装包在别人机器上会被 Gatekeeper 拦截，"
  warn "需要对方在 Finder 中按住 Control 点击应用再选「打开」。"
fi

if [ -n "$NOTARY_PROFILE" ]; then
  [ -n "$SIGN_IDENTITY" ] || fail "公证必须配合 Developer ID 签名，请同时设置 SIGN_IDENTITY。"
  info "公证凭据 profile：$NOTARY_PROFILE"
fi

# ---------- 版本号 ----------

MARKETING_VERSION="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
  -showBuildSettings 2>/dev/null \
  | awk -F ' = ' '/ MARKETING_VERSION = /{print $2; exit}')"
[ -n "$MARKETING_VERSION" ] || fail "无法从工程读取 MARKETING_VERSION。"
info "版本号：$MARKETING_VERSION"

# 按版本号分目录：不同版本的包不会混在一起，也不会互相覆盖。
DIST_DIR="$DIST_ROOT/$APP_NAME-$MARKETING_VERSION"
mkdir -p "$DIST_DIR"

# ---------- 逐个架构构建与打包 ----------

BUILT_DMGS=()

for ARCH in "${ARCHS_TO_BUILD[@]}"; do
  info "构建 $ARCH（$CONFIGURATION）"

  DERIVED="$BUILD_ROOT/DerivedData-$ARCH"
  rm -rf "$DERIVED"

  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" \
    ARCHS="$ARCH" \
    ONLY_ACTIVE_ARCH=NO \
    build

  APP_PATH="$DERIVED/Build/Products/$CONFIGURATION/$APP_NAME.app"
  [ -d "$APP_PATH" ] || fail "构建成功但找不到 $APP_PATH"

  # 架构必须与本次目标一致，避免误打出 fat 包
  BINARY="$APP_PATH/Contents/MacOS/$APP_NAME"
  FOUND_ARCHS="$(lipo -archs "$BINARY")"
  if [ "$FOUND_ARCHS" != "$ARCH" ]; then
    fail "期望纯 $ARCH，实际是「$FOUND_ARCHS」。请检查 ARCHS 与 ONLY_ACTIVE_ARCH 设置。"
  fi
  info "架构校验通过：$FOUND_ARCHS"

  # 签名：有 Developer ID 时做正式签名，否则 ad-hoc
  if [ -n "$SIGN_IDENTITY" ]; then
    info "使用 Developer ID 签名并启用加固运行时"
    codesign --force --deep --options runtime --timestamp \
      --sign "$SIGN_IDENTITY" "$APP_PATH"
  else
    info "ad-hoc 签名"
    codesign --force --deep --sign - "$APP_PATH"
  fi

  codesign --verify --verbose=1 "$APP_PATH" >/dev/null 2>&1 \
    || fail "签名校验失败：$APP_PATH"

  # ---------- 制作 DMG ----------

  STAGING="$(mktemp -d)"
  trap 'rm -rf "$STAGING"' EXIT

  cp -R "$APP_PATH" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"

  DMG_NAME="$APP_NAME-$MARKETING_VERSION-$ARCH.dmg"
  DMG_PATH="$DIST_DIR/$DMG_NAME"
  rm -f "$DMG_PATH"

  info "生成 $DMG_NAME"
  hdiutil create \
    -volname "$APP_NAME $MARKETING_VERSION" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG_PATH" >/dev/null

  # 对 DMG 本身签名，便于公证与下载校验
  if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
  fi

  # ---------- 公证 ----------

  if [ -n "$NOTARY_PROFILE" ]; then
    info "提交公证（可能要几分钟）"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

    info "附加公证票据"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
  fi

  rm -rf "$STAGING"
  trap - EXIT

  SIZE="$(du -h "$DMG_PATH" | awk '{print $1}')"
  BUILT_DMGS+=("$DMG_NAME ($ARCH, $SIZE)")

  # Gatekeeper 结论：仅正式签名的包才有意义
  if [ -n "$SIGN_IDENTITY" ]; then
    if spctl --assess --type open --context context:primary-signature -v "$DMG_PATH" 2>&1 | grep -q accepted; then
      info "Gatekeeper 评估：通过"
    else
      warn "Gatekeeper 评估未通过，请检查签名与公证状态。"
    fi
  fi
done

# ---------- 汇总 ----------

info "完成，产物位于 dist/$APP_NAME-$MARKETING_VERSION/"
for ENTRY in "${BUILT_DMGS[@]}"; do
  printf '    %s\n' "$ENTRY"
done

if [ -z "$SIGN_IDENTITY" ]; then
  printf '\n'
  warn "本次为未公证的开发包。正式分发前请配置 Developer ID 证书与 notarytool 凭据："
  warn "  xcrun notarytool store-credentials ohnews"
  warn "  SIGN_IDENTITY=\"Developer ID Application: ...\" NOTARY_PROFILE=ohnews scripts/build-dmg.sh"
fi
