#!/bin/bash
cd "$(dirname "$0")/.."
kubectl delete hpa emi-web -n emi --ignore-not-found
for R in 1 2 3; do
  kubectl scale deployment emi-web -n emi --replicas=$R
  kubectl rollout status deployment/emi-web -n emi
  sleep 30
  for RATE in 10 25 50 100 200; do
    L=r${R}_rate${RATE}
    echo "=== $L ($(date +%H:%M:%S)) ==="
    python scripts/profile.py $L & PID=$!
    sleep 2
    python scripts/loadgen.py $RATE 60 results/run_$L.txt > /dev/null
    kill $PID; wait $PID 2>/dev/null
    sleep 20
  done
done
echo "RERUN DONE"
