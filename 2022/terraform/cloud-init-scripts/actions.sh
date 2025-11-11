#!/bin/bash

zypper_up_ref() {
  zypper ref
  zypper up -y
}

apt_update() {
  apt update
}

apt_install() {
  apt install -y $1
}

download_manifests() {
  USER=$(ls /home/)
  wget https://raw.githubusercontent.com/manuelbuil/PoCs/main/2023/windows-deployment.yml
  wget https://raw.githubusercontent.com/manuelbuil/PoCs/main/2021/multitool.yaml
  wget https://raw.githubusercontent.com/manuelbuil/PoCs/main/2021/httpbin.yaml
  mv windows-deployment.yml multitool.yaml httpbin.yaml /home/$USER/
  find /home/$USER/ -type f -exec chown $USER:$USER {} \;
}

helm_install() {
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

set_env_variables() {
  USER=$(ls /home/)
  echo "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml" >> /home/$USER/.profile
  echo "export PATH=$PATH:/var/lib/rancher/rke2/bin/" >> /home/$USER/.profile
  echo "alias k=kubectl" >> /home/$USER/.profile
  source /home/$USER/.profile
}

zypper_install() {
  zypper install -y $1
}

reboot() {
  reboot
}

docker_config() {
  usermod -aG docker azureuser
  echo
  cat /etc/group | grep docker
  echo
}

zypper_cuda() {
  zypper addrepo --refresh https://developer.download.nvidia.com/compute/cuda/repos/sles15/x86_64/ cuda-sles15
  zypper --gpg-auto-import-keys refresh
  zypper remove -y nvidia-open-driver-G06-signed-cuda-kmp-default
  zypper install -y --auto-agree-with-licenses nvidia-gl-G06 nvidia-video-G06 nvidia-compute-utils-G06
}

nc_server() {
  # Little server for the other VM to find me
  for i in 1 2; do echo "hola" | nc -l 43210; done &
}

download_k3s_server() {
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
}