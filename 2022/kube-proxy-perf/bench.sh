#!/bin/bash

# Should be run from a client host
# REPLACE_ME in netperf.yaml with worker node name (retrieved via `kubectl get nodes`)

set -exu

MASTER_IP="$1"
WORKER_IP="$2"
RESULTS_FILE="$3"

prev=1
for i in 1 100 1000 2000; do
    for j in $(seq $prev $i); do sed "s/xxx/$j/g" iperf3-svc.yaml | kubectl apply -f -; done
    prev=$i
    echo "# SVC=$i" >> $RESULTS_FILE
    PORT=$(kubectl get svc | grep "iperf3-$((1 + RANDOM % i))" | head -n1 | awk '{print $5}' | cut -d: -f2 | cut -d/ -f1)
    $HOME/iperf3-test $MASTER_IP $PORT >> $RESULTS_FILE
done

for i in $(kubectl get services | grep iperf | awk '{print $1}'); do kubectl delete service $i; done
