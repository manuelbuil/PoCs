#!/bin/bash

apt update

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

cat <<EOF > config.yaml
server: "https://terraform-mbuil-vm0:6443"
token: "secret"
# curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL="latest" K3S_URL=https://terraform-mbuil-vm0:6443 K3S_TOKEN=secret sh -
EOF

mkdir -p /etc/rancher/k3s
cp config.yaml /etc/rancher/k3s/config.yaml
user=$(ls /home/)
mv config.yaml /home/${user}/config.yaml
chown ${user}:${user} /home/${user}/config.yaml

curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL="latest" K3S_URL=https://terraform-mbuil-vm0:6443 K3S_TOKEN=secret sh -
