#!/bin/bash
set -euo pipefail

# Always install the latest patch of a given CRI-O major.minor on CentOS 8.
CRIO_VERSION="1.27"

# To check K8s patches:
# https://kubernetes.io/releases/patch-releases/#:~:text=These%20releases%20are%20no%20longer%20supported.%20Minor,Patch%20Release%2C%20End%20Of%20Life%20Date%2C%20Note.
# https://github.com/kubernetes/kubernetes/releases?page=20
# For <1.24, we need to specify the exact patch version to download binaries, like 1.23.17
# Otherwise, always install the latest patch version of a given K8s major.minor version.
K8S_VERSION="1.27"
# Make sure to set the correct API versions for kubeadm and kube-proxy config, acording to K8S_VERSION
KUBEADM_API_VERSION="v1beta3"
KUBEPROXY_API_VERSION="v1alpha1"

# Pod network add-on version (Calico)
# To check the available versions, visit: https://github.com/projectcalico/calico/releases?page=1
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

# --------- Enforce CRI-O and K8s major.minor compatibility ---------
K8S_MAJOR_MINOR=$(echo "$K8S_VERSION" | awk -F. '{print $1"."$2}')

if [[ "$CRIO_MAJOR_MINOR" != "$K8S_MAJOR_MINOR" ]]; then
    fatal "CRI-O version ${CRIO_MAJOR_MINOR} is NOT compatible with Kubernetes ${K8S_MAJOR_MINOR}.
Both CRI-O and Kubernetes must use the same major.minor version.
Example: CRI-O 1.23.x must match Kubernetes 1.23.x."
fi

log "Version check passed: CRI-O $CRIO_MAJOR_MINOR ↔ K8s $K8S_MAJOR_MINOR"

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

# --------- Configure CRI-O for kubelet (if needed) ---------
# Ensure CRI-O uses the correct cgroup manager (systemd) for kubelet compatibility
CRIO_CONF_DIR="/etc/crio"
# Find the main crio.conf file (there may be multiple, pick the one with the shortest path)
CRIO_CONF=$(
    find "$CRIO_CONF_DIR" -type f -name "*crio.conf" \
    | awk -F/ '{ print NF, $0 }' \
    | sort -n -k1,1 -k2,2 \
    | head -n 1 \
    | cut -d' ' -f2-
)
if [[ -f "${CRIO_CONF}" ]]; then
    log "Ensuring CRI-O uses systemd cgroup manager in ${CRIO_CONF}..."

    # Check if the correct setting already exists
    if grep -qE '^cgroup_manager *= *"systemd"' "${CRIO_CONF}"; then
        log "cgroup_manager already set to systemd; skipping update."
    else
        log "Backupting original CRI-O config to ${CRIO_CONF}.bak.systemd_cgroup"
        cp -p "${CRIO_CONF}" "${CRIO_CONF}.bak.systemd_cgroup"
        # Key exists but with wrong value → replace it
        if grep -q '^cgroup_manager' "${CRIO_CONF}"; then
            sed -ri 's/^cgroup_manager *= *.*/cgroup_manager = "systemd"/' "${CRIO_CONF}"
        else
            # If section exists, insert key under it
            if grep -q '^\[crio.runtime\]' "${CRIO_CONF}"; then
                sed -i '/^\[crio.runtime\]/a cgroup_manager = "systemd"' "${CRIO_CONF}"
            else
                # No section → append both section and key
                {
                    echo "[crio.runtime]"
                    echo 'cgroup_manager = "systemd"'
                } >> "${CRIO_CONF}"
            fi
        fi
    fi
fi


log "Enabling and starting CRI-O service..."
systemctl enable crio 2> >(while read -r l; do
    [[ "$l" =~ Created\ symlink ]] && echo "$l" || echo "$l" >&2
done)
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
        curl -L --fail --silent --show-error -o "${BIN_DIR}/${bin}" "$URL" || fatal "Failed to download $bin"
        chmod +x "${BIN_DIR}/${bin}"
    done

    # Create systemd service for kubelet. This is needed for manually downloaded kubelet.
    log "Creating systemd service for kubelet..."
    cat >/etc/systemd/system/kubelet.service <<'EOF'
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=https://kubernetes.io/docs/
After=network.target

[Service]
ExecStart=/usr/bin/kubelet
Restart=always
StartLimitInterval=0
RestartSec=10
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
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
systemctl enable --now kubelet 2> >(while read -r l; do
    [[ "$l" =~ Created\ symlink ]] && echo "$l" || echo "$l" >&2
done)

# --------- kubeadm config and init ---------
K8S_VERSION_WITH_PATCH=$(kubeadm version -o short)
KUBEADM_CONFIG="/root/kubeadm-config.yaml"
POD_NETWORK_CIDR="192.168.0.0/16"   # Default for Calico; change if needed

log "Writing kubeadm configuration to ${KUBEADM_CONFIG} (Kubernetes ${K8S_VERSION_WITH_PATCH})"
cat > "${KUBEADM_CONFIG}" <<EOF
apiVersion: kubeadm.k8s.io/${KUBEADM_API_VERSION}
kind: ClusterConfiguration
kubernetesVersion: ${K8S_VERSION_WITH_PATCH}
controlPlaneEndpoint: ""    # optional: replace with VIP or FQDN if HA
networking:
  podSubnet: "${POD_NETWORK_CIDR}"
---
apiVersion: kubeproxy.config.k8s.io/${KUBEPROXY_API_VERSION}
kind: KubeProxyConfiguration
mode: "iptables"
EOF

log "Running kubeadm init (this may take a few minutes)..."
# kubeadm may error if required ports blocked or preflight fails. We let it run and fail explicitly.
kubeadm init --config="${KUBEADM_CONFIG}" --upload-certs || {
  err "kubeadm init failed. Inspect the output above. Exiting."
  exit 1
}

#kubeadm reset -f   # clean any partial state


log "Downloading Calico v${CALICO_VERSION} manifest..."
 wget -q -O ~/calico.yaml https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/calico.yaml
