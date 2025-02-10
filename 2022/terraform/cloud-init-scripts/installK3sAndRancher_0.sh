#!/bin/sh
apt update

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

myIP=$(curl -4 ifconfig.me)
cat <<EOF > config.yaml
write-kubeconfig-mode: 644
token: "secret"
# Use https://${myIP}.sslip.io/
EOF

mkdir -p /etc/rancher/k3s
cp config.yaml /etc/rancher/k3s/config.yaml
user=$(ls /home/)
mv config.yaml /home/${user}/config.yaml
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.30.4+k3s1 sh -
sleep 30
echo "alias k=kubectl" >> /home/${user}/.profile
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
kubectl create namespace cattle-system
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.3/cert-manager.crds.yaml
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace
sleep 20
helm install rancher rancher-latest/rancher --namespace cattle-system --set hostname=$myIP.sslip.io --set replicas=1 --set bootstrapPassword=linux
