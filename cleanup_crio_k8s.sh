
rm -f install.out install.err
################### clean up K8s #################
dnf remove -y kubeadm kubectl kubelet
rm -f /root/kubeadm-config.yaml
rm -f /etc/yum.repos.d/kubernetes.repo
rm -f /usr/local/bin/kubeadm
rm -f /usr/local/bin/kubectl
rm -f /usr/local/bin/kubelet
rm -f /etc/systemd/system/kubelet.service
rm -f /etc/systemd/system/multi-user.target.wants/kubelet.service

########### clean up CRI-O #################
systemctl stop crio
systemctl disable crio
rm -rf /etc/crio
dnf remove -y cri-o
cd /etc/yum.repos.d/
rm -f devel:* isv:*
