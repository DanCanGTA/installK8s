#!/usr/bin/env bash
set -euo pipefail

# Apply prerequisite changes by invoking the "apply" scripts.
# Default SELinux target is 'permissive' unless provided as first argument.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# send stdout/stderr to both screen and files
exec > >(tee "${SCRIPT_NAME}.log") 2> >(tee "${SCRIPT_NAME}.err" >&2)

SELINUX_TARGET="${1:-permissive}"

echo "${SCRIPT_NAME} started at: $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo "Using SELinux target: $SELINUX_TARGET"

apply_scripts=(
    "1_os_packages.sh"
    "2_swap_disable.sh"
    "3_activate_modules.sh"
    "4_network_forwarding.sh"
    "5_SELinux_config.sh"
    "6_firewall_port.sh"
)

for script in "${apply_scripts[@]}"; do
    path="$SCRIPT_DIR/$script"
    echo
    echo "---- Executing: $script ----"
    if [ ! -x "$path" ]; then
        echo "ERROR: apply-script missing or not executable: $path" >&2
        exit 2
    fi

    # Special-case SELinux config script to pass the target
    if [ "$script" = "5_SELinux_config.sh" ]; then
        "$path" "$SELINUX_TARGET"
    else
        "$path"
    fi

    echo "---- Completed: $script ----"
done

echo
echo "All apply-scripts completed successfully."
exit 0
