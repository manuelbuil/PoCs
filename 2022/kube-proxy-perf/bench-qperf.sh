#!/bin/bash

# Should be run from a client host
# REPLACE_ME in netperf.yaml with worker node name (retrieved via `kubectl get nodes`)

set -exu

MASTER_IP="$1"
WORKER_IP="$2"

prev=1
for i in 1 100 1000 2000; do
    for j in $(seq $prev $i); do sed "s/xxx/$j/g" qperf-svc.yaml | kubectl apply -f -; done
    prev=$i
    PORT=$(kubectl get svc | grep "qperf-$((1 + RANDOM % i))" | head -n1 | awk '{print $5}' | cut -d: -f2 | cut -d/ -f1)
done

for i in $(kubectl get services | grep perf | awk '{print $1}'); do kubectl delete service $i; done
