#!/bin/bash

RKE2VERSION=v1.28.4+rke2r1

nextip(){
    IP=$1
    IP_HEX=$(printf '%.2X%.2X%.2X%.2X\n' `echo $IP | sed -e 's/\./ /g'`)
    NEXT_IP_HEX=$(printf %.8X `echo $(( 0x$IP_HEX + $2 ))`)
    NEXT_IP=$(printf '%d.%d.%d.%d\n' `echo $NEXT_IP_HEX | sed -r 's/(..)/0x\1 /g'`)
    echo "$NEXT_IP"
}

previp(){
    IP=$1
    IP_HEX=$(printf '%.2X%.2X%.2X%.2X\n' `echo $IP | sed -e 's/\./ /g'`)
    NEXT_IP_HEX=$(printf %.8X `echo $(( 0x$IP_HEX - $2 ))`)
    NEXT_IP=$(printf '%d.%d.%d.%d\n' `echo $NEXT_IP_HEX | sed -r 's/(..)/0x\1 /g'`)
    echo "$NEXT_IP"
}

apt update

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# The other created VM has the next or the previous IP. Ping to check which one is it
myIP=$(ip addr show $(ip route | awk '/default/ { print $5 }') | grep "inet" | head -n 1 | awk '/inet/ {print $2}' | cut -d'/' -f1)
echo This my myIP: ${myIP}

listCloserIPs(){
    IP=$1
    local -a IPs
    for i in $(seq 1 10); do
        IPnext=$(nextip ${IP} ${i})
        IPprev=$(previp ${IP} ${i})
        IPs+=(${IPnext} ${IPprev})
    done
    echo ${IPs[@]}
}

# Message to look for
expected_message="hola"

for ip in $(listCloserIPs ${myIP}); do
    response=$(nc -w 3 ${ip} 43210)
    if [[ "$response" == "$expected_message" ]]; then
        	echo SERVER FOUND ${ip}
                result=${ip}
                break
	else
        	echo SERVER NOT FOUND ${ip}
	fi
done

cat <<EOF > config.yaml
server: "https://${result}:9345"
token: "secret"
# curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_TYPE="agent" sh -
EOF

mkdir -p /etc/rancher/rke2
cp config.yaml /etc/rancher/rke2/config.yaml
user=$(ls /home/)
mv config.yaml /home/${user}/config.yaml

curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL="latest" INSTALL_RKE2_TYPE="agent" sh -
systemctl enable --now rke2-agent
