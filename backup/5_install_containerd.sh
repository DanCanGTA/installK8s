#!/bin/bash

# Run check script first to get current status
eval "$(/root/installK8s/05_install_containerd_check.sh --outputToInstall)"

# Install containerd if not installed
if [ "$containerd_installed" = false ]; then
    echo "Installing containerd..."
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    dnf install -y containerd.io

    # Create default containerd configuration
    mkdir -p /etc/containerd
    containerd config default | tee /etc/containerd/config.toml
    
    # Update containerd configuration to use systemd cgroup driver
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
fi

# Enable and start service if not enabled or not running
if [ "$containerd_enabled" = false ]; then
    echo "Enabling containerd service..."
    systemctl enable containerd
fi

if [ "$containerd_running" = false ]; then
    echo "Starting containerd service..."
    systemctl restart containerd
fi

echo "Service containerd is installed."
echo "Service status:"
systemctl status containerd