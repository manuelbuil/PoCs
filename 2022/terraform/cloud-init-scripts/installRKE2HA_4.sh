#!/bin/bash

apt update

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
