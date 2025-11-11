#!/bin/bash

# Check if containerd is installed
# Determine installation and service statuses
containerd_installed=true
if ! command -v containerd >/dev/null 2>&1; then
    containerd_installed=false
fi

containerd_enabled=false
if systemctl is-enabled --quiet containerd 2>/dev/null; then
    containerd_enabled=true
fi

containerd_running=false
if systemctl is-active --quiet containerd; then
    containerd_running=true
fi

# Print statuses
printf 'containerd_installed=%s\n' "$containerd_installed"
printf 'containerd_enabled=%s\n' "$containerd_enabled"
printf 'containerd_running=%s\n' "$containerd_running"

# Fail if any status is false
if [ "$containerd_installed" = false ] || [ "$containerd_enabled" = false ] || [ "$containerd_running" = false ]; then
    exit 1
fi

# If all checks pass
if [[ " $* " == *" --outputToInstall "* ]]; then
    echo "✅ containerd is installed and running properly"
    echo "Service status:"
    systemctl status containerd
fi
exit 0