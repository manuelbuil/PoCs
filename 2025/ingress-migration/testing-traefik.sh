#!/bin/bash

CURL="curl -s -o /dev/null -w "%{http_code}""
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

compare() {
    local HTTP_CODE="$1"
    local EXPECTED_CODE="$2"
    
    if [[ "$HTTP_CODE" == "$EXPECTED_CODE" ]]; then
        echo -e "[${GREEN}PASS${NC}] $DESCRIPTION: Received $HTTP_CODE (Expected $EXPECTED_CODE)"
    else
        echo -e "[${RED}FAIL${NC}] $DESCRIPTION: Received $HTTP_CODE (Expected $EXPECTED_CODE)"
    fi
}

kubectl create secret tls dummy-tls-secret --cert=dummy-tls.crt --key=dummy-tls.key --namespace test-migration
IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' | cut -d" " -f1)
OUTPUT1=$($CURL -H "Host: simple.example.com" http://$IP:8000)
compare $OUTPUT1 "200"
OUTPUT2=$($CURL -H "Host: annotations.example.com" http://$IP:8000/app/test)
compare $OUTPUT2 "401"
OUTPUT3=$($CURL -u "user:password" -H "Host: annotations.example.com" http://$IP:8000/app/test)
compare $OUTPUT3 "200"
OUTPUT4=$($CURL -u "user:password" -H "Host: annotations.nonworking.example.com" http://$IP:8000/app/test)
compare $OUTPUT4 "404"
OUTPUT5=$($CURL -H "Host: oneannotation.example.com" http://$IP:8000/)
compare $OUTPUT5 "308"

curl -v -H "Host: nonworking.example.com" http://$IP:8000/
