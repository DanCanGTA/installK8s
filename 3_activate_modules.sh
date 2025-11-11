#!/bin/bash
set -euo pipefail

conf=/etc/modules-load.d/kubernetes.conf

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check="$script_dir/03_activate_modules_check.sh"

check_output=""
if [ -x "$check" ]; then
    echo "Invoking check script: $check"
    # allow non-zero exit codes from the check script and capture its output
    set +e
    check_output="$("$check" 2>&1)"
    check_rc=$?
    set -e
    if [ $check_rc -ne 0 ]; then
        echo "  Note: check script exited with $check_rc; parsing its output where possible."
    fi
else
    echo "  ERROR: check script not found or not executable: $check"
    echo "  Aborting because this script now relies on the check script to declare required modules."
    exit 1
fi

# Parse check output expecting lines like:
# overlay_temp=off
# br_netfilter_temp=off
# overlay_perm=off
# br_netfilter_perm=off
declare -A temp_status
declare -A perm_status
modules=()

while IFS= read -r line; do
    # skip empty lines and comments
    case "$line" in
        ''|\#*) continue ;;
    esac

    if [[ "$line" =~ ^([A-Za-z0-9_]+)=(on|off)$ ]]; then
        var="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"

        case "$var" in
            *_temp)
                mod="${var%_temp}"
                temp_status["$mod"]="$val"
                ;;
            *_perm)
                mod="${var%_perm}"
                perm_status["$mod"]="$val"
                ;;
            *)
                # ignore unrelated variables
                continue
                ;;
        esac

        # track module name for iteration (avoid duplicates)
        if ! printf '%s\n' "${modules[@]}" | grep -xq -- "${mod}"; then
            modules+=("$mod")
        fi
    fi
done <<< "$check_output"

if [ ${#modules[@]} -eq 0 ]; then
    echo "No module status lines found in check output; nothing to do."
    exit 0
fi

to_temp=()
to_perm=()
for m in "${modules[@]}"; do
    ts="${temp_status[$m]:-}"
    ps="${perm_status[$m]:-}"

    if [ -z "$ts" ]; then
        echo "  Check did not report temporary (loaded) status for: $m"
    else
        if [ "$ts" = "off" ]; then
            to_temp+=("$m")
        else
            echo "  Already temporarily present (per check): $m"
        fi
    fi

    if [ -z "$ps" ]; then
        echo "  Check did not report persistent (config) status for: $m"
    else
        if [ "$ps" = "off" ]; then
            to_perm+=("$m")
        else
            echo "  Already persistent in config (per check): $m"
        fi
    fi
done

if [ ${#to_temp[@]} -gt 0 ]; then
    echo "Temporarily loading modules with modprobe (only missing):"
    for m in "${to_temp[@]}"; do
        if modprobe "$m"; then
            echo "  Loaded: $m"
        else
            echo "  ERROR: failed to modprobe $m" >&2
            exit 1
        fi
    done
else
    echo "No modules need temporary loading."
fi

if [ ${#to_perm[@]} -gt 0 ]; then
    echo
    echo "Ensuring persistent configuration at $conf"
    mkdir -p "$(dirname "$conf")"
    touch "$conf"

    for m in "${to_perm[@]}"; do
        if grep -E -xq "^${m}$" "$conf"; then
            echo "  Already present in $conf: $m"
        else
            echo "$m" >> "$conf"
            echo "  Added to $conf: $m"
        fi
    done
else
    echo "No modules need to be added to persistent configuration."
fi

echo "Done."
