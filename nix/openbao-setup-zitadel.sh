#!/usr/bin/env bash
set -euo pipefail
source "${APP_INFRA_HELPERS}"

# Policy: auth-canary-zitadel-read — read-only on zitadel-canary path
bao_ensure_policy "auth-canary-zitadel-read" '
  path "kv/data/auth-canary/zitadel-canary" {
    capabilities = ["read"]
  }'

# Zitadel JWT role — use bao_ensure_zitadel_jwt_role (NOT bao_ensure_jwt_role)
# Zitadel tokens have aud=<issuer_url>, NOT aud=openbao
bao_ensure_zitadel_jwt_role \
  "jwt" \
  "auth-canary-zitadel" \
  "${ZITADEL_BOUND_SUBJECT}" \
  "${ZITADEL_ISSUER_URL}" \
  "auth-canary-zitadel-read"

# Seed the canary secret
bao_ensure_kv_mount "kv"
bao_seed_secret "kv/auth-canary/zitadel-canary" "value" "zitadel-canary-ok"

echo "OpenBao setup for auth-canary-zitadel complete."
