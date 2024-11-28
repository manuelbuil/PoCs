#!/bin/sh
apt update

# Little server for the other VM to find me
for i in 1 2; do echo "hola" | nc -l 43210; done &

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

cat <<EOF > config.yaml
write-kubeconfig-mode: 644
token: "secret"
cluster-cidr: 10.42.0.0/16,2001:cafe:42::/56
service-cidr: 10.43.0.0/16,2001:cafe:43::/112
# curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL="latest" sh -
EOF

mkdir -p /etc/rancher/k3s
cp config.yaml /etc/rancher/k3s/config.yaml

user=$(ls /home/)
mv config.yaml /home/${user}/config.yaml
chown ${user}:${user} /home/${user}/config.yaml
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL="latest" sh -

echo "alias k=kubectl" >> /home/${user}/.profile

# Add the typical manifests
wget https://raw.githubusercontent.com/manuelbuil/PoCs/main/2023/windows-deployment.yml
wget https://raw.githubusercontent.com/manuelbuil/PoCs/main/2021/multitool.yaml
wget https://raw.githubusercontent.com/manuelbuil/PoCs/main/2021/httpbin.yaml
mv windows-deployment.yml multitool.yaml httpbin.yaml /home/${user}/

# Change the owner of all files in /home/azureuser/
find /home/${user}/ -type f -exec chown ${user}:${user} {} \;