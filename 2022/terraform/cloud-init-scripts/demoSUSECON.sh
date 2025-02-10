#!/bin/bash
zypper ref
zypper up -y
zypper install -y jq

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

user=$(ls /home/)
echo "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml" >> /home/${user}/.profile
echo "export PATH=$PATH:/var/lib/rancher/rke2/bin/" >> /home/${user}/.profile
echo "alias k=kubectl" >> /home/${user}/.profile

reboot