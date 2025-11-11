#!/bin/sh
set +x

RKECLUSTERFILE="/home/manuel/rke-cluster1/cluster.yml"
RKECLUSTERSTATEFILE="/home/manuel/rke-cluster1/cluster.rkestate"

# Default values for parameters
K8S_DISTRO=""
CNI_PLUGIN="canal" # Default CNI plugin for RKE2, if not specified
OS_TYPE="ubuntu"   # Default OS type
MULTUS_ENABLED="false" # Default to Multus disabled

changeSshConfig () {
local cloud_provider="$1" # e.g., "azure" or "aws"
local vm_config_type="$2" # e.g., "HA" for azure, or OS_TYPE for aws

case "$cloud_provider" in
  "azure")
    local ip_addresses
    local base_hostname_prefix

    # Determine the number of IPs and the base hostname prefix based on vm_config_type
    case "$vm_config_type" in
      "HA")
        echo "Updating SSH config for Azure HA setup (5 VMs)"
        # Use jq to get all values from the array directly as a space-separated string
        ip_addresses=$(terraform output -json | jq -r '.ipAddresses.value[]')
        base_hostname_prefix="azure-ubuntu"
      ;;
      "windows")
        echo "Updating SSH config for Azure Windows setup (Ubuntu controller + Windows node)"
        # Get specific IPs for the Windows scenario
        ip_addresses[0]=$(terraform output -json | jq -r '.ipAddresses.value[0]') # Assuming controller
        ip_addresses[1]=$(terraform output -json | jq -r '.ipAddresses.value[1]') # Assuming worker 1 (Windows)
        # Handle the specific sed commands for Windows and its controller
        sed -i "/^Host azure-ubuntu/{n;s/Hostname .*/Hostname ${ip_addresses[0]}/}" ~/.ssh/config
        sed -i "/^Host azure-windows/{n;s/Hostname .*/Hostname ${ip_addresses[1]}/}" ~/.ssh/config
        echo "Updated Host azure-ubuntu with ${ip_addresses[0]}"
        echo "Updated Host azure-windows with ${ip_addresses[1]}"
        return 0 # Exit function early as Windows case is special
      ;;
      *)
        echo "Updating SSH config for Azure default setup (3 VMs)"
        # Default Azure setup (e.g., rke1, rancher, k3s with 2-3 nodes)
        ip_addresses=$(terraform output -json | jq -r '.ipAddresses.value[]')
        base_hostname_prefix="azure-ubuntu"
      ;;
    esac

    local i=1
    for ip in $ip_addresses; do
      local host_entry="${base_hostname_prefix}"
      if [ "$i" -gt 1 ]; then
        host_entry="${host_entry}${i}"
      fi
      echo "Updating Host $host_entry with IP $ip"
      sed -i "/^Host $host_entry/{n;s/Hostname .*/Hostname $ip/}" ~/.ssh/config
      i=$((i+1))
    done
  ;; 

  "aws")
    local public_ips
    public_ips=$(terraform output -json | jq -r '.publicIP.value[]')

    local os_prefix
    case "$vm_config_type" in
      "ubuntu")
        os_prefix="ubuntu"
      ;;
      "sles")
        os_prefix="suse"
      ;;
      "rhel")
        os_prefix="rhel"
      ;;
      *)
        echo "Error: Unknown OS type for AWS in changeSshConfig: $vm_config_type"
        exit 1
      ;;
    esac

    local i=1
    for ip in $public_ips; do
      local host_entry="aws-${os_prefix}"
      if [ "$i" -gt 1 ]; then
        host_entry="${host_entry}${i}"
      fi
      echo "Updating Host $host_entry with IP $ip"
      sed -i "/^Host $host_entry/{n;s/Hostname .*/Hostname $ip/}" ~/.ssh/config
      i=$((i+1))
    done
  ;;
  *)
    echo "Something went wrong in the ssh config update for cloud provider: $cloud_provider"
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
# Determine the second argument for changeSshConfig based on the cloud provider and context
if [ "$1" = "aws" ]; then
    changeSshConfig "$1" "$OS_TYPE" # Pass the OS_TYPE for AWS
elif [ "$1" = "azure" ]; then
    # For Azure, we need to know if it's HA, Windows, or default
    # The '$2' from applyTerraform (e.g., 'HA') is passed as vm_config_type
    # If no $2, it falls into the default Azure case in changeSshConfig
    changeSshConfig "$1" "$2"
else
    echo "Error: Unhandled cloud provider in applyTerraform: $1"
    exit 1
fi
ipv4public1=$(terraform output -json | jq -r '.ipAddresses.value[0]')
popd
}

# Function to display usage
usage() {
  echo "Usage: $0 --k8s=<rke1|rancher|rancher-prime|k3s|rke2|windows|demo-gpu> [--cni=<canal|calico|cilium|flannel>] [--os=<ubuntu|sles>] [--multus]"
  echo "  --k8s: Specify the Kubernetes distribution (required)."
  echo "  --cni: Specify the CNI plugin for RKE2 (default: canal)."
  echo "  --os: Specify the OS type (ubuntu or sles) for AWS AMIs (default: ubuntu)."
  echo "  --multus: Enable Multus CNI (flag, no value needed)."
  exit 1
}

# Parse named parameters
while [ "$#" -gt 0 ]; do
  case "$1" in
    --k8s=*)
      K8S_DISTRO="${1#*=}"
      ;;
    --cni=*)
      CNI_PLUGIN="${1#*=}"
      ;;
    --os=*)
      OS_TYPE="${1#*=}"
      ;;
    --multus)
      MULTUS_ENABLED="true"
      ;;
    *)
      echo "Unknown parameter: $1"
      usage
      ;;
  esac
  shift
done

# Validate K8S_DISTRO is set
if [ -z "$K8S_DISTRO" ]; then
  echo "Error: --k8s parameter is required."
  usage
fi

# Define AMIs based on OS_TYPE
case "$OS_TYPE" in
  "ubuntu")
    AMI_ID_AWS="ami-0bb457e0c5095fa9d" # Ubuntu AMI
    ;;
  "sles")
    AMI_ID_AWS="ami-0c517408a745b7297" # SLES AMI
    ;;
  "rhel")
    AMI_ID_AWS="ami-0c00c3951305c3894" # RHEL9 AMI
    ;;
  *)
    echo "Error: Invalid OS type: $OS_TYPE. Supported types are 'ubuntu' and 'sles'."
    exit 1
    ;;
esac

case "$K8S_DISTRO" in
  "rke1")
    echo "rke1 option"
    cp azure/template/azure.tf.template azure/azure.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installDockerHelm.sh"/g' azure/azure.tf
    sed -i 's/%COUNT%/2/g' azure/azure.tf
    applyTerraform azure ""
    updaterke1cluster azure
  ;;
  "rancher")
    echo "rancher option"
    cp azure/template/azure.tf.template azure/azure.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installK3sAndRancher_${count.index}.sh"/g' azure/azure.tf
    sed -i 's/%COUNT%/2/g' azure/azure.tf
    applyTerraform azure ""
    echo "Access ${ip0//\"/}.sslip.io in your browser"
  ;;
  "rancher-prime")
    echo "rancher prime option"
    cp azure/template/azure.tf.template azure/azure.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installK3sAndRancherPrime_${count.index}.sh"/g' azure/azure.tf
    sed -i 's/%COUNT%/2/g' azure/azure.tf
    applyTerraform azure ""
    echo "Access ${ip0//\"/}.sslip.io in your browser"
  ;;
  "k3s")
    echo "k3s option"
    cp azure/template/azure.tf.template azure/azure.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installK3s_${count.index}.sh"/g' azure/azure.tf
    sed -i 's/%COUNT%/3/g' azure/azure.tf
    applyTerraform azure ""
  ;;
  "windows")
    echo "rke2 and windows with cni plugin $CNI_PLUGIN"
    case "$CNI_PLUGIN" in
      "calico"|"flannel")
        # Valid CNI plugin for Windows
        ;;
      *)
        echo "Error: $CNI_PLUGIN is not a valid CNI plugin for Windows RKE2. Supported: calico, flannel."
        exit 1
        ;;
    esac
    cp azure/template/azure.tf.windows.template azure/azure.tf
    sed -i "s/cni: .*/cni: ${CNI_PLUGIN}/g" cloud-init-scripts\/installRKE2NoDS_0.sh
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installRKE2NoDS_${count.index}.sh"/g' azure/azure.tf
    applyTerraform azure "windows"
    echo "ssh azure-windows 'powershell.exe -File C:\AzureData\install.ps1 MYIP'"
    echo "ssh azure-windows 'powershell.exe C:\usr\local\bin\rke2.exe agent service --add'"
    echo "ssh azure-windows 'powershell.exe Start-Service -Name rke2'"
  ;;
  "rancher-aws")
    echo "rancher-aws option"
    cp aws/template/aws.tf.template aws/aws.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installK3sAndRancher_${count.index}.sh"/g' aws/aws.tf
    sed -i 's/%COUNT%/2/g' aws/aws.tf
    sed -i "s|%AMI%|$AMI_ID_AWS|g" aws/aws.tf
    applyTerraform aws
    echo "Access ${ipv4public1//\"/}.sslip.io in your browser"
  ;;
  "rancher-prime-aws")
    echo "rancher prime option"
    cp aws/template/aws.tf.template aws/aws.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installK3sAndRancherPrime_${count.index}.sh"/g' aws/aws.tf
    sed -i 's/%COUNT%/2/g' aws/aws.tf
    sed -i "s|%AMI%|$AMI_ID_AWS|g" aws/aws.tf
    applyTerraform aws
    echo "Access ${ipv4public1//\"/}.sslip.io in your browser"
  ;;
  "k3s-aws")
    echo "k3s option"
    cp aws/template/aws.tf.template aws/aws.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installK3s_${count.index}.sh"/g' aws/aws.tf
    sed -i 's/%COUNT%/3/g' aws/aws.tf
    sed -i "s|%AMI%|$AMI_ID_AWS|g" aws/aws.tf
    applyTerraform aws
  ;;
  "k3s-ipv6")
    echo "k3s-ipv6 option"
    cp aws/template/aws.tf.template aws/aws.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installK3snoDS.sh"/g' aws/aws.tf
    sed -i "s|%AMI%|$AMI_ID_AWS|g" aws/aws.tf
    applyTerraform aws
  ;;
  "rke2")
    echo "rke2 option with cni plugin $CNI_PLUGIN"
    case "$CNI_PLUGIN" in
      "canal"|"calico"|"cilium"|"flannel")
        # Valid CNI plugin
        ;;
      *)
        echo "Error: $CNI_PLUGIN is not a valid CNI plugin for RKE2. Supported: canal, calico, cilium, flannel."
        exit 1
        ;;
    esac
    current_cni_setting="${CNI_PLUGIN}"
    if [ "$MULTUS_ENABLED" == "true" ]; then
      echo "Multus included!"
      current_cni_setting="multus,${current_cni_setting}"
    fi
    sed -i "s/cni: .*/cni: ${current_cni_setting}/g" cloud-init-scripts\/installRKE2_0.sh
    cp aws/template/aws.tf.template aws/aws.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installRKE2_${count.index}.sh"/g' aws/aws.tf
    sed -i 's/%COUNT%/2/g' aws/aws.tf
    sed -i "s|%AMI%|$AMI_ID_AWS|g" aws/aws.tf # Use the determined AMI_ID_AWS
    applyTerraform aws
  ;;
  "rke2-ha")
    echo "rke2 in HA mode"
    cp aws/template/aws.tf.template aws/aws.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installRKE2_${count.index}.sh"/g' aws/aws.tf
    sed -i 's/%COUNT%/5/g' aws/aws.tf
    sed -i "s|%AMI%|$AMI_ID_AWS|g" aws/aws.tf
    applyTerraform aws HA
  ;;
  "demo-gpu")
    echo "demo-gpu"
    cp aws/template/aws-demo.tf.template aws/aws.tf
    AMI_ID_AWS="ami-07a28cc68132fccf1" # SLES15 SP7 in AWS Ireland
    OS_TYPE="sles"
    sed -i "s|%AMI%|$AMI_ID_AWS|g" aws/aws.tf
    sed -i 's/%CLOUDINIT%/"..\/cloud-init-scripts\/installRKE2_${count.index}.sh"/g' aws/aws.tf
    applyTerraform aws
  ;;
  *)
    echo "Error: Invalid --k8s option: $K8S_DISTRO"
    usage
    ;;
esac