set -eu

check_network_sysctl() {
	echo "/proc/sys/net/ipv4/conf/all/forwarding = $(cat /proc/sys/net/ipv4/conf/all/forwarding)"
	main_if=$(ip r get 8.8.8.8 | awk '{print $5}')
	echo /proc/sys/net/ipv4/conf/$main_if/forwarding = $(cat /proc/sys/net/ipv4/conf/$main_if/forwarding)
}

check_ports() {
	tcp_list=(9345 6443 10250 2379 2380 4240 179 5473 9099)
	for port in ${tcp_list[@]};
	do
		if $(nc -zvw 5 $1 $port > /dev/null 2>&1); then
			echo "$1:$port is open (tcp)"
		else
			echo "$1:$port is closed (tcp)"
		fi
	done
}

echo "Starting test..."

check_network_sysctl
echo

for item in $(kubectl get nodes -o wide | awk '{print $3";"$6}' | tail -n+2);
do 
	role=$(echo $item | cut -d";" -f1)
	echo "The role of the node is: $role"
	ip=$(echo $item | cut -d";" -f2)
	check_ports $ip; echo;
	ping -c 4 $ip; echo;
done

kubectl apply -f connectivity-check.yaml

echo "Finishing test..."
