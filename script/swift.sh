#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
PROJECT_KEY="$(printf '%s' "$ROOT_DIR" | shasum | cut -c1-12)"
# Keep signed test bundles out of Desktop/iCloud file-provider directories.
BUILD_DIR="${MOUSE_ELF_BUILD_DIR:-$HOME/Library/Caches/MouseElf/$PROJECT_KEY}"
exec swift "$@" --scratch-path "$BUILD_DIR"
