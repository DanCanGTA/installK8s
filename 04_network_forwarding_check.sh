#!/usr/bin/env bash
# /root/installK8s/04_network_forwarding_check.sh
# Check that the required sysctl lines exist in any file under /etc/sysctl.d
set -u

keys=(
    "net.bridge.bridge-nf-call-ip6tables"
    "net.bridge.bridge-nf-call-iptables"
    "net.ipv4.ip_forward"
)

fail=0

for key in "${keys[@]}"; do
    # allow optional whitespace around '=' and require value 1
    regex="^${key//./\\.}[[:space:]]*=[[:space:]]*1([[:space:]]|\$)"
    matches=$(grep -HnE "$regex" /etc/sysctl.d/* 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
        # print which file(s) contain the matching line(s)
        printf '%s\n' "$matches"
    else
        printf 'MISSING: %s\n' "$key" >&2
        fail=1
    fi
done

# If sourced, use return; otherwise exit
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    return $fail
else
    exit $fail
fi
