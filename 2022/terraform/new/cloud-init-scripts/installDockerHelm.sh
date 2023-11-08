#!/bin/sh
apt update
apt -y install docker.io
usermod -aG docker azureuser
echo
cat /etc/group | grep docker
echo
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
