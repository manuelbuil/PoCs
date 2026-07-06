#!/bin/bash
set -euo pipefail

apt update
apt install -y qemu-kvm qemu-utils cpu-checker

# Enable KVM nested virtualization in the guest so Kata workloads can use HW acceleration.
cat <<EOF >/etc/modprobe.d/kvm-nested.conf
options kvm_intel nested=1
EOF

modprobe -r kvm_intel || true
modprobe kvm_intel nested=1 || true

if command -v virt-host-validate >/dev/null 2>&1; then
  virt-host-validate || true
fi

echo "Kata VM bootstrap complete"
