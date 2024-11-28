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
server: "https://${result}:6443"
token: "secret"
# curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL="latest" K3S_URL=https://${result}:6443 K3S_TOKEN=secret sh -
EOF

mkdir -p /etc/rancher/k3s
cp config.yaml /etc/rancher/k3s/config.yaml
user=$(ls /home/)
mv config.yaml /home/${user}/config.yaml
chown ${user}:${user} /home/${user}/config.yaml

curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL="latest" K3S_URL=https://${result}:6443 K3S_TOKEN=secret sh -
