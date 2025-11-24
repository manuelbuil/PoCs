#!/bin/bash

set -eu

CURL="curl -s -o /dev/null -w "%{http_code}""
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

compare() {
    local HTTP_CODE="$1"
    local EXPECTED_CODE="$2"
    local DESCRIPTION="$3"
    
    if [[ "$HTTP_CODE" == "$EXPECTED_CODE" ]]; then
        echo -e "[${GREEN}PASS${NC}] $DESCRIPTION: Received $HTTP_CODE (Expected $EXPECTED_CODE)"
    else
        echo -e "[${RED}FAIL${NC}] $DESCRIPTION: Received $HTTP_CODE (Expected $EXPECTED_CODE)"
    fi
}


IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' | cut -d" " -f1)
OUTPUT1=$($CURL -H "Host: simple.example.com" http://$IP)
compare $OUTPUT1 "200" "simple.example.com"
OUTPUT2=$($CURL -H "Host: annotations.example.com" http://$IP/app/test)
compare $OUTPUT2 "401" "auth annotations no auth"
OUTPUT3=$($CURL -u "user:password" -H "Host: annotations.example.com" http://$IP/app/test)
compare $OUTPUT3 "200" "auth annotations with auth"
OUTPUT4=$($CURL -u "user:password" -H "Host: another.nonworking.annotation.example.com" http://$IP/app/test)
compare $OUTPUT4 "200" "redirect"
OUTPUT5=$($CURL -H "Host: oneannotation.example.com" http://$IP/)
compare $OUTPUT5 "308" "ssl-redirect"
OUTPUT6_FULL=$(curl -v -H "Host: nonworking.example.com" http://$IP/ 2>&1)
if echo "$OUTPUT6_FULL" | grep -q 'Host: internal-host.local'; then
    echo -e "[${GREEN}PASS${NC}] "vhost""
else
    # If the desired header is NOT found, set the output flag to "FAIL" (unexpected result)
    echo -e "[${RED}FAIL${NC}] "vhost""
fi
