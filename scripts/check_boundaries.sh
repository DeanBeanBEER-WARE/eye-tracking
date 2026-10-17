#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

SOURCES="Packages/EyeCore/Sources"
MODULES="CoreKit UpdateKit AppSupportKit TrackingKit GazeKit PointerKit"
violations=0

forbid() {
    local module="$1"
    shift
    local hits
    hits="$(grep -rlE "^[[:space:]]*(@[A-Za-z]+ |(public|package|internal|private|fileprivate) )?import $module\$" \
        "$@" 2>/dev/null || true)"
    if [ -n "$hits" ]; then
        echo "ERROR: these files must not import $module:"
        echo "$hits" | sed 's/^/  /'
        violations=1
    fi
}

allowed() {
    case "$1" in
        CoreKit) echo "" ;;
        GazeKit) echo "CoreKit TrackingKit" ;;
        PointerKit) echo "CoreKit GazeKit" ;;
        *) echo "CoreKit" ;;
    esac
}

for module in $MODULES; do
    for other in $MODULES; do
        if [ "$other" != "$module" ] && ! echo " $(allowed "$module") " | grep -q " $other "; then
            forbid "$other" "$SOURCES/$module"
        fi
    done
done

if [ "$violations" -ne 0 ]; then
    exit 1
fi
echo "Module boundaries OK."
