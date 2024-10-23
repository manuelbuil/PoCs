#!/bin/bash

apt update

cat <<EOF > config.yaml
server: "https://terraform-mbuil-vm1:9345"
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
