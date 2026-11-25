#!/bin/bash
# Milestone 3 helper. Needs emi.local mapped to the Ingress (see README).
# Usage: rollout.sh update|undo
# Runs a request loop through the Ingress during `kubectl set image` (update)
# or `kubectl rollout undo` (undo), and reports every failed request.
# Run from the repository root; the request log is saved in results/.
mode=$1
reqs=$(mktemp)
(
  while [ ! -f "$reqs.stop" ]; do
    out=$(curl -s -m 5 -w ' %{http_code}' -X POST http://emi.local/api/emi \
      -H 'Content-Type: application/json' -d '{"P":400000,"rate":9.5,"n":60}')
    code=${out##* }
    pod=$(echo "${out% *}" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("servedBy","-"))' 2>/dev/null || echo -)
    echo "$(date -u +%H:%M:%S) $code $pod" >> "$reqs"
    python3 -c 'import time; time.sleep(0.2)'
  done
) &
loop=$!
python3 -c 'import time; time.sleep(5)'

if [ "$mode" = update ]; then
  echo "$ kubectl set image deployment/emi-web emi-web=emi-web:1.1 -n emi"
  kubectl set image deployment/emi-web emi-web=emi-web:1.1 -n emi
  kubectl annotate deployment/emi-web -n emi kubernetes.io/change-cause="update to emi-web:1.1 (footer)" --overwrite >/dev/null
else
  echo "$ kubectl rollout undo deployment/emi-web -n emi"
  kubectl rollout undo deployment/emi-web -n emi
fi
echo "$ kubectl rollout status deployment/emi-web -n emi"
kubectl rollout status deployment/emi-web -n emi --timeout=300s
python3 -c 'import time; time.sleep(15)'
touch "$reqs.stop"; wait $loop

echo
echo "--- request loop through http://emi.local during the rollout"
total=$(wc -l < "$reqs" | tr -d ' ')
ok=$(awk '$2 == 200' "$reqs" | wc -l | tr -d ' ')
echo "requests: $total   HTTP 200: $ok   failed: $((total - ok))"
echo "first and last requests (time, HTTP code, pod):"
head -3 "$reqs"; echo "  ..."; tail -3 "$reqs"
awk '$2 != 200' "$reqs" | head -20
mkdir -p results
if [ "$mode" = update ]; then cp "$reqs" results/m3_rolling_update_requests.log
else cp "$reqs" results/m3_rollback_requests.log; fi
rm -f "$reqs" "$reqs.stop"
