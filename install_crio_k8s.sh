#!/bin/bash
set -euo pipefail

# Always install the latest patch of a given CRI-O major.minor on CentOS 8.
CRIO_VERSION="1.23"

# Always install the latest patch version of a given K8s major.minor version.
K8S_VERSION="1.23"

# Pod network add-on version (Calico)
CALICO_VERSION="3.28.5"

# --------- Helpers ---------
log() { echo "[INFO] $*"; }
warn() { echo "[WARNING] $*" >&2; }
err() { echo "[ERROR] $*" >&2; }
fatal() { err "$*"; exit 1; }

# Normalize version (add .0 if only major.minor)
normalize_version() {
    local ver=$1
    if [[ $ver =~ ^([0-9]+\.[0-9]+)$ ]]; then
        ver="${ver}.0"
    fi
    echo "$ver"
}

CRIO_MAJOR_MINOR_PATCH=$(normalize_version "$CRIO_VERSION")
CRIO_MAJOR_MINOR=$(echo "$CRIO_MAJOR_MINOR_PATCH" | awk -F. '{print $1"."$2}')

# Repo selection
if [[ $(echo "$CRIO_MAJOR_MINOR < 1.29" | bc) -eq 1 ]]; then
    REPO_BASE="https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/${CRIO_MAJOR_MINOR}/CentOS_8"
    REPO_FILE="devel:kubic:libcontainers:stable:cri-o:${CRIO_MAJOR_MINOR}.repo"
else
    REPO_BASE="https://download.opensuse.org/repositories/isv:/cri-o:/stable:/v${CRIO_MAJOR_MINOR}:/build/rpm"
    REPO_FILE="isv:cri-o:stable:v${CRIO_MAJOR_MINOR}:build.repo"
fi

log "CRI-O requested version: $CRIO_VERSION"
log "Repository URL: $REPO_BASE"

# Download repo file
log "Downloading repo file: $REPO_FILE"
wget -q -O "/etc/yum.repos.d/${REPO_FILE}" "${REPO_BASE}/${REPO_FILE}" \
    || fatal "Failed to download repository file."

log "Cleaning DNF cache..."
dnf clean all -q
dnf makecache -q

# Install CRI-O (always installs the latest patch for that major.minor)
log "Installing CRI-O..."
dnf install -y cri-o || fatal "Failed to install CRI-O."

log "Enabling and starting CRI-O service..."
systemctl enable crio
systemctl start crio

# --------- Check actual installed version ---------

ACTUAL_VERSION=$(rpm -q --qf "%{VERSION}" cri-o || echo "unknown")

log "CRI-O installed version: $ACTUAL_VERSION"

# If user specified a patch, compare
if [[ $CRIO_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # user wants exact patch
    if [[ "$CRIO_VERSION" != "$ACTUAL_VERSION" ]]; then
        warn "Requested CRI-O version '$CRIO_VERSION' but installed '$ACTUAL_VERSION'."
        warn "This happens because the repo provides only the latest patch for this branch."
    fi
fi

# --------- Install Kubernetes components ---------
log "Installing Kubernetes v${K8S_VERSION} components..."
BIN_DIR="/usr/local/bin"

# -------- Determine version --------
K8S_MAJOR=$(echo "$K8S_VERSION" | awk -F. '{print $1}')
K8S_MINOR=$(echo "$K8S_VERSION" | awk -F. '{print $2}')
K8S_MAJOR_MINOR="${K8S_MAJOR}.${K8S_MINOR}"

# -------- Install Logic --------
if [[ "$K8S_MAJOR_MINOR" < "1.24" ]]; then
    # Case 1: <1.24 -> download binaries manually
    log "K8s version <1.24, downloading binaries directly..."
    for bin in kubeadm kubelet kubectl; do
        URL="https://dl.k8s.io/release/v${K8S_VERSION}/bin/linux/amd64/${bin}"
        log "Downloading ${bin} from ${URL}..."
        curl -L --fail -o "${BIN_DIR}/${bin}" "$URL" || fatal "Failed to download $bin"
        chmod +x "${BIN_DIR}/${bin}"
    done
    ## commenting out crictl download as it is not necessary for CRI-O. 
    ## under installatio method is complicated, avoid doing it if this is not necessary.
    # log "Downloading crictl for K8s v${K8S_VERSION}..."
    # CRI_TOOLS_PATCH_VERSION=$(curl -s https://api.github.com/repos/kubernetes-sigs/cri-tools/tags \
    # | grep -oE "\"name\": \"v${CRIO_MAJOR_MINOR}\.[0-9]+\"" \
    # | sed -E 's/"name": "v([^"]+)"/\1/' \
    # | sort -V \
    # | tail -n 1)
    # wget -q -O "~/crictl.tar.gz" "https://github.com/kubernetes-sigs/cri-tools/releases/download/v${CRI_TOOLS_PATCH_VERSION}/crictl-v${CRI_TOOLS_PATCH_VERSION}-linux-amd64.tar.gz" \
    # || fatal "Failed to download repository file."

else
    # Case 2 & 3: >=1.24 -> create repo
    log "K8s version >=1.24, creating Kubernetes repo..."
    K8S_REPO_BASE="https://pkgs.k8s.io/core:/stable:/v${K8S_MAJOR_MINOR}/rpm"
    cat >/etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=${K8S_REPO_BASE}
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${K8S_MAJOR_MINOR}/rpm/repodata/repomd.xml.key
EOF

    # Decide whether to use --nogpgcheck
    DNF_GPG_OPTION=""
    if [[ "$K8S_MAJOR_MINOR" < "1.28" ]]; then
        warn "K8s version <1.28, will use --nogpgcheck for installation"
        DNF_GPG_OPTION="--nogpgcheck"
    fi

    log "Installing kubelet, kubeadm, kubectl..."
    dnf -y install kubelet kubeadm kubectl $DNF_GPG_OPTION --disableexcludes=kubernetes || \
    fatal "Failed to install kubelet/kubeadm/kubectl v${K8S_VERSION}"

    # for K8s >=1.24, crictl is installed together when installing kubeadm package
fi

# -------- Enable kubelet --------
systemctl enable --now kubelet


log "Downloading Calico v${CALICO_VERSION} manifest..."
 wget -q -O ~/calico.yaml https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/calico.yaml
