#!/bin/bash
cd "$(dirname "$0")/.."
mkdir -p results
kubectl delete hpa emi-web -n emi --ignore-not-found

for R in 1 2 3; do
  kubectl scale deployment emi-web -n emi --replicas=$R
  kubectl rollout status deployment/emi-web -n emi
  sleep 30
  for RATE in 10 25 50 100 200; do
    L=r${R}_rate${RATE}
    N=$((RATE*60))
    echo "=== $L ($(date +%H:%M:%S)) ==="
    python3 scripts/profile.py $L & PID=$!
    sleep 2
    httperf --hog --server emi.local --port 80 \
      --add-header='Content-Type: application/json\n' \
      --wsesslog=$N,0,scripts/sessions.txt \
      --rate=$RATE --timeout=5 > results/run_$L.txt 2>&1
    kill $PID; wait $PID 2>/dev/null
    sleep 20
  done
done
echo "ALL DONE"
