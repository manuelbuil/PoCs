#!/bin/sh
#K3SVERSION=v1.27.7+k3s1
apt update

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

cat <<EOF > config.yaml
write-kubeconfig-mode: 644
token: "secret"
EOF

mkdir -p /etc/rancher/k3s
cp config.yaml /etc/rancher/k3s/config.yaml

user=$(ls /home/)
mv config.yaml /home/${user}/config.yaml
chown ${user}:${user} /home/${user}/config.yaml
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL="latest" sh -
echo "alias k=kubectl" >> /home/${user}/.profile
