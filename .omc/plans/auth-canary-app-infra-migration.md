# auth-canary app-infra migration

**Epic**: `auth_canary-wex`
**Status**: approved, pending execution

---

## Summary

Replace the manually-provisioned agenix secret (`secrets/pi/auth-canary-env.age`) with
app-infra setup scripts. Auth-canary's ZITADEL_ADMIN_TOKEN and BAO_ADMIN_TOKEN are
optional setup credentials in `runtime.exs` — with app-infra, these become the provisioner
token + idempotent oneshot services instead.

Auth-canary's runtime uses the SPIRE JWT SVID → Zitadel → OpenBao JWT auth → KV read
pipeline exclusively. No static tokens needed at runtime.

---

## ADR

**Decision**: Migrate auth-canary provisioning to app-infra setup scripts; retain manual SPIRE workload entry.

**Drivers**: Eliminate static tokens at rest; standardize on app-infra provisioning pattern.

**Alternatives rejected**:
- Full app-infra SPIRE auto-wiring: `uid:0` selector incompatible with auth-canary's
  non-root runtime user (`unix:user:auth-canary`)
- Keep agenix secret: misses provisioning automation goal

**Consequences**: On first deploy, auth-canary may fail-and-restart once while
openbao-setup completes. `Restart=on-failure` handles this. Subsequent deploys are
no-ops (stamp check).

**Follow-ups**:
- Verify JWT auth backend ownership (fleet-level vs per-app)
- Consider adding `bao_zitadel_issuer` as a non-secret env var directly in the NixOS module

---

## Task Flow

| ID | Task |
|----|------|
| `auth_canary-wex.1` | Write openbao-setup.sh (KV mount, policy, JWT role, seed canary-secret) |
| `auth_canary-wex.2` | Write zitadel-setup.sh (machine user, store IDs in OpenBao KV) |
| `auth_canary-wex.3` | Wire `services.app-infra.auth-canary` in pi/services.nix (`spire.enable=false`) |
| `auth_canary-wex.4` | Update `services.auth-canary`: remove credentialsFile, add systemd ordering |
| `auth_canary-wex.5` | Remove agenix secret (auth-canary-env.age, secrets.nix, age_config.nix) |
| `auth_canary-wex.6` | Commit across machines_conf and auth_canary repos |

---

## Implementation Detail

### Step 1 — openbao-setup.sh

**New file**: `systems/x86_64-linux/pi/app-infra/auth-canary/openbao-setup.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "${APP_INFRA_HELPERS}"

# KV mount for auth-canary secrets
bao_ensure_kv_mount "kv/auth-canary"

# Policy: read-only access to auth-canary KV namespace
bao_ensure_policy "auth-canary-read" "$(cat <<EOF
path "kv/data/auth-canary/*"     { capabilities = ["read"] }
path "kv/metadata/auth-canary/*" { capabilities = ["read", "list"] }
EOF
)"

# JWT auth role — bound to auth-canary's runtime SPIFFE ID (NOT the app-infra workload/ form)
RUNTIME_SPIFFE_ID="spiffe://infra.tailnet/auth-canary"
bao_ensure_jwt_role "auth-canary" "${RUNTIME_SPIFFE_ID}"

# Seed the canary secret auth-canary reads to prove the pipeline works
bao_seed_secret "kv/auth-canary/canary-secret" "value" "canary-ok"

echo "OpenBao setup for auth-canary complete."
```

**NOTE**: Do NOT call `bao write auth/jwt/config` here. JWT backend configuration is a
fleet-level concern (owned by the normatix setup or a dedicated fleet step). Auth-canary
only creates its own KV, policy, and JWT role.

### Step 2 — zitadel-setup.sh

**New file**: `systems/x86_64-linux/pi/app-infra/auth-canary/zitadel-setup.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "${APP_INFRA_HELPERS}"

export ZITADEL_TOKEN
ZITADEL_TOKEN=$(zitadel_get_token)

PROJECT_ID=$(zitadel_ensure_project "homelab-monitoring")
MACHINE_USER_ID=$(zitadel_ensure_machine_user "auth-canary-service")

bao_seed_secret "kv/auth-canary/zitadel" "project_id"      "${PROJECT_ID}"
bao_seed_secret "kv/auth-canary/zitadel" "machine_user_id" "${MACHINE_USER_ID}"

echo "Zitadel setup for auth-canary complete."
```

### Step 3 — Wire app-infra in pi/services.nix

```nix
services.app-infra.auth-canary = {
  enable = true;
  openbao.script = ./app-infra/auth-canary/openbao-setup.sh;
  zitadel.script = ./app-infra/auth-canary/zitadel-setup.sh;
  spire.enable = false;  # SPIRE entry kept manual — uid:0 selector ≠ unix:user:auth-canary
};
```

### Step 4 — Update services.auth-canary in pi/services.nix

Remove `credentialsFile`. Update `baoKvMount` to match the new mount. Add ordering:

```nix
services.auth-canary = {
  enable = true;
  zitadelUrl = "https://homeserver:8443";
  zitadelTlsVerify = false;
  baoAddr = "https://127.0.0.1:8200";
  baoTlsVerify = false;
  baoRole = "auth-canary";
  baoSecretPath = "kv/data/auth-canary/canary-secret";
  baoKvMount = "kv/auth-canary";   # updated to match new KV mount
  # credentialsFile REMOVED
};

systemd.services.auth-canary.after = lib.mkAfter [
  "openbao-setup-auth-canary.service"
  "zitadel-setup-auth-canary.service"
];
```

Keep the manual SPIRE entry unchanged:
```nix
{
  spiffeId = "spiffe://infra.tailnet/auth-canary";
  parentId = "spiffe://infra.tailnet/spire/agent/host/pi";
  selectors = [ "unix:user:auth-canary" ];
  ttl = 300;
}
```

### Step 5 — Remove agenix secret

In `secrets/secrets.nix`: remove `"pi/auth-canary-env.age"` entry.
In `pi/age_config.nix`: remove `auth-canary-env` mapping.
Delete: `secrets/pi/auth-canary-env.age`.

---

## Acceptance Criteria

```
✓ systemctl is-active openbao-setup-auth-canary   → active
✓ systemctl is-active zitadel-setup-auth-canary    → active
✓ systemctl is-active auth-canary                  → active
✓ journalctl -u auth-canary | grep -i "canary"     → pipeline success log
✓ grep "auth-canary-env" secrets/secrets.nix        → no match
✓ ls secrets/pi/auth-canary-env.age                 → file absent
```
