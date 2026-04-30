#!/usr/bin/env bash
set -euo pipefail

export BAO_ADDR="http://127.0.0.1:8200"
export BAO_TOKEN="e2e-root-token"

# Enable KV v2 engine at secret/ path (infra-level; not in AuthCanary.Setup)
if bao secrets list 2>/dev/null | grep -q "^secret/"; then
  echo "KV v2 engine already enabled at secret/"
else
  bao secrets enable -version=2 -path=secret kv
  echo "Enabled KV v2 engine at secret/"
fi

# Enable JWT auth backend at auth/jwt (infra-level; not in AuthCanary.Setup)
if bao auth list 2>/dev/null | grep -q "^auth/jwt/\|^jwt/"; then
  echo "JWT auth backend already enabled"
else
  bao auth enable -path=auth/jwt jwt
  echo "Enabled JWT auth backend at auth/jwt"
fi

# Configure JWT auth with Zitadel OIDC discovery
# Zitadel must be healthy before this runs (ensured by process-compose depends_on)
ZITADEL_ISSUER="${BAO_ZITADEL_ISSUER:-http://localhost:8080}"
bao write auth/jwt/config \
  oidc_discovery_url="${ZITADEL_ISSUER}" \
  default_role="auth-canary"

echo "OpenBao infra bootstrap complete."
echo "  KV v2: secret/"
echo "  JWT auth: auth/jwt (oidc_discovery_url=${ZITADEL_ISSUER})"
