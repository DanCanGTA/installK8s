#!/bin/bash
# check current (temporary) and configured (permanent) SELinux mode

# temp
if command -v getenforce &>/dev/null; then
    CUR_TEMP=$(getenforce 2>/dev/null)
else
    CUR_TEMP=unknown
fi

# permanent
if [ -f /etc/selinux/config ]; then
    CUR_PERM=$(awk -F= '/^SELINUX=/{print $2}' /etc/selinux/config | tr -d '[:space:]')
else
    CUR_PERM=missing
fi

echo "SELINUX_TEMP=$CUR_TEMP"
echo "SELINUX_PERM=$CUR_PERM"

# success only when both are permissive
if [ "$CUR_TEMP" == "Permissive" ] && [ "$CUR_PERM" == "permissive" ]; then
    exit 0
else
    exit 1
fi
