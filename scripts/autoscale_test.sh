#!/bin/bash
cd "$(dirname "$0")/.."
mkdir -p results
kubectl delete hpa emi-web -n emi --ignore-not-found
kubectl scale deployment emi-web -n emi --replicas=1
kubectl rollout status deployment/emi-web -n emi
sleep 60
kubectl apply -f k8s/hpa.yaml
sleep 20

echo "timestamp,rate" > results/autoscale_phases.csv
python scripts/profile.py autoscale --hpa & PID=$!
sleep 2

run_phase () {  # rate duration
  echo "$(date +%s),$1" >> results/autoscale_phases.csv
  python scripts/loadgen.py $1 $2 results/autoscale_phase_$1_$2.txt > /dev/null
}
run_phase 10 120
run_phase 100 300
run_phase 10 180
echo "$(date +%s),0" >> results/autoscale_phases.csv

sleep 30
kill $PID; wait $PID 2>/dev/null
kubectl get hpa emi-web -n emi > results/autoscale_hpa_final.txt
echo "AUTOSCALE DONE"