#!/bin/bash
if [ -f /etc/os-release ]; then
    # Source the file to load its variables (like $ID)
    . /etc/os-release

    case "$ID" in
        ubuntu)
            echo "Detected Ubuntu. Running 'apt update'..."
            apt update
            ;;
        sles)
            echo "Detected SLES. Running 'zypper ref'..."
            zypper ref
            zypper up
            ;;
        *)
            echo "Unsupported OS ID: $ID"
            ;;
    esac
else
    echo "Error: Cannot detect OS (Missing /etc/os-release)"
    exit 1
fi



curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
# This instance is only up to be used as a custom VM to install rke2/k3s with rancher
