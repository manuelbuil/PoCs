#!/bin/bash
apt update
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
# This instance is only up to be used as a custom VM to install rke2/k3s with rancher
