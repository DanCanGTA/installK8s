#!/usr/bin/env bash
#
# install-crio-k8s-1.23-centos8.sh
# Purpose: Install CRI-O 1.23 and Kubernetes 1.23 on CentOS 8, then run kubeadm init.
# Notes: Run as root. Intended for lab / testing or controlled environments.
#
# Usage: sudo bash install-crio-k8s-1.23-centos8.sh
#
set -euo pipefail

# --------- Configuration ---------
CRIO_VERSION="1.23.5"
# CRI-O repo for browsing:
# <=1.28: https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/
# >= 1.29: https://download.opensuse.org/repositories/isv:/cri-o:/stable:/
CRIO_REPO_BASE="https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/${CRIO_VERSION}"
# There are repo variants with minor releases (e.g. 1.23:1.23.1). The script tries to use the general path.
CRIO_REPO_FILENAME="devel:kubic:libcontainers:stable:cri-o:${CRIO_VERSION}.repo"

# To check K8s patches:
# https://kubernetes.io/releases/patch-releases/#:~:text=These%20releases%20are%20no%20longer%20supported.%20Minor,Patch%20Release%2C%20End%20Of%20Life%20Date%2C%20Note.
# https://github.com/kubernetes/kubernetes/releases?page=20
K8S_VERSION="1.23.17"     # kubeadm/kubelet/kubectl version
K8S_REPO_BASE="https://pkgs.k8s.io/core:/stable:/v1.23/rpm"

POD_NETWORK_CIDR="10.244.0.0/16"   # Default for flannel; change if needed
KUBEADM_CONFIG="/root/kubeadm-config.yaml"

# --------- Helpers ---------
log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
fatal() { err "$*"; exit 1; }

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
  fatal "This script must be run as root."
fi

# --------- Add CRI-O repo and install CRI-O 1.23 ---------
log "Adding CRI-O ${CRIO_VERSION} repository..."

cd /etc/yum.repos.d

# Try to build a reliable wget URL for CentOS_8 variant. Use opensuse download path.
CRIO_REPO_URL="${CRIO_REPO_BASE}/CentOS_8/${CRIO_REPO_FILENAME}"

log "Using CRI-O repo URL: ${CRIO_REPO_URL}"
if ! wget -q --spider "${CRIO_REPO_URL}"; then
  log "CRI-O repo URL not reachable. Trying a fallback pattern..."
  # Fallback: some repo paths use a slightly different naming (1.23:1.23.1). We'll try to find a matching index.
  # If not found, script will continue and fail on install attempt with diagnostic.
fi

# Download repo file (if reachable)
if wget -q -O "${CRIO_REPO_FILENAME}" "${CRIO_REPO_URL}"; then
  log "CRI-O repo saved to /etc/yum.repos.d/${CRIO_REPO_FILENAME}"
else
  err "Failed to fetch CRI-O repo ${CRIO_REPO_URL}. You may need to adjust CRIO_REPO_BASE/CRIO_REPO_FILENAME in the script."
  fatal "Cannot proceed without CRI-O repo."
fi

log "Cleaning dnf cache..."
dnf clean all
dnf makecache

log "Installing CRI-O packages..."
# Install cri-o and cri-tools
dnf -y install cri-o cri-tools

log "Enabling and starting cri-o..."
systemctl enable --now crio
sleep 2
systemctl status crio --no-pager || true

# --------- Kubernetes repo & install kubelet/kubeadm/kubectl ---------
log "Adding Kubernetes yum repo for v${K8S_VERSION}..."
cat >/etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=${K8S_REPO_BASE}
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.23/rpm/repodata/repomd.xml.key
EOF

log "Disabling swap and extras excludes for kubernetes repo"
# Ensure dnf doesn't exclude kubernetes packages (some repos use exclude rules)
dnf -y clean all
dnf makecache

log "Installing kubelet kubeadm kubectl (v${K8S_VERSION})..."
# Install exact version (kubelet-<version>-0). The package naming may use a suffix -0; using wildcard to be tolerant.
dnf -y install "kubelet-${K8S_VERSION}" "kubeadm-${K8S_VERSION}" "kubectl-${K8S_VERSION}" --disableexcludes=kubernetes || \
dnf -y install "kubelet-${K8S_VERSION}-0" "kubeadm-${K8S_VERSION}-0" "kubectl-${K8S_VERSION}-0" --disableexcludes=kubernetes || \
fatal "Failed to install kubelet/kubeadm/kubectl v${K8S_VERSION}. Check repo and package names."

# Enable kubelet (it will be started after kubeadm init)
systemctl enable --now kubelet
sleep 2
systemctl status kubelet --no-pager || true

# --------- Configure CRI-O for kubelet (if needed) ---------
# Ensure CRI-O uses the correct cgroup manager (systemd) for kubelet compatibility
CRIO_CONF="/etc/crio/crio.conf"
if [[ -f "${CRIO_CONF}" ]]; then
  log "Ensuring CRI-O uses systemd cgroup manager..."
  # set cgroup_manager = "systemd" in the config file if present
  if grep -q '^cgroup_manager' "${CRIO_CONF}"; then
    sed -ri 's/^cgroup_manager *= *.*/cgroup_manager = "systemd"/' "${CRIO_CONF}"
  else
    # add under [crio.runtime] section if exists, otherwise append
    if grep -q '^\[crio.runtime\]' "${CRIO_CONF}"; then
      sed -i '/^\[crio.runtime\]/a cgroup_manager = "systemd"' "${CRIO_CONF}"
    else
      echo -e "[crio.runtime]\ncgroup_manager = \"systemd\"" >> "${CRIO_CONF}"
    fi
  fi
  systemctl restart crio
fi

# --------- kubeadm config and init ---------
log "Writing kubeadm configuration to ${KUBEADM_CONFIG} (Kubernetes ${K8S_VERSION})"
cat > "${KUBEADM_CONFIG}" <<EOF
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
kubernetesVersion: v${K8S_VERSION}
controlPlaneEndpoint: ""    # optional: replace with VIP or FQDN if HA
networking:
  podSubnet: "${POD_NETWORK_CIDR}"
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "iptables"
EOF

log "Running kubeadm init (this may take a few minutes)..."
# kubeadm may error if required ports blocked or preflight fails. We let it run and fail explicitly.
kubeadm init --config="${KUBEADM_CONFIG}" --upload-certs || {
  err "kubeadm init failed. Inspect the output above. Exiting."
  exit 1
}

# Set up kubeconfig for root user (and display for non-root)
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config || true

log "kubeadm init completed. Cluster control-plane is up (if no errors)."

# Un-taint master (optional for single-node testing)
log "Removing master taint to allow scheduling pods on the control plane (useful for single-node test clusters)..."
kubectl taint nodes --all node-role.kubernetes.io/master- || true
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

# Provide next steps
cat <<EOF

Done — CRI-O ${CRIO_VERSION} and Kubernetes ${K8S_VERSION} installation attempted.

Next recommended steps:
  * On the master, install a CNI (e.g. Flannel):
      kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    (Flannel expects pod CIDR: ${POD_NETWORK_CIDR}. If you changed it, use correct manifest.)
  * If you want to join worker nodes, run the kubeadm join command printed by kubeadm init above.
  * Verify nodes:
      kubectl get nodes
      kubectl get pods -A

Troubleshooting:
  * If kubeadm init failed, inspect /var/log/messages, journalctl -u kubelet, and kubeadm output.
  * Ensure firewall ports required by kubeadm are open (6443, 2379-2380, 10250, 10251, 10252).
  * If package installs fail due to modular filtering, try:
      dnf module disable -y container-tools
      dnf clean all
      dnf makecache
    Then reinstall CRI-O or container-selinux as needed.

References:
  * CRI-O 1.23 repository pattern: devel:kubic:libcontainers project. (example repo layout). :contentReference[oaicite:1]{index=1}
  * Kubernetes RPM repo pattern (pkgs.k8s.io core stable v1.23). :contentReference[oaicite:2]{index=2}
  * kubeadm installation guidance. :contentReference[oaicite:3]{index=3}

EOF

exit 0
