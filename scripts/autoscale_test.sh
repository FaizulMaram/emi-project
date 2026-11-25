#!/bin/bash
# Usage: autoscale_test.sh [peak_rate] [label]
# 10-minute HPA test: 2 min at 10 req/s, 5 min at peak_rate, 3 min at 10 req/s.
# Defaults (100 req/s, label "autoscale") are the test the assignment specifies.
PEAK=${1:-100}
LABEL=${2:-autoscale}
cd "$(dirname "$0")/.."
mkdir -p results
kubectl delete hpa emi-web -n emi --ignore-not-found
kubectl scale deployment emi-web -n emi --replicas=1
kubectl rollout status deployment/emi-web -n emi
sleep 60
kubectl apply -f k8s/hpa.yaml
sleep 20

echo "timestamp,rate" > results/${LABEL}_phases.csv
python3 scripts/profile.py $LABEL --hpa & PID=$!
sleep 2

run_chunk () {  # rate seconds outfile
  # One 60 s httperf run. A watchdog stops httperf if a stuck connection keeps
  # it running more than 10 s past its time, so the phase timing stays correct.
  httperf --hog --server emi.local --port 80 \
    --add-header='Content-Type: application/json\n' \
    --wsesslog=$(($1 * $2)),0,scripts/sessions.txt \
    --rate=$1 --timeout=5 >> "$3" 2>&1 &
  local hp=$!
  ( sleep $(($2 + 10)); kill -9 $hp 2>/dev/null && echo "watchdog: httperf stopped" >> "$3" ) &
  local wd=$!
  wait $hp
  kill $wd 2>/dev/null; wait $wd 2>/dev/null
}

run_phase () {  # rate duration (a multiple of 60 s)
  echo "$(date +%s),$1" >> results/${LABEL}_phases.csv
  out=results/${LABEL}_phase_$1_$2.txt
  : > "$out"
  for _ in $(seq 1 $(($2 / 60))); do
    run_chunk $1 60 "$out"
  done
}
run_phase 10 120
run_phase $PEAK 300
run_phase 10 180
echo "$(date +%s),0" >> results/${LABEL}_phases.csv

sleep 30
kill $PID; wait $PID 2>/dev/null
kubectl get hpa emi-web -n emi > results/${LABEL}_hpa_final.txt
echo "AUTOSCALE DONE"
