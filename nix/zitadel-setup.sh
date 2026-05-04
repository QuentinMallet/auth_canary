#!/usr/bin/env bash
# zitadel-setup.sh for auth-canary Zitadel monitoring account
# Creates a machine user with client_credentials grant.
# IMPORTANT: Do NOT assign any Zitadel project roles to this account.
# It only needs to exist for token issuance.
#
# After running, retrieve a test token and verify the 'sub' claim value:
#   curl -s -X POST "${ZITADEL_URL}/oauth/v2/token" \
#     -d "grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&scope=openid" \
#     | jq -r '.access_token' | cut -d. -f2 | base64 -d | jq .sub
# Use the confirmed sub value as ZITADEL_BOUND_SUBJECT in services.nix.
set -euo pipefail
source "${APP_INFRA_HELPERS}"

echo "[auth-canary] Zitadel machine user setup"
echo "[auth-canary] MANUAL STEP: Create machine user 'auth-canary-monitor' in Zitadel"
echo "[auth-canary] 1. Go to: ${ZITADEL_URL}/ui/console"
echo "[auth-canary] 2. Create machine user 'auth-canary-monitor' (no project roles)"
echo "[auth-canary] 3. Generate client credentials (client_id + client_secret)"
echo "[auth-canary] 4. Store in agenix: secrets/auth-canary/zitadel-credentials.age"
echo "[auth-canary] 5. Verify sub claim format: decode access token JWT and check sub"
echo "[auth-canary] 6. Set services.auth-canary-zitadel.zitadelBoundSubject in services.nix"
