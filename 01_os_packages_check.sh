#!/usr/bin/env bash
set -euo pipefail

status=0
outputToInstall=""

# parse command-line options (only consumes --outputToInstall)
if [[ "${1-}" == "--outputToInstall" ]]; then
    shift
    outputToInstall=true
elif [[ "${1-}" == "--help" ]]; then
    printf 'Usage: %s [--outputToInstall]\n' "$(basename "$0")" >&2
    exit -1
fi

# read package expectations from "basicPackages" located next to this script
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pkgfile="$script_dir/basicPackages"

if [[ ! -r "$pkgfile" ]]; then
    printf 'Error: cannot read package file: %s\n' "$pkgfile" >&2
    exit 2
fi

while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue

    # parse fields
    package_name=$(printf '%s' "$line" | cut -d'|' -f1)
    package_version=$(printf '%s' "$line" | cut -d'|' -f2)
    third_field=$(printf '%s' "$line" | cut -d'|' -f3)
    package_release=$(printf '%s' "$third_field" | cut -d':' -f1)
    package_arch=$(printf '%s' "$third_field" | cut -d':' -f2)
    extra_opt=$(printf '%s' "$line" | cut -d'|' -f4)

    installed=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' "$package_name" 2>/dev/null | grep -E '^[^ ]+$' || true)
    installed_version=$(rpm -q --qf '%{VERSION}\n' "$package_name" 2>/dev/null | grep -E '^[^ ]+$' || true)

    if [[ -z "$installed" ]]; then
        # human log to stderr, machine output to stdout
        if [[ -n "$outputToInstall" ]]; then
            # add extra_opt field
            printf 'MISSING|%s-%s-%s.%s|%s\n' \
                "$package_name" "$package_version" "$package_release" "$package_arch" "$extra_opt"
        else
            printf 'MISSING: %s (expected %s)\n' "$package_name" "$package_version" >&2
        fi
        status=1

    elif [[ "$installed_version" != "$package_version" ]]; then
        if [[ -n "$outputToInstall" ]]; then
            # add extra_opt field
            printf 'UNMATCHED|%s|%s|%s|%s\n' \
                "$package_name" "$installed_version" "$package_version" "$extra_opt"
        else
            printf 'WARNING: %s installed as %s but expected %s\n' "$package_name" "$installed_version" "$package_version" >&2
        fi

    else
        if [[ "$installed" != "$package_name-$package_version-$package_release.$package_arch" ]]; then
            printf 'Minor Difference: %s installed, but expected %s-%s-%s.%s\n' \
                "$installed" "$package_name" "$package_version" "$package_release" "$package_arch"
        else
            printf 'OK: %s is already installed as expected\n' "$installed"
        fi
    fi
done < "$pkgfile"

exit $status