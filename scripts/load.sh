#!/bin/bash
# About 10 requests/s to the demo; logs UTC time, HTTP code and which pod answered.
while true; do
  body=$(curl -s -m 2 -w ' %{http_code}' http://demo.192.168.29.228.nip.io/)
  node=$(echo "$body" | grep -o '"pod": "[^"]*"' | cut -d'"' -f4)
  echo "$(date -u +%H:%M:%S) ${body##* } ${node:-none}"
  sleep 0.1
done
