#!/usr/bin/env bash
set -euo pipefail

# All env vars required by AuthCanary.Setup and runtime.exs
export ZITADEL_URL="http://localhost:8080"
export ZITADEL_ADMIN_TOKEN="e2e-admin-pat-value-for-testing"
export ZITADEL_KEY_FILE_PATH="test/e2e/data/zitadel-jwt-key.json"
export ZITADEL_TLS_VERIFY="false"
export BAO_ADDR="http://127.0.0.1:8200"
export BAO_ADMIN_TOKEN="e2e-root-token"
export BAO_ROLE="auth-canary"
export BAO_SECRET_PATH="auth-canary/canary"
export BAO_KV_MOUNT="secret"
export BAO_JWT_MOUNT="auth/jwt"
export BAO_ZITADEL_ISSUER="http://localhost:8080"
export BAO_POLICY="auth-canary-read"
export BAO_TLS_VERIFY="false"
export SPIFFE_ENDPOINT_SOCKET="test/e2e/data/agent.sock"

echo "Running AuthCanary.Setup..."

# Run AuthCanary.Setup:
#   Zitadel: creates project + JWT app + machine user + JWT key file
#   OpenBao: creates policy (auth-canary-read) + role + secret seed
nix develop --command mix run \
  -e 'AuthCanary.Setup.run()' \
  --no-compile

echo "AuthCanary.Setup complete."

# Write env file for use by e2e test run
mkdir -p test/e2e/data
cat > test/e2e/data/e2e.env <<'EOF'
ZITADEL_URL=http://localhost:8080
BAO_ADDR=http://127.0.0.1:8200
BAO_ROLE=auth-canary
BAO_SECRET_PATH=auth-canary/canary
SPIFFE_ENDPOINT_SOCKET=test/e2e/data/agent.sock
ZITADEL_KEY_FILE_PATH=test/e2e/data/zitadel-jwt-key.json
ZITADEL_TLS_VERIFY=false
BAO_TLS_VERIFY=false
EOF

echo "Wrote test/e2e/data/e2e.env"
echo "App bootstrap complete. Ready for: mix test --only e2e"
