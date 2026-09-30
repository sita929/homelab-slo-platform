#!/bin/bash
# Open-loop load: starts a request every 0.1 s, whether or not earlier ones have finished.
while true; do
  curl -s -o /dev/null -m 5 http://demo.192.168.29.228.nip.io/ &
  sleep 0.1
done
