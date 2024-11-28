#!/bin/bash
apt update

wget https://raw.githubusercontent.com/manuelbuil/PoCs/refs/heads/main/2022/terraform/cloud-init-scripts/utils.sh -O /tmp/utils.sh

source /tmp/utils.sh

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# The other created VM has the next or the previous IP. Ping to check which one is it
myIP=$(ip addr show $(ip route | awk '/default/ { print $5 }') | grep "inet" | head -n 1 | awk '/inet/ {print $2}' | cut -d'/' -f1)
echo This my myIP: ${myIP}

result=$(getServerIP ${myIP})

cat <<EOF > config.yaml
server: "https://${result}:9345"
write-kubeconfig-mode: 644
token: "secret"
cluster-cidr: 10.42.0.0/16,2001:cafe:42::/56
service-cidr: 10.43.0.0/16,2001:cafe:43::/112
cni: canal
# curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_CHANNEL="latest" sh -
EOF

mkdir -p /etc/rancher/rke2
cp config.yaml /etc/rancher/rke2/config.yaml

user=$(ls /home/)
mv config.yaml /home/${user}/config.yaml
chown ${user}:${user} /home/${user}/config.yaml
curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL="latest" sh -
systemctl enable --now rke2-server

echo "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml" >> /home/${user}/.profile
echo "export PATH=$PATH:/var/lib/rancher/rke2/bin/" >> /home/${user}/.profile
echo "alias k=kubectl" >> /home/${user}/.profile

# Add the typical manifests
wget https://raw.githubusercontent.com/manuelbuil/PoCs/main/2023/windows-deployment.yml
wget https://raw.githubusercontent.com/manuelbuil/PoCs/main/2021/multitool.yaml
wget https://raw.githubusercontent.com/manuelbuil/PoCs/main/2021/httpbin.yaml
mv windows-deployment.yml multitool.yaml httpbin.yaml /home/${user}/

# Change the owner of all files
find /home/${user}/ -type f -exec chown ${user}:${user} {} \;
