#!/bin/bash

# Function to compare two version strings
# Arguments: $1 = version 1, $2 = version 2
# Output:
#   -1 if version 1 is older than version 2
#    0 if version 1 is the same as version 2
#    1 if version 1 is newer than version 2
compare_versions() {
    local ver1="$1"
    local ver2="$2"

    if [ "$ver1" = "$ver2" ]; then
        echo 0
        return
    fi

    # Use sort -V to determine the order
    # The output will be the lower version followed by the higher version
    local sorted_versions
    sorted_versions=$(printf '%s\n' "$ver1" "$ver2" | sort -V)
    
    # Extract the first line of the sorted output
    local lowest_version
    lowest_version=$(head -n 1 <<< "$sorted_versions")

    if [ "$lowest_version" = "$ver1" ]; then
        # If ver1 is the lowest, it's older than ver2
        echo -1
    else
        # If ver2 is the lowest, ver1 is newer than ver2
        echo 1
    fi
}

# You can capture the result in a variable:
# RESULT=$(compare_versions "1.12" "1.12.0")
# echo $RESULT

# call the check script and act on its output
check_script="$(dirname "${BASH_SOURCE[0]}")/01_os_packages_check.sh"
if [ ! -x "$check_script" ]; then
    check_script="./01_os_packages_check.sh"
fi

# Iterate over each line of the check script's output
while IFS= read -r line; do
    case "$line" in
        MISSING\|*)
            IFS='|' read -r _ pkg extra_opt <<< "$line"

            if [ -n "$extra_opt" ]; then
                echo "Installing missing package: $pkg  (option: $extra_opt)"
                dnf install -y "$extra_opt" "$pkg"
            else
                echo "Installing missing package: $pkg"
                dnf install -y "$pkg"
            fi
            ;;
        UNMATCHED\|*)
            # split on '|' and read fields: UNMATCHED|pkg|installed|expected|extra_option
            IFS='|' read -r _ pkg installed expected extra_opt <<< "$line"

            if [ -z "$expected" ] || [ -z "$installed" ]; then
                echo "Warning: could not parse versions from line: $line"
                continue
            fi

            cmp_result=$(compare_versions "$expected" "$installed")
            if [ "$cmp_result" -eq 1 ]; then
                echo "Expected version ($expected) is newer than installed ($installed) for $pkg — installing expected version"
                # try installing package-version, fall back to plain package install if needed
                if [ -n "$extra_opt" ]; then
                    dnf install -y "$extra_opt" "${pkg}-${expected}" \
                        || dnf install -y "$extra_opt" "$pkg-$expected" \
                        || dnf install -y "$extra_opt" "$pkg"
                else
                    dnf install -y "${pkg}-${expected}" \
                        || dnf install -y "$pkg-$expected" \
                        || dnf install -y "$pkg"
                fi
            elif [ "$cmp_result" -eq -1 ]; then
                echo "Warning: installed version ($installed) is newer than expected ($expected) for $pkg"
            else
                echo "Package $pkg already at expected version $expected"
            fi
            ;;
        *)
            echo $line
            ;;
    esac
done < <("$check_script" --outputToInstall)
