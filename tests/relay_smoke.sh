#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

bash -n sing-box.sh
bash -n install.sh
bash -n src/help.sh
bash -n src/core.sh
bash -n src/init.sh
bash -n src/bbr.sh
bash -n src/relay.sh

if ! command -v go >/dev/null 2>&1; then
    echo "skip relay-parser build: go not found"
    exit 0
fi

cd cmd/relay-parser
go mod tidy
go test ./...
go build -o ../../tmp-relay-parser .

sample='vless://11111111-2222-3333-4444-555555555555@h.example.com:443?security=reality&sni=x.com&fp=chrome&pbk=PBKEY&sid=&spx=%2Fpath&type=tcp#reality'
outbound=$(../../tmp-relay-parser "$sample")

jq -e '
  .type == "vless" and
  .server == "h.example.com" and
  .server_port == 443 and
  .uuid == "11111111-2222-3333-4444-555555555555" and
  .tls.reality.public_key == "PBKEY"
' <<<"$outbound" >/dev/null

rm -f ../../tmp-relay-parser
