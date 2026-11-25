#!/bin/bash
# Milestone 3 helper. Needs emi.local mapped to the Ingress (see README).
# Sends 30 POST /api/emi requests through the Ingress and counts servedBy per pod.
out=$(mktemp)
for i in $(seq 1 30); do
  pod=$(curl -s -m 10 -X POST http://emi.local/api/emi \
    -H 'Content-Type: application/json' \
    -d "{\"P\":$((100000 + RANDOM * 10)),\"rate\":12,\"n\":24}" |
    python3 -c 'import sys,json; print(json.load(sys.stdin).get("servedBy","ERROR"))' 2>/dev/null || echo ERROR)
  echo "$pod" >> "$out"
done
echo "Requests served per pod (30 requests):"
sort "$out" | uniq -c | awk '{printf "  %-32s %s\n", $2, $1}'
echo "  total: $(wc -l < "$out" | tr -d ' ')"
rm -f "$out"
