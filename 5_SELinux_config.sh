#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $0 <permissive|enforcing>"
    echo "Example:"
    echo "  $0 permissive"
    echo "  $0 enforcing"
    exit 2
}

# ensure argument
if [ $# -lt 1 ]; then
    usage
fi

# normalize input (case-insensitive)
TARGET_MODE=$(echo "$1" | tr '[:upper:]' '[:lower:]')
case "$TARGET_MODE" in
    permissive|enforcing) ;;
    *) usage ;;
esac

TARGET_MODE_UPPER=$(tr '[:lower:]' '[:upper:]' <<<"$TARGET_MODE")

if ! command -v getenforce &>/dev/null; then
    echo "getenforce command not found; SELinux may not be installed." >&2
    exit 0
fi

# Get current modes
output="$("$DIR/05_SELinux_check.sh" || true)"
TEMP_MODE=$(echo "$output" | awk -F= '/SELINUX_TEMP/{print $2}')
PERM_MODE=$(echo "$output" | awk -F= '/SELINUX_PERM/{print $2}')

CHANGE_TEMP=false
CHANGE_PERM=false

# Decide if changes needed
if [ "$TEMP_MODE" != "$TARGET_MODE_UPPER" ]; then
    CHANGE_TEMP=true
fi
if [ "$PERM_MODE" != "$TARGET_MODE" ]; then
    CHANGE_PERM=true
fi

# Apply changes only if needed
if $CHANGE_TEMP; then
    echo "Setting SELinux runtime to $TARGET_MODE..."
    setenforce $([ "$TARGET_MODE" = "permissive" ] && echo 0 || echo 1) || true
fi

if $CHANGE_PERM && [ -f /etc/selinux/config ]; then
    echo "Setting SELinux config to $TARGET_MODE..."
    sed -i.bak -r "s/^SELINUX=.*/SELINUX=$TARGET_MODE/" /etc/selinux/config || true
fi

log "Checking SELinux status after changes..."
$DIR/05_SELinux_check.sh
