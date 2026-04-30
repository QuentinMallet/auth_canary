#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="test/e2e/data"
mkdir -p "$DATA_DIR/spire-server" "$DATA_DIR/spire-agent"

# Generate join token for SPIRE agent
JOIN_TOKEN=$(spire-server token generate \
  -config test/e2e/spire/server.conf \
  -spiffeID "spiffe://e2e.test/agent/e2e" | grep -oP 'Token:\s+\K\S+')

echo "Generated join token: ${JOIN_TOKEN:0:8}..."

# Write agent.conf with real join token substituted
sed "s|{{JOIN_TOKEN}}|${JOIN_TOKEN}|g" \
  test/e2e/spire/agent.conf > "$DATA_DIR/agent.conf"

echo "Wrote agent.conf to $DATA_DIR/agent.conf"

# Create workload registration entry for auth_canary
# unix:uid is stable in CI (unlike unix:path which changes with Nix store hashes)
if spire-server entry show -config test/e2e/spire/server.conf 2>&1 | grep -q "spiffe://e2e.test/auth-canary"; then
  echo "SPIRE entry already exists for spiffe://e2e.test/auth-canary"
  spire-server entry show -config test/e2e/spire/server.conf
else
  spire-server entry create \
    -config test/e2e/spire/server.conf \
    -parentID "spiffe://e2e.test/agent/e2e" \
    -spiffeID "spiffe://e2e.test/auth-canary" \
    -selector "unix:uid:$(id -u)" \
    -jwtSVIDTTL 300
  echo "Created SPIRE entry: spiffe://e2e.test/auth-canary (unix:uid:$(id -u))"
fi

echo "SPIRE bootstrap complete."
