#!/bin/sh
RKE2VERSION=v1.28.4+rke2r1
apt update

# Little server for the other VM to find me
echo "hola" | nc -l 43210 &

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

cat <<EOF > config.yaml
write-kubeconfig-mode: 644
token: "secret"
cluster-cidr: 10.42.0.0/16,2001:cafe:42::/56
service-cidr: 10.43.0.0/16,2001:cafe:43::/112
cni: canal
# curl -sfL https://get.rke2.io | sudo sh -
EOF

mkdir -p /etc/rancher/rke2
cp config.yaml /etc/rancher/rke2/config.yaml

user=$(ls /home/)
mv config.yaml /home/${user}/config.yaml
chown ${user}:${user} /home/${user}/config.yaml
curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL="latest" sh -
systemctl enable --now rke2-server
echo "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml" >> /home/azureuser/.profile
echo "export PATH=$PATH:/var/lib/rancher/rke2/bin/" >> /home/azureuser/.profile
echo "alias k=kubectl" >> /home/azureuser/.profile
