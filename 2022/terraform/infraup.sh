#!/bin/sh
set +x

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
  *)
    echo "$0 executed without arg"
    exit 1
esac
