ip0=$(terraform output -json | jq '.ipAddresses.value[0]')
ip1=$(terraform output -json | jq '.ipAddresses.value[1]')

echo $ip0
echo $ip1

sed -i '/^Host azure-ubuntu/{n;s/Hostname .*/Hostname '$ip0'/}' ~/.ssh/config
sed -i '/^Host azure-ubuntu2/{n;s/Hostname .*/Hostname '$ip1'/}' ~/.ssh/config
