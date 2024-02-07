#!/bin/sh

K3SVERSION=v1.28.4+k3s1

nextip(){
    IP=$1
    IP_HEX=$(printf '%.2X%.2X%.2X%.2X\n' `echo $IP | sed -e 's/\./ /g'`)
    NEXT_IP_HEX=$(printf %.8X `echo $(( 0x$IP_HEX + 1 ))`)
    NEXT_IP=$(printf '%d.%d.%d.%d\n' `echo $NEXT_IP_HEX | sed -r 's/(..)/0x\1 /g'`)
    echo "$NEXT_IP"
}

previp(){
    IP=$1
    IP_HEX=$(printf '%.2X%.2X%.2X%.2X\n' `echo $IP | sed -e 's/\./ /g'`)
    NEXT_IP_HEX=$(printf %.8X `echo $(( 0x$IP_HEX - 1 ))`)
    NEXT_IP=$(printf '%d.%d.%d.%d\n' `echo $NEXT_IP_HEX | sed -r 's/(..)/0x\1 /g'`)
    echo "$NEXT_IP"
}

nextip2(){
    IP=$1
    IP_HEX=$(printf '%.2X%.2X%.2X%.2X\n' `echo $IP | sed -e 's/\./ /g'`)
    NEXT_IP_HEX=$(printf %.8X `echo $(( 0x$IP_HEX + 2 ))`)
    NEXT_IP=$(printf '%d.%d.%d.%d\n' `echo $NEXT_IP_HEX | sed -r 's/(..)/0x\1 /g'`)
    echo "$NEXT_IP"
}

previp2(){
    IP=$1
    IP_HEX=$(printf '%.2X%.2X%.2X%.2X\n' `echo $IP | sed -e 's/\./ /g'`)
    NEXT_IP_HEX=$(printf %.8X `echo $(( 0x$IP_HEX - 2 ))`)
    NEXT_IP=$(printf '%d.%d.%d.%d\n' `echo $NEXT_IP_HEX | sed -r 's/(..)/0x\1 /g'`)
    echo "$NEXT_IP"
}
apt update

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# The other created VM has the next or the previous IP. Ping to check which one is it
myIP=$(ip addr show $(ip route | awk '/default/ { print $5 }') | grep "inet" | head -n 1 | awk '/inet/ {print $2}' | cut -d'/' -f1)
echo This my myIP: ${myIP}

IPsum=$(nextip ${myIP})
IPsubs=$(previp ${myIP})
IPsum2=$(nextip2 ${myIP})
IPsubs2=$(previp2 ${myIP})

for ip in ${IPsum} ${IPsubs} ${IPsum2} ${IPsubs2}; do
	ping -c 2 -W 2 ${ip}
	if [ $? -eq 0 ]; then
        	echo PING WORKED
                result=${ip}
                break
	else
        	echo PING FAILED
	fi
done

cat <<EOF > config.yaml
server: "https://${result}:6443"
token: "secret"
# curl -sfL https://get.k3s.io | K3S_URL=https://myserver:6443 K3S_TOKEN=mynodetoken sh -
EOF

mkdir -p /etc/rancher/k3s
cp config.yaml /etc/rancher/k3s/config.yaml
user=$(ls /home/)
mv config.yaml /home/${user}/config.yaml

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${K3SVERSION} K3S_URL=https://${result}:6443 K3S_TOKEN=secret sh -
