#!/bin/bash
# check temporary swap (proc) and permanent swap (fstab)

# temp
if tail -n +2 /proc/swaps | grep -q .; then
    SWAP_TEMP=on
else
    SWAP_TEMP=off
fi

# permanent (non-commented fstab entries with 3rd field == "swap")
if [ -n "$(awk '$1 !~ /^#/ && $3 == "swap"' /etc/fstab)" ]; then
    SWAP_PERM=on
else
    SWAP_PERM=off
fi

echo "SWAP_TEMP=$SWAP_TEMP"
echo "SWAP_PERM=$SWAP_PERM"

# success only when both are off
if [ "$SWAP_TEMP" = "off" ] && [ "$SWAP_PERM" = "off" ]; then
    exit 0
else
    exit 1
fi
