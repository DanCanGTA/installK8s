dnf -y update
dnf install -y $(cat basicPackages)
swapoff -a
sed -i '/swap/d' /etc/fstab

#lsmod | egrep 'overlay|br_netfilter'
tee /etc/modules-load.d/kubernetes.conf <<EOF
overlay
br_netfilter
EOF

#sysctl net.bridge.bridge-nf-call-ip6tables
#sysctl net.bridge.bridge-nf-call-iptables
#sysctl net.ipv4.ip_forward

tee /etc/sysctl.d/kubernetes.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system
