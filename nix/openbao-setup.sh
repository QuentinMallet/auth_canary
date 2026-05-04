#!/usr/bin/env bash
set -euo pipefail
source "${APP_INFRA_HELPERS}"

# KV mount for auth-canary secrets
bao_ensure_kv_mount "kv"

# Policy: read-only access to auth-canary KV namespace
bao_ensure_policy "auth-canary-read" "$(cat <<EOF
path "kv/data/auth-canary/*"     { capabilities = ["read"] }
path "kv/metadata/auth-canary/*" { capabilities = ["read", "list"] }
EOF
)"

# Seed the canary secret auth-canary reads to prove the pipeline works
bao_seed_secret "kv/auth-canary/canary-secret" "value" "canary-ok"

# SPIRE JWT role on auth/jwt-spire for direct M2M auth (no Zitadel)
# Policy name is "auth-canary-read" (not "auth-canary") — pass explicitly to avoid mismatch.
require_spiffe_id
bao_ensure_jwt_role auth-canary "${SPIFFE_ID}" jwt-spire auth-canary-read

echo "OpenBao setup for auth-canary complete."
