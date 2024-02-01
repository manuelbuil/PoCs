#!/bin/sh
set +x

RKECLUSTERFILE="/home/manuel/rke-cluster1/cluster.yml"
RKECLUSTERSTATEFILE="/home/manuel/rke-cluster1/cluster.rkestate"

# changeSshConfig adds the publicIP of the new VMs to ~/.ssh/config
changeSshConfig () {
case $1 in
  "azure")
    ip0=$(terraform output -json | jq '.ipAddresses.value[0]')
    ip1=$(terraform output -json | jq '.ipAddresses.value[1]')
    echo $ip0
    echo $ip1
    sed -i '/^Host azure-ubuntu/{n;s/Hostname .*/Hostname '$ip0'/}' ~/.ssh/config
    sed -i '/^Host azure-ubuntu2/{n;s/Hostname .*/Hostname '$ip1'/}' ~/.ssh/config
  ;;
  "aws")
    ipv6=$(terraform output -json | jq '.ipv6IP.value[0]')
    ipv4jump=$(terraform output -json | jq '.publicIP.value')
    echo $ipv6
    echo $ipv4jump
    sed -i '/^Host aws-ubuntu/{n;s/Hostname .*/Hostname '$ipv4jump'/}' ~/.ssh/config
    sed -i '/^Host aws-ubuntu2/{n;s/Hostname .*/Hostname '$ipv6'/}' ~/.ssh/config
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
changeSshConfig $1
popd
}

cp azure/template/azure.tf.template azure/azure.tf
cp aws/template/aws.tf.template aws/aws.tf

case $1 in
  "rke1")
    echo "rke1 option"
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installDockerHelm.sh"/g' azure/azure.tf
    sed -i 's/%COUNT%/2/g' azure/azure.tf
    applyTerraform azure
    updaterke1cluster azure
  ;;
  "rancher")
    echo "rancher option"
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installK3sAndRancher.sh"/g' azure/azure.tf
    sed -i 's/%COUNT%/1/g' azure/azure.tf
    applyTerraform azure
  ;;
  "k3s")
    echo "k3s option"
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installK3s${count.index}.sh"/g' azure/azure.tf
    sed -i 's/%COUNT%/2/g' azure/azure.tf
    applyTerraform azure
  ;;
  "k3s-ipv6")
    echo "k3s-ipv6 option"
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
      *)
        echo "$2 is not a valid CNI plugin"
	exit 1 
      ;;
    esac
    sed -i "s/cni: .*/cni: ${cniPlugin}/g" cloud-init-scripts\/installRKE2_0.sh
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installRKE2_${count.index}.sh"/g' azure/azure.tf
    sed -i 's/%COUNT%/2/g' azure/azure.tf
    applyTerraform azure
  ;;
  *)
    echo "$0 executed without arg"
    exit 1
esac
