#!/usr/bin/env bash
# Prints the wallet-engine commits Telegram's clients build today, one per line:
#   <engine commit> <desktop-app/patches commit or -> <where it is pinned>
# Needs `gh` (authenticated) and `curl`.
set -euo pipefail

desktop() {
    local ref=$1 prepare pin patches
    prepare=$(curl -fsSL "https://raw.githubusercontent.com/telegramdesktop/tdesktop/$ref/Telegram/build/prepare/prepare.py")
    pin=$(grep -oP "^walletEngineRevision = '\K[0-9a-f]{40}" <<<"$prepare" || true)
    patches=$(awk "/stage\\('patches'/ { found = 1 } found && /git checkout [0-9a-f]{40}/ { print \$3; exit }" <<<"$prepare")
    if [ -n "$pin" ]; then
        echo "$pin ${patches:--} tdesktop@$ref"
    fi
}

ios() {
    local ref=$1 pin
    pin=$(gh api "repos/TelegramMessenger/Telegram-iOS/contents/third-party/wallet-engine/wallet-engine?ref=$ref" --jq .sha 2>/dev/null || true)
    if [ -n "$pin" ]; then
        echo "$pin - telegram-ios@$ref"
    fi
}

desktop "$(gh api repos/telegramdesktop/tdesktop/releases/latest --jq .tag_name)"
desktop dev
ios master
ios "$(gh api --paginate 'repos/TelegramMessenger/Telegram-iOS/tags?per_page=100' --jq '.[].name | select(test("^release-[0-9.]+$"))' | sort -V | tail -n 1)"
