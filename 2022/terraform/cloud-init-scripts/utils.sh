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

listCloserIPs(){
    IP=$1
    local -a IPs
    for i in $(seq 1 14); do
        IPnext=$(nextip ${IP} ${i})
        IPprev=$(previp ${IP} ${i})
        IPs+=(${IPnext} ${IPprev})
    done
    echo ${IPs[@]}
}

getServerIP(){
    # Message to look for
    expected_message="hola"

    # Avoid a race condition
    sleep_time=$((RANDOM % 26 + 10))
    sleep $sleep_time

    for ip in $(listCloserIPs $1); do
        response=$(nc -w 3 ${ip} 43210)
        if [[ "$response" == "$expected_message" ]]; then
                echo ${ip}
                break
        fi
    done
}
