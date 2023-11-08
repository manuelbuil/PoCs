#!/bin/sh
K3SVERSION=v1.27.6+k3s1
apt update

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

cat <<EOF > config.yaml
write-kubeconfig-mode: 644
token: "secret"
cluster-cidr: 10.42.0.0/16,2001:cafe:42:0::/56
service-cidr: 10.43.0.0/16,2001:cafe:42:1::/112
EOF

mkdir -p /etc/rancher/k3s
cp config.yaml /etc/rancher/k3s/config.yaml
mv config.yaml /home/azureuser/config.yaml
chown azureuser:azureuser /home/azureuser/config.yaml
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${K3SVERSION} sh -
