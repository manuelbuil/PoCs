#!/bin/sh
set +x

# changeSshConfig adds the publicIP of the new VMs to ~/.ssh/config
changeSshConfig () {
ip0=$(terraform output -json | jq '.ipAddresses.value[0]')
ip1=$(terraform output -json | jq '.ipAddresses.value[1]')

echo $ip0
echo $ip1

sed -i '/^Host azure-ubuntu/{n;s/Hostname .*/Hostname '$ip0'/}' ~/.ssh/config
sed -i '/^Host azure-ubuntu2/{n;s/Hostname .*/Hostname '$ip1'/}' ~/.ssh/config
}


cp template/azure-new.tf.template azure-new.tf

case $1 in
  "rke1")
    echo "rke1 option"
    sed -i 's/%CLOUDINIT%/"installDockerHelm.sh"/g' azure-new.tf
    sed -i 's/%COUNT%/2/g' azure-new.tf
  ;;
  "rancher")
    echo "k3s option"
    sed -i 's/%CLOUDINIT%/"installK3sAndRancher.sh"/g' azure-new.tf
    sed -i 's/%COUNT%/2/g' azure-new.tf
  ;;
  *)
    echo "$0 executed without arg"
    exit 1
esac

terraform apply --auto-approve
sleep 10
terraform refresh
sleep 5
changeSshConfig
