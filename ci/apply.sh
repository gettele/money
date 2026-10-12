#!/usr/bin/env bash
# Usage: ci/apply.sh <wallet-engine clone> <engine commit>
#
# Checks out the commit and applies patches/ on top. Committer and dates are
# fixed, so the result is the exact commit the tag tele/<commit>/<series> points to.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
engine=$1
pin=$2

git -C "$engine" checkout -q --detach "$pin"
GIT_COMMITTER_NAME=nitreojs \
GIT_COMMITTER_EMAIL=hello@starkow.dev \
    git -C "$engine" -c commit.gpgSign=false am -q --3way --keep-cr --committer-date-is-author-date \
    "$root"/patches/*.patch
