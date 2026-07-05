---
name: mac-cleanup
description: |
  macOSの不要ファイルやキャッシュを削除してストレージを最適化する。
  Docker、開発キャッシュ、アプリケーションキャッシュ、ダウンロード整理、
  システムキャッシュ等を対話的に選択して安全にクリーンアップ。
disable-model-invocation: true
---

# Mac Cleanup - macOS メンテナンス自動実行

macOSの不要ファイルやキャッシュを削除してストレージを最適化します。削除前に対話的に削除対象を選択でき、安全にメンテナンスが実行できます。

```bash
#!/bin/bash
set -e

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧹 Mac Cleanup Tool${NC}"
echo "=========================================="

# 容量確認関数
check_size() {
    if [ -d "$1" ]; then
        du -sh "$1" 2>/dev/null | cut -f1
    else
        echo "0B"
    fi
}

echo -e "${YELLOW}📊 現在の使用量確認中...${NC}"
echo ""

# 削除候補の容量チェック
docker_size=$(docker system df --format "table {{.TotalCount}}\t{{.Size}}" 2>/dev/null | tail -n +2 | awk '{total+=$2} END {print total "MB"}' || echo "0MB")
cache_size=$(check_size ~/.cache)
npm_size=$(check_size ~/.npm)
library_cache_size=$(check_size ~/Library/Caches)
downloads_size=$(check_size ~/Downloads)
docker_container_size=$(check_size ~/Library/Containers/com.docker.docker/Data)

echo "削除対象の容量:"
echo "  🐳 Docker: $docker_size"
echo "  📦 ~/.cache: $cache_size"
echo "  📦 ~/.npm: $npm_size"
echo "  📦 ~/Library/Caches: $library_cache_size"
echo "  📥 ~/Downloads: $downloads_size"
echo "  🐳 Docker Desktop Data: $docker_container_size"
echo ""

# 対話的選択
echo -e "${YELLOW}削除する項目を選択してください (y/n):${NC}"

read -p "🐳 Docker system prune (コンテナ/イメージ/ボリューム全削除)? " -n 1 -r docker_choice
echo ""
read -p "📦 開発キャッシュ (~/.cache, ~/.npm)? " -n 1 -r dev_cache_choice
echo ""
read -p "📦 アプリケーションキャッシュ (~/Library/Caches)? " -n 1 -r app_cache_choice
echo ""
read -p "📥 ダウンロードフォルダ (.dmg/.zip/.pkg削除)? " -n 1 -r downloads_choice
echo ""
read -p "🍎 macOSシステムキャッシュ? " -n 1 -r system_choice
echo ""
read -p "☠️  危険: Docker Desktop完全リセット (全データ消失)? " -n 1 -r docker_reset_choice
echo ""

echo -e "${GREEN}🚀 クリーンアップ開始...${NC}"

# Docker system prune
if [[ $docker_choice =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}🐳 Docker system prune実行中...${NC}"
    docker system prune -a -f --volumes 2>/dev/null || echo "Dockerが起動していません"
    docker builder prune -a -f 2>/dev/null || true
fi

# 開発キャッシュ
if [[ $dev_cache_choice =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}📦 開発キャッシュ削除中...${NC}"
    rm -rf ~/.cache/* 2>/dev/null || true
    rm -rf ~/.npm/_cacache 2>/dev/null || true
    npm cache clean --force 2>/dev/null || true
    rm -rf ~/.cargo/registry/cache 2>/dev/null || true
    rm -rf ~/.cargo/git/checkouts 2>/dev/null || true
    go clean -cache -modcache -testcache 2>/dev/null || true
    echo "  ✅ 開発キャッシュ削除完了"
fi

# アプリケーションキャッシュ
if [[ $app_cache_choice =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}📦 アプリケーションキャッシュ削除中...${NC}"
    rm -rf ~/Library/Caches/* 2>/dev/null || true
    echo "  ✅ アプリケーションキャッシュ削除完了"
fi

# ダウンロードファイル
if [[ $downloads_choice =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}📥 ダウンロードファイル削除中...${NC}"
    find ~/Downloads -name "*.dmg" -delete 2>/dev/null || true
    find ~/Downloads -name "*.zip" -delete 2>/dev/null || true
    find ~/Downloads -name "*.pkg" -delete 2>/dev/null || true
    echo "  ✅ インストーラー削除完了"
fi

# システムキャッシュ
if [[ $system_choice =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}🍎 macOSシステムキャッシュ削除中...${NC}"
    sudo dscacheutil -flushcache 2>/dev/null || true
    sudo killall -HUP mDNSResponder 2>/dev/null || true
    rm -rf ~/Library/Logs/* 2>/dev/null || true
    xcrun simctl delete unavailable 2>/dev/null || true
    echo "  ✅ システムキャッシュ削除完了"
fi

# Docker Desktop完全リセット（危険）
if [[ $docker_reset_choice =~ ^[Yy]$ ]]; then
    echo -e "${RED}☠️  Docker Desktop完全リセット実行中...${NC}"
    echo -e "${RED}  警告: 全てのDockerデータが失われます${NC}"
    sleep 3
    osascript -e 'quit app "Docker"' 2>/dev/null || true
    sleep 5
    rm -rf ~/Library/Containers/com.docker.docker 2>/dev/null || true
    echo "  ✅ Docker Desktop リセット完了"
    echo "  ⚠️  Docker Desktopを再起動してください"
fi

# Homebrew cleanup
echo -e "${BLUE}🍺 Homebrew cleanup実行中...${NC}"
brew cleanup -s --prune=all 2>/dev/null || true
brew autoremove 2>/dev/null || true

# 結果表示
echo ""
echo -e "${GREEN}✨ クリーンアップ完了!${NC}"
echo ""
echo -e "${YELLOW}📊 削除後の状況:${NC}"
echo "  🐳 Docker: $(docker system df --format "table {{.TotalCount}}\t{{.Size}}" 2>/dev/null | tail -n +2 | awk '{total+=$2} END {print total "MB"}' || echo "0MB")"
echo "  📦 ~/.cache: $(check_size ~/.cache)"
echo "  📦 ~/.npm: $(check_size ~/.npm)"
echo "  📦 ~/Library/Caches: $(check_size ~/Library/Caches)"
echo "  📥 ~/Downloads: $(check_size ~/Downloads)"
echo ""
echo -e "${GREEN}🎉 PCが軽くなりました!${NC}"
```

## 機能

- 🐳 **Docker cleanup**: コンテナ/イメージ/ボリューム削除
- 📦 **開発キャッシュ**: npm, cargo, go等のキャッシュ削除
- 📦 **アプリキャッシュ**: ~/Library/Caches配下の削除
- 📥 **ダウンロード整理**: .dmg/.zip/.pkg削除
- 🍎 **システムキャッシュ**: DNS/ログ/Simulator削除
- ☠️ **Docker完全リセット**: 全データ消去（危険オプション）

## 安全性

- ✅ 対話式確認で誤削除防止
- ✅ システム重要ファイル保護
- ✅ 全コマンドエラーハンドリング対応
- ✅ 削除前後の容量表示
