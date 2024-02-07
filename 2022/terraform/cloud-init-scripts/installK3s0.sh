#!/bin/sh
K3SVERSION=v1.28.4+k3s1
apt update

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

cat <<EOF > config.yaml
write-kubeconfig-mode: 644
token: "secret"
cluster-cidr: 10.42.0.0/16,2001:cafe:42::/56
service-cidr: 10.43.0.0/16,2001:cafe:43::/112
# curl -sfL https://get.k3s.io | sh -
EOF

mkdir -p /etc/rancher/k3s
cp config.yaml /etc/rancher/k3s/config.yaml

user=$(ls /home/)
mv config.yaml /home/${user}/config.yaml
chown ${user}:${user} /home/azureuser/config.yaml
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${K3SVERSION} sh -
