#!/usr/bin/env bash
# Runs tsls against a fixture through a fake `tailscale` on PATH.
# Usage: ./test.sh
set -euo pipefail
cd "$(dirname "$0")"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Current UTC wall time tagged +03:00 is an instant 3h ago; tagged -02:00
# it is 2h ahead, which must clamp to 0s, not read as 2h ago.
wall=$(date -u +%Y-%m-%dT%H:%M:%S)
cat > "$tmp/status.json" <<EOF
{"BackendState": "Running", "MagicDNSSuffix": "example.ts.net",
 "Self": {"ID": "s", "DNSName": "mac.example.ts.net.", "OS": "macOS", "Online": true,
          "TailscaleIPs": ["100.64.0.1"], "LastSeen": "0001-01-01T00:00:00Z"},
 "Peer": {
  "a": {"ID": "a", "DNSName": "us-sea-wg-001.mullvad.ts.net.", "OS": "linux", "Online": true,
        "ExitNode": true, "ExitNodeOption": true, "Tags": ["tag:mullvad-exit-node"], "TailscaleIPs": ["100.64.0.2"]},
  "b": {"ID": "b", "DNSName": "de-fra-wg-302.mullvad.ts.net.", "OS": "linux", "Online": true,
        "ExitNodeOption": true, "Tags": ["tag:mullvad-exit-node"], "TailscaleIPs": ["100.64.0.3"]},
  "c": {"ID": "c", "DNSName": "", "HostName": "device-of-shared-to-user", "ShareeNode": true,
        "Online": false, "TailscaleIPs": ["100.64.0.4"]},
  "d": {"ID": "d", "DNSName": "router.example.ts.net.", "OS": "linux", "Online": true,
        "ExitNodeOption": true, "PrimaryRoutes": ["192.168.1.0/24"], "TailscaleIPs": ["100.64.0.5"]},
  "e": {"ID": "e", "DNSName": "nas.example.ts.net.", "OS": "linux", "Online": false,
        "LastSeen": "${wall}.5+03:00", "TailscaleIPs": ["100.64.0.6"]},
  "f": {"ID": "f", "DNSName": "ahead.example.ts.net.", "OS": "windows", "Online": false,
        "LastSeen": "${wall}-02:00", "TailscaleIPs": ["100.64.0.7"]},
  "g": {"ID": "g", "DNSName": "old.example.ts.net.", "OS": "android", "Online": true, "Active": true,
        "Expired": true, "TailscaleIPs": ["100.64.0.8"]},
  "h": {"ID": "h", "DNSName": "", "HostName": "", "OS": "", "Online": false, "TailscaleIPs": ["100.64.0.9"]}
 }}
EOF
printf '#!/bin/sh\ncat "%s"\n' "$tmp/status.json" > "$tmp/tailscale"
chmod +x "$tmp/tailscale"

fail=0
run() { out=$(PATH="$tmp:$PATH" ./tsls "$@"); args="$*"; }
has() {
  grep -Eq -- "$1" <<< "$out" || { echo "FAIL tsls $args: expected /$1/"; fail=1; }
}
lacks() {
  if grep -Eq -- "$1" <<< "$out"; then echo "FAIL tsls $args: unexpected /$1/"; fail=1; fi
}
count() {
  local n; n=$(grep -c -- "$1" <<< "$out" || true)
  [[ "$n" == "$2" ]] || { echo "FAIL tsls $args: $2 x /$1/, got $n"; fail=1; }
}

run
has   '3 online  4 offline  ·  2 hidden'
has   'mac +macOS +online \[self\]'
has   'us-sea-wg-001 +linux +online \[exit\]$'
lacks 'de-fra-wg-302|device-of-shared-to-user'
has   'router +linux +online \[exit\?\] \[subnets\]$'
has   'nas +linux +3h ago$'
has   'ahead +windows +0s ago$'
has   'old +android +expired$'
has   '100\.64\.0\.9 +\? +- +offline$'
count '●' 3
count '○' 4

run -a
has   '4 online  5 offline   v'
has   'de-fra-wg-302 +linux +online \[exit\?\]$'
has   'device-of-shared-to-user'

run -o
count '○' 0
count '●' 3

run -o -f
count '●' 0
count '○' 4

(( fail )) && exit 1
echo "ok"
