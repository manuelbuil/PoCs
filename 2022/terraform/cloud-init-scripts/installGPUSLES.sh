#!/bin/bash
#zypper ref
#zypper up -y
#zypper addrepo --refresh https://developer.download.nvidia.com/compute/cuda/repos/sles15/x86_64/ cuda-sles15
#zypper --gpg-auto-import-keys refresh
#zypper remove -y nvidia-open-driver-G06-signed-cuda-kmp-default
#zypper install -y --auto-agree-with-licenses nvidia-gl-G06==570.172.08-1 nvidia-video-G06==570.172.08-1 nvidia-compute-utils-G06==570.172.08-1

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

if [ -f /etc/os-release ]; then
    # Source the file to load its variables (like $ID)
    . /etc/os-release

    case "$ID" in
        ubuntu)
            echo "Detected Ubuntu. Running 'apt update'..."
            apt update
            ;;
        sles)
            echo "Detected SLES. Running 'zypper ref'..."
            zypper ref
            zypper up
            ;;
        *)
            echo "Unsupported OS ID: $ID"
            ;;
    esac
else
    echo "Error: Cannot detect OS (Missing /etc/os-release)"
    exit 1
fi

wget https://raw.githubusercontent.com/manuelbuil/PoCs/refs/heads/main/2022/terraform/cloud-init-scripts/utils.sh -O /tmp/utils.sh

source /tmp/utils.sh

# The other created VM has the next or the previous IP. Ping to check which one is it
myIP=$(ip addr show $(ip route | awk '/default/ { print $5 }') | grep "inet" | head -n 1 | awk '/inet/ {print $2}' | cut -d'/' -f1)
echo This my myIP: ${myIP}

result=$(getServerIP ${myIP})

cat <<EOF > config.yaml
server: "https://${result}:9345"
token: "secret"
# curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_CHANNEL="latest" INSTALL_RKE2_TYPE="agent" sh -
EOF

mkdir -p /etc/rancher/rke2
cp config.yaml /etc/rancher/rke2/config.yaml
user=$(ls /home/)
mv config.yaml /home/${user}/config.yaml
chown ${user}:${user} /home/${user}/config.yaml

curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL="latest" INSTALL_RKE2_TYPE="agent" sh -
systemctl enable --now rke2-agent