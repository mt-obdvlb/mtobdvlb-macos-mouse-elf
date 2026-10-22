#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in run|--verify|--debug|--logs|--telemetry) ;; *) echo "usage: $0 [run|--verify|--debug|--logs|--telemetry]" >&2; exit 2;; esac
APP_BUNDLE="$ROOT_DIR/dist/MouseElf.app"
if /usr/bin/pgrep -x MouseElf >/dev/null; then
    /usr/bin/osascript -e 'tell application id "dev.mtobdvlb.mouse-elf" to quit'
    for attempt in {1..30}; do
        /usr/bin/pgrep -x MouseElf >/dev/null || break
        sleep 0.1
    done
    if /usr/bin/pgrep -x MouseElf >/dev/null; then
        echo "鼠标精灵仍在退出，请先停止任务并关闭应用。" >&2
        exit 1
    fi
fi
./script/build_app.sh debug
if [ "$MODE" = --debug ]; then exec /usr/bin/lldb -- "$APP_BUNDLE/Contents/MacOS/MouseElf"; fi
/usr/bin/open -n "$APP_BUNDLE"
case "$MODE" in
    --verify) sleep 1; /usr/bin/pgrep -x MouseElf >/dev/null; echo "MouseElf is running.";;
    --logs) exec /usr/bin/log stream --info --style compact --predicate 'process == "MouseElf"';;
    --telemetry) exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "dev.mtobdvlb.mouse-elf"';;
esac
