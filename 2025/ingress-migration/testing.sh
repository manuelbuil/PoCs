#!/bin/bash

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


IP=$1

if [ -z "$IP" ]; then
    echo "❌ Error: The variable IP cannot be empty." >&2
    exit 1
fi

kubectl create secret tls dummy-tls-secret --cert=dummy-tls.crt --key=dummy-tls.key --namespace test-migration
kubectl create ns test-migration
echo "user:$(echo -n password | openssl passwd -stdin -apr1)" > auth_file.txt
kubectl create secret generic basic-auth-secret --from-file=auth=auth_file.txt -n test-migration
rm auth_file.txt

echo
echo "========================== STARTING TEST ================================="
echo

# TEST1 - SIMPLE APP
OUTPUT_TEST1=$($CURL -H "Host: simple.example.com" http://$IP)
compare $OUTPUT_TEST1 "200" "simple.example.com (should work)"

# TEST2 - AUTH ANNOTATIONS
OUTPUT_TEST2A=$($CURL -H "Host: auth.example.com" http://$IP)
compare $OUTPUT_TEST2A "401" "auth.example no auth (should work)"
OUTPUT_TEST2B=$($CURL -u "user:password" -H "Host: auth.example.com" http://$IP)
compare $OUTPUT_TEST2B "200" "auth.example with auth (should work)"

# TEST3 - REWRITE PATH
OUTPUT_TEST3=$($CURL -H "Host: nonworking.rewrite.example.com" http://$IP/app/test)
compare $OUTPUT_TEST3 "200" "rewrite (only works with nginx)"

# TEST4 - COOKIES
OUTPUT_TEST4=$(curl -s -c cookie-jar.txt -H "Host: cookie.example.com" http://$IP)
for i in {1..5}; do curl -s -b cookie-jar.txt -H "Host: cookie.example.com" http://$IP | grep Hostname: ; sleep 0.5; done

# TEST5 - REDIRECT
OUTPUT5=$($CURL -H "Host: ssl.redirect.example.com" http://$IP/)
compare $OUTPUT5 "308" "ssl-redirect (should work)"

# TEST6 - UPSTREAM VHOST
if curl -s -H "Host: nonworking.upstreamvhost.example.com" http://$IP/ | grep -q isitworking; then
    compare "good" "good" "vhost (only works with nginx)"
else
    compare "good" "bad" "vhost (only works with nginx)"
fi
