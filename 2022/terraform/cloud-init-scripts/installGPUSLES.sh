#!/bin/bash
zypper ref
zypper up -y
zypper addrepo --refresh https://developer.download.nvidia.com/compute/cuda/repos/sles15/x86_64/ cuda-sles15
zypper --gpg-auto-import-keys refresh
zypper remove -y nvidia-open-driver-G06-signed-cuda-kmp-default
zypper install -y --auto-agree-with-licenses nvidia-gl-G06 nvidia-video-G06 nvidia-compute-utils-G06

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

reboot