#!/bin/bash
set -euo pipefail

# Always install the latest patch version of a given CRI-O major.minor version on CentOS 8.
CRIO_VERSION="1.27"  

# Always install the latest patch version of a given K8s major.minor version.
# Only if you want to install <=1.23 specific patch, use e.g. 1.23.17
K8S_VERSION="1.27"


# --------- Helpers ---------
log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
fatal() { err "$*"; exit 1; }

# Function to normalize version to include patch if missing
normalize_version() {
    local ver=$1
    if [[ $ver =~ ^([0-9]+\.[0-9]+)$ ]]; then
        # Only major.minor provided, append .0
        ver="${ver}.0"
    fi
    echo "$ver"
}

CRIO_MAJOR_MINOR_PATCH=$(normalize_version "$CRIO_VERSION")

# Extract major.minor and major.minor.patch
CRIO_MAJOR_MINOR=$(echo "$CRIO_MAJOR_MINOR_PATCH" | awk -F. '{print $1"."$2}')
CRIO_VERSION_INSTALL=$CRIO_MAJOR_MINOR_PATCH

# Determine repository URL based on version
if [[ $(echo "$CRIO_MAJOR_MINOR < 1.29" | bc) -eq 1 ]]; then
    # Older style repo (<=1.28)
    REPO_BASE="https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_MAJOR_MINOR:/${CRIO_MAJOR_MINOR_PATCH}/CentOS_8"
    REPO_FILE="devel:kubic:libcontainers:stable:cri-o:${CRIO_MAJOR_MINOR}:${CRIO_MAJOR_MINOR_PATCH}.repo"
else
    # Newer style repo (>=1.29)
    # Use branch-based repo; patch number is not in the path
    REPO_BASE="https://download.opensuse.org/repositories/isv:/cri-o:/stable:/v${CRIO_MAJOR_MINOR}:/build/rpm"
    REPO_FILE="isv:cri-o:stable:v${CRIO_MAJOR_MINOR}:build.repo"
    # Keep the original user specified version # for dnf installation
    # If user specified 1.29, we will install the latest 1.29.x
    # If user specified 1.29.0, we will install 1.29.0
    CRIO_VERSION_INSTALL=$CRIO_VERSION
fi

echo "CRI-O version: $CRIO_VERSION_INSTALL"
echo "Repository URL: $REPO_BASE"

# Download the repo file
echo "Downloading repo file..."
wget -q -O "/etc/yum.repos.d/${REPO_FILE}" "${REPO_BASE}/${REPO_FILE}" || {
    echo "Failed to download repository file."
    exit 1
}

log "Cleaning dnf cache..."
dnf clean all
dnf makecache

# Install CRI-O
echo "Installing CRI-O..."
dnf install -y cri-o || {
    echo "Failed to install CRI-O."
    exit 1
}

# Enable and start CRI-O
# sudo systemctl enable crio
# sudo systemctl start crio
