#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
./script/swift.sh build
./script/swift.sh test
./script/build_app.sh release
git diff --check
