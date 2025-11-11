#!/bin/bash
set -euo pipefail

required=(overlay br_netfilter)
status=0

# Temporary (loaded) modules
for m in "${required[@]}"; do
    if lsmod | awk '{print $1}' | grep -q "^${m}$"; then
        echo "${m}_temp=on"
    else
        echo "${m}_temp=off"
        status=1
    fi
done

conf_dir=/etc/modules-load.d

# Persistent configuration
if [ -d "$conf_dir" ]; then
    files=( "$conf_dir"/* )
    if [ ! -e "${files[0]}" ]; then
        for m in "${required[@]}"; do
            echo "${m}_perm=off"
            status=1
        done
    else
        for m in "${required[@]}"; do
            if grep -E -xq "${m}" "$conf_dir"/* 2>/dev/null; then
                echo "${m}_perm=on"
            else
                echo "${m}_perm=off"
                status=1
            fi
        done
    fi
else
    for m in "${required[@]}"; do
        echo "${m}_perm=off"
    done
    status=1
fi

exit $status