#!/usr/bin/env bash
# Tags tele/<engine commit>/<series> for every engine commit a Telegram client
# builds (ci/pins.sh, plus $EXTRA_PIN), after the patches apply and the tests
# pass, and checks that desktop-app's wallet-engine.patch still applies on top.
# Each failure opens one issue (no duplicates); a pin that passes everything
# closes its open issues.
#
# Env: GH_TOKEN, GITHUB_REPOSITORY, PUSH_REMOTE (a remote that may push tags);
# EXTRA_PIN (optional engine commit); DRY_RUN=1 tags nothing and opens no issues.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
series=$(tr -d '[:space:]' < "$root/SERIES")
engine=$(mktemp -d)/wallet-engine
log=$(mktemp)
public="https://github.com/$GITHUB_REPOSITORY.git"

report() {
    local title=$1 body=$2 open
    if [ "${DRY_RUN:-}" = 1 ]; then
        echo "issue: $title"
        cat "$body"
        return
    fi
    open=$(gh issue list --repo "$GITHUB_REPOSITORY" --state open --search "in:title \"$title\"" \
        --json title --jq "[.[] | select(.title == \"$title\")] | length")
    if [ "$open" = 0 ]; then
        gh issue create --repo "$GITHUB_REPOSITORY" --title "$title" --body-file "$body" > /dev/null
    fi
}

resolve() {
    local pin=$1 tag=$2
    [ "${DRY_RUN:-}" = 1 ] && return
    gh issue list --repo "$GITHUB_REPOSITORY" --state open --search "in:title ${pin:0:12}" --json number --jq '.[].number' |
        while read -r number; do
            gh issue close "$number" --repo "$GITHUB_REPOSITORY" --comment "Fixed: $tag passes." > /dev/null
        done
}

fenced() {
    echo '```'
    tail -n 200 "$log"
    echo '```'
}

"$root/ci/pins.sh" > "$root/pins.txt"
if [ -n "${EXTRA_PIN:-}" ]; then
    if ! [[ "$EXTRA_PIN" =~ ^[0-9a-f]{40}$ ]]; then
        echo "EXTRA_PIN must be a full engine commit hash" >&2
        exit 1
    fi
    echo "$EXTRA_PIN - manual" >> "$root/pins.txt"
fi
cat "$root/pins.txt"

git clone -q https://github.com/i582/wallet-engine.git "$engine"
git -C "$engine" config advice.detachedHead false

failed=0
for pin in $(cut -d' ' -f1 "$root/pins.txt" | sort -u); do
    tag="tele/$pin/$series"
    echo "::group::$tag"
    ok=1
    git -C "$engine" am --abort > /dev/null 2>&1 || true
    if git -C "$engine" fetch -q "$public" "refs/tags/$tag:refs/tags/$tag" 2> /dev/null; then
        git -C "$engine" checkout -q --detach "$tag"
        echo "$tag exists"
    elif ! "$root/ci/apply.sh" "$engine" "$pin" > "$log" 2>&1; then
        { echo "The patches don't apply to wallet-engine \`$pin\`. Resolve locally (see README)."; echo; fenced; } > "$log.md"
        report "Patches don't apply to ${pin:0:12}" "$log.md"
        failed=1
        echo "::endgroup::"
        continue
    elif ! (cd "$engine" && cargo test --locked --lib) > "$log" 2>&1; then
        { echo "Tests fail on wallet-engine \`$pin\` with the patches."; echo; fenced; } > "$log.md"
        report "Tests fail on ${pin:0:12}" "$log.md"
        failed=1
        echo "::endgroup::"
        continue
    elif [ "${DRY_RUN:-}" = 1 ]; then
        echo "would tag $tag at $(git -C "$engine" rev-parse HEAD)"
    else
        git -C "$engine" tag "$tag"
        git -C "$engine" push -q "$PUSH_REMOTE" "refs/tags/$tag"
        echo "tagged $tag at $(git -C "$engine" rev-parse HEAD)"
    fi
    for patches in $(awk -v pin="$pin" '$1 == pin && $2 != "-" { print $2 }' "$root/pins.txt" | sort -u); do
        if ! curl -fsSL "https://raw.githubusercontent.com/desktop-app/patches/$patches/wallet-engine.patch" |
            git -C "$engine" apply --check > "$log" 2>&1; then
            { echo "desktop-app/patches \`$patches\` wallet-engine.patch doesn't apply on top of \`$tag\`, so Telegram Desktop builds with it break."; echo; fenced; } > "$log.md"
            report "Desktop patch doesn't apply on ${pin:0:12}" "$log.md"
            ok=0
            failed=1
        fi
    done
    if [ "$ok" = 1 ]; then
        resolve "$pin" "$tag"
    fi
    echo "::endgroup::"
done
exit "$failed"
