systemctl stop crio
systemctl disable crio
dnf remove -y cri-o
cd /etc/yum.repos.d/
rm -f devel:* isv:*
