#!/usr/bin/env bash
#
# containerdSetup.sh - Intelligent installer and service manager for container runtimes on RHEL 8.x
#
# Author: Daniel Jin
# Version: 1.1
# License: MIT
#
# Description:
#   Automatically ensures a functional container runtime on RHEL 8.x.
#   Default behavior checks existing installations and installs containerd or cri-o based on Podman presence.
#
# Usage:
#   containerdSetup.sh [OPTIONS]
#
# Options:
#   --containerd       Force install and enable containerd (clean up Podman/conflicts first)
#   --crio             Force install and enable cri-o, regardless of Podman presence
#   --status           Display runtime installation and service status only (no changes)
#   -h, --help         Show this help and exit
#   -v, --version      Show version information and exit
#
# Exit Codes:
#   0 - Success
#   1 - General error
#
# Example:
#   sudo ./containerdSetup.sh
#   sudo ./containerdSetup.sh --containerd
#   sudo ./containerdSetup.sh --crio
#
# Logs:
#   /var/log/containerdSetup.log

set -euo pipefail

VERSION="1.1"
LOGFILE="/var/log/containerdSetup.log"
exec > >(tee -a "$LOGFILE") 2>&1

# ===== Helper functions =====
log() { echo -e "[\033[1;34mINFO\033[0m] $*"; }
warn() { echo -e "[\033[1;33mWARN\033[0m] $*" >&2; }
error_exit() { echo -e "[\033[1;31mERROR\033[0m] $*" >&2; exit 1; }

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

show_version() {
    echo "containerdSetup.sh version ${VERSION}"
}

check_service_status() {
    local svc="$1"
    if systemctl is-enabled --quiet "$svc" && systemctl is-active --quiet "$svc"; then
        log "$svc is enabled and running."
        return 0
    fi
    log "$svc is not active, starting and enabling..."
    systemctl enable --now "$svc"
}

# ===== Installation functions =====
install_containerd() {
    log "Installing containerd..."

    # Disable container-tools module (Podman toolset)
    if dnf module list container-tools -y 2>/dev/null | grep -qE '\[e\]|enabled'; then
        log "Disabling container-tools module..."
        dnf module disable -y container-tools || true
    fi

    log "Removing conflicting Podman packages (if any)..."
    dnf remove -y podman buildah skopeo || true

    log "Cleaning dnf cache..."
    dnf clean all

    # Prepare dnf plugin tool
    log "Installing dnf-plugins-core..."
    dnf -y install dnf-plugins-core

    log "Setting up Docker repository..."
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    # Install containerd
    dnf install -y containerd.io || dnf install -y containerd

    log "After installation, preparing config.toml..."
    containerd config default | tee /etc/containerd/config.toml >/dev/null
    sed -i '/^\s*\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options\]/,/^\[/s/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

    systemctl enable --now containerd
    systemctl restart containerd
    systemctl status containerd --no-pager
    log "containerd installation complete."
}

install_crio() {
    local CRIO_VERSION="1.28"

    log "Installing CRI-O ${CRIO_VERSION}..."

    OS_VERSION_ID=$(source /etc/os-release && echo $VERSION_ID)
    cat >/etc/yum.repos.d/devel:kubic:libcontainers:stable.repo <<EOF
[devel_kubic_libcontainers_stable]
name=devel:kubic:libcontainers:stable
baseurl=https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_${OS_VERSION_ID}/
enabled=1
gpgcheck=0
EOF

    cat >/etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:${CRIO_VERSION}.repo <<EOF
[devel_kubic_libcontainers_stable_cri-o_${CRIO_VERSION}]
name=devel:kubic:libcontainers:stable:cri-o:${CRIO_VERSION}
baseurl=https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/${CRIO_VERSION}/CentOS_${OS_VERSION_ID}/
enabled=1
gpgcheck=0
EOF

    dnf install -y cri-o
    systemctl enable --now crio
    systemctl status crio --no-pager
    log "CRI-O installation complete."
}

show_status() {
    echo "=== Container Runtime Status ==="
    for svc in containerd crio podman; do
        if systemctl list-unit-files --type=service | grep -q "^${svc}.service"; then
            if systemctl is-active --quiet "$svc"; then
                state="active"
            else
                state="inactive"
            fi

            if systemctl is-enabled --quiet "$svc"; then
                enabled="enabled"
            else
                enabled="disabled"
            fi

            echo "Service: ${svc}.service -> ${state}, ${enabled}"
        else
            echo "Service: ${svc}.service -> not installed"
        fi
    done

    echo "================================"
}

# ===== Main logic =====
FORCE_MODE=""
STATUS_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --containerd) FORCE_MODE="containerd" ;;
        --crio) FORCE_MODE="crio" ;;
        --status) STATUS_ONLY=1 ;;
        -h|--help) usage; exit 0 ;;
        -v|--version) show_version; exit 0 ;;
        -*)
            echo "Unknown option: $1"
            echo "Try '$0 --help' for more information."
            exit 1
            ;;
        *) ;; # Ignore non-option arguments
    esac
    shift
done

log "Starting container runtime setup..."

if [[ "$STATUS_ONLY" -eq 1 ]]; then
    show_status
    exit 0
fi

if [[ "$FORCE_MODE" == "containerd" ]]; then
    install_containerd
    exit 0
elif [[ "$FORCE_MODE" == "crio" ]]; then
    install_crio
    exit 0
fi

# Default logic
if command -v containerd >/dev/null 2>&1; then
    log "Containerd is installed."
    check_service_status containerd
elif command -v podman >/dev/null 2>&1; then
    log "Podman is installed, installing CRI-O..."
    install_crio
else
    log "Neither containerd nor podman found, installing containerd..."
    install_containerd
fi

log "Setup completed."