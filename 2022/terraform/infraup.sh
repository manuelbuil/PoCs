#!/bin/sh
set +x

RKECLUSTERFILE="/home/manuel/rke-cluster1/cluster.yml"
RKECLUSTERSTATEFILE="/home/manuel/rke-cluster1/cluster.rkestate"

# changeSshConfig adds the publicIP of the new VMs to ~/.ssh/config
changeSshConfig () {
case $1 in
  "azure")
    case $2 in
      "HA")
        ip0=$(terraform output -json | jq '.ipAddresses.value[0]')
        ip1=$(terraform output -json | jq '.ipAddresses.value[1]')
        ip2=$(terraform output -json | jq '.ipAddresses.value[2]')
        ip3=$(terraform output -json | jq '.ipAddresses.value[3]')
        ip4=$(terraform output -json | jq '.ipAddresses.value[4]')
        echo $ip0
        echo $ip1
        echo $ip2
        echo $ip3
        echo $ip4
        sed -i '/^Host azure-ubuntu/{n;s/Hostname .*/Hostname '$ip0'/}' ~/.ssh/config
        sed -i '/^Host azure-ubuntu2/{n;s/Hostname .*/Hostname '$ip1'/}' ~/.ssh/config
        sed -i '/^Host azure-ubuntu3/{n;s/Hostname .*/Hostname '$ip2'/}' ~/.ssh/config
        sed -i '/^Host azure-ubuntu4/{n;s/Hostname .*/Hostname '$ip3'/}' ~/.ssh/config
        sed -i '/^Host azure-ubuntu5/{n;s/Hostname .*/Hostname '$ip4'/}' ~/.ssh/config
      ;;
      *)
        ip0=$(terraform output -json | jq '.ipAddresses.value[0]')
        ip1=$(terraform output -json | jq '.ipAddresses.value[1]')
        ip2=$(terraform output -json | jq '.ipAddresses.value[2]')
        sed -i '/^Host azure-ubuntu/{n;s/Hostname .*/Hostname '$ip0'/}' ~/.ssh/config
        sed -i '/^Host azure-ubuntu2/{n;s/Hostname .*/Hostname '$ip1'/}' ~/.ssh/config
        sed -i '/^Host azure-ubuntu3/{n;s/Hostname .*/Hostname '$ip2'/}' ~/.ssh/config
        sed -i '/^Host azure-windows/{n;s/Hostname .*/Hostname '$ip2'/}' ~/.ssh/config
    esac
  ;;
  "aws")
    ipv6=$(terraform output -json | jq '.ipv6IP.value[0]')
    ipv4jump=$(terraform output -json | jq '.publicIP.value')
    ipv4public1=$(terraform output -json | jq '.publicIP.value[0]')
    ipv4public2=$(terraform output -json | jq '.publicIP.value[1]')
    ipv4public3=$(terraform output -json | jq '.publicIP.value[2]')
    ipv4public4=$(terraform output -json | jq '.publicIP.value[3]')
    ipv4public5=$(terraform output -json | jq '.publicIP.value[4]')
    sed -i '/^Host aws-ubuntu/{n;s/Hostname .*/Hostname '$ipv4public1'/}' ~/.ssh/config
    sed -i '/^Host aws-ubuntu2/{n;s/Hostname .*/Hostname '$ipv4public2'/}' ~/.ssh/config
    sed -i '/^Host aws-ubuntu3/{n;s/Hostname .*/Hostname '$ipv4public3'/}' ~/.ssh/config
    sed -i '/^Host aws-ubuntu4/{n;s/Hostname .*/Hostname '$ipv4public4'/}' ~/.ssh/config
    sed -i '/^Host aws-ubuntu5/{n;s/Hostname .*/Hostname '$ipv4public5'/}' ~/.ssh/config
    sed -i '/^Host aws-suse/{n;s/Hostname .*/Hostname '$ipv4public1'/}' ~/.ssh/config
    sed -i '/^Host aws-suse2/{n;s/Hostname .*/Hostname '$ipv4public2'/}' ~/.ssh/config
    sed -i '/^Host aws-suse3/{n;s/Hostname .*/Hostname '$ipv4public3'/}' ~/.ssh/config
  ;;
  *)
    echo "Something went wrong in the ssh"
    exit 1
esac
}

# updaterke1cluster updates the addresses of the rke1 cluster
updaterke1cluster() {
  pushd $1
  ipPublic0=$(terraform output -json | jq '.ipAddresses.value[0]')
  ipPublic1=$(terraform output -json | jq '.ipAddresses.value[1]')
  ipPrivate0=$(terraform output -json | jq '.ipPrivateAddresses.value[0]')
  ipPrivate1=$(terraform output -json | jq '.ipPrivateAddresses.value[1]')
  sed -i '4s/.*/- address: '${ipPublic0}'/' ${RKECLUSTERFILE}
  sed -i '5s/.*/  internal_address: '${ipPrivate0}'/' ${RKECLUSTERFILE}
  sed -i '12s/.*/- address: '${ipPublic1}'/' ${RKECLUSTERFILE}
  sed -i '13s/.*/  internal_address: '${ipPrivate1}'/' ${RKECLUSTERFILE}
  rm ${RKECLUSTERSTATEFILE}
  popd
}

# applyTerraform runs terraform apply and refresh to get the publicIP of the new VMs
applyTerraform () {
pushd $1
terraform apply --auto-approve
sleep 10
terraform refresh
sleep 5
changeSshConfig $1 $2
popd
}


case $1 in
  "rke1")
    echo "rke1 option"
    cp azure/template/azure.tf.template azure/azure.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installDockerHelm.sh"/g' azure/azure.tf
    sed -i 's/%COUNT%/2/g' azure/azure.tf
    applyTerraform azure
    updaterke1cluster azure
  ;;
  "rancher")
    echo "rancher option"
    cp azure/template/azure.tf.template azure/azure.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installK3sAndRancher_${count.index}.sh"/g' azure/azure.tf
    sed -i 's/%COUNT%/2/g' azure/azure.tf
    applyTerraform azure
    echo "Access ${ip0//\"/}.sslip.io in your browser"
  ;;
  "rancher-aws")
    echo "rancher-aws option"
    cp aws/template/aws.tf.template aws/aws.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installK3sAndRancher_${count.index}.sh"/g' aws/aws.tf
    sed -i 's/%COUNT%/2/g' aws/aws.tf
    applyTerraform aws
    echo "Access ${ipv4public1//\"/}.sslip.io in your browser"
  ;;
  "rancher-prime")
    echo "rancher prime option"
    cp azure/template/azure.tf.template azure/azure.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installK3sAndRancherPrime_${count.index}.sh"/g' azure/azure.tf
    sed -i 's/%COUNT%/2/g' azure/azure.tf
    applyTerraform azure
    echo "Access ${ip0//\"/}.sslip.io in your browser"
  ;;
  "rancher-prime-aws")
    echo "rancher prime option"
    cp aws/template/aws.tf.template aws/aws.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installK3sAndRancherPrime_${count.index}.sh"/g' aws/aws.tf
    sed -i 's/%COUNT%/2/g' aws/aws.tf
    applyTerraform aws
    echo "Access ${ipv4public1//\"/}.sslip.io in your browser"
  ;;
  "k3s")
    echo "k3s option"
    cp azure/template/azure.tf.template azure/azure.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installK3s_${count.index}.sh"/g' azure/azure.tf
    sed -i 's/%COUNT%/3/g' azure/azure.tf
    applyTerraform azure
  ;;
  "k3s-aws")
    echo "k3s option"
    cp aws/template/aws.tf.template aws/aws.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installK3s_${count.index}.sh"/g' aws/aws.tf
    sed -i 's/%COUNT%/3/g' aws/aws.tf
    applyTerraform aws
  ;;
  "k3s-ipv6")
    echo "k3s-ipv6 option"
    cp aws/template/aws.tf.template aws/aws.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installK3snoDS.sh"/g' aws/aws.tf
    applyTerraform aws
  ;;
  "rke2")
    echo "rke2 option with cni plugin $2"
    case $2 in
      ""|"canal")
        echo "CNI plugin is canal"
	cniPlugin=canal
      ;;
      "calico")
        echo "CNI plugin is calico"
	cniPlugin=calico
      ;;
      "cilium")
        echo "CNI plugin is cilium"
	cniPlugin=cilium
      ;;
      "flannel")
        echo "CNI plugin is flannel"
	cniPlugin=flannel
      ;;
      *)
        echo "$2 is not a valid CNI plugin"
	exit 1 
      ;;
    esac
    if [ "$3" == "multus" ];then
	    echo "Multus included!"
	    cniPlugin="$3,${cniPlugin}"
    fi
    sed -i "s/cni: .*/cni: ${cniPlugin}/g" cloud-init-scripts\/installRKE2_0.sh
    cp aws/template/aws.tf.template aws/aws.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installRKE2_${count.index}.sh"/g' aws/aws.tf
    sed -i 's/%COUNT%/2/g' aws/aws.tf
    applyTerraform aws
  ;;
  "windows")
    echo "rke2 and windows with cni plugin $2"
    case $2 in
      ""|"calico")
        echo "CNI plugin is calico"
        cniPlugin=calico
      ;;
      "flannel")
        echo "CNI plugin is flannel"
        cniPlugin=flannel
      ;;
      *)
        echo "$2 is not a valid CNI plugin"
        exit 1
      ;;
    esac
    cp azure/template/azure.tf.windows.template azure/azure.tf
    sed -i "s/cni: .*/cni: ${cniPlugin}/g" cloud-init-scripts\/installRKE2NoDS_0.sh
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installRKE2NoDS_${count.index}.sh"/g' azure/azure.tf
    applyTerraform azure
    echo "ssh azure-windows 'powershell.exe -File C:\AzureData\install.ps1 MYIP'"
    echo "ssh azure-windows 'powershell.exe C:\usr\local\bin\rke2.exe agent service --add'"
    echo "ssh azure-windows 'powershell.exe Start-Service -Name rke2'"
  ;;
  "rke2-ha")
    echo "rke2 in HA mode"
    cp aws/template/aws.tf.template aws/aws.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installRKE2HA_${count.index}.sh"/g' aws/aws.tf
    sed -i 's/%COUNT%/5/g' aws/aws.tf
    applyTerraform aws HA
  ;;
  "demo-gpu")
    echo "demo-gpu"
    cp aws/template/aws-demo.tf.template aws/aws.tf
    applyTerraform aws
  ;;
  *)
    echo "$0 executed without arg. Please use rke1, rancher, rancher-prime, k3s, k3s-ipv6, rke2 or windows"
    exit 1
esac
