# Plan: Wire auth_canary into machines_conf

Epic: auth_canary-d66
Status: approved
Approved: 2026-04-30

## Summary

Add auth_canary as a Nix flake input to machines_conf and wrap it as a Snowfall NixOS systemd service module. Changes are made in a dedicated git worktree.

## RALPLAN-DR

### Principles
1. Follow existing Snowfall conventions — module lives in `modules/nixos/auth-canary/default.nix`, auto-discovered by Snowfall
2. Systemd hardening parity — mirror openbao-agent hardening profile (excluding `MemoryDenyWriteExecute` for BEAM JIT compatibility)
3. Config via environment variables — all options map to env vars; secrets delegated to `EnvironmentFile=` via `credentialsFile`
4. Minimal blast radius — all work in a dedicated worktree/branch; no changes to master until reviewed

### Decision Drivers
1. Nix correctness — module must evaluate cleanly in `nix flake check` without running auth_canary
2. Service ordering — auth-canary depends on SPIRE agent socket, network
3. Worktree isolation — changes live in `feat/auth-canary` branch

### Options Considered
- **Option A (chosen)**: Inline package reference inside module, no overlay — follows normatix/cremexporter precedent, simpler
- **Option B (deferred)**: Create overlay exposing `pkgs.auth-canary` — deferred until second consumer exists

### ADR
- **Decision**: Inline package reference via `inputs.auth-canary.packages.${pkgs.system}.default` in module
- **Rejected**: Overlay — no second consumer exists yet; decision documented in module comment
- **Consequences**: Package not available as `pkgs.auth-canary`; acceptable for single consumer
- **Follow-ups**: SPIRE workload entry (unix:uid attestation); production `baoSecretPath`; agenix secret for `credentialsFile`

## Task Flow

### d66.1 — Create dedicated worktree and branch
```bash
cd /home/urist/machines_conf
git worktree add ../machines_conf-auth-canary -b feat/auth-canary
```
All subsequent edits in `/home/urist/machines_conf-auth-canary`.

**AC**: `git worktree list` shows `../machines_conf-auth-canary` on branch `feat/auth-canary`.

### d66.2 — Add auth-canary flake input
In `/home/urist/machines_conf-auth-canary/flake.nix`, add to `inputs`:
```nix
auth-canary.url = "github:QuentinMallet/auth_canary";
```
Run `nix flake lock --update-input auth-canary` to fetch and pin.

**AC**: `flake.lock` contains an entry for `auth-canary` referencing `github:QuentinMallet/auth_canary`.

### d66.3 — Create modules/nixos/auth-canary/default.nix

Full NixOS module with `services.auth-canary` options:

#### Non-secret options (→ systemd `Environment=`)

| Option | Type | Default | Env var |
|--------|------|---------|---------|
| `enable` | bool | false | — |
| `package` | package | `inputs.auth-canary.packages.${pkgs.system}.default` | — |
| `spiffeSocket` | str | `/run/spire/agent.sock` | `SPIFFE_ENDPOINT_SOCKET` |
| `zitadelUrl` | str | — (required) | `ZITADEL_URL` |
| `zitadelTlsVerify` | bool | true | `ZITADEL_TLS_VERIFY` |
| `baoAddr` | str | — (required) | `BAO_ADDR` |
| `baoRole` | str | — (required) | `BAO_ROLE` |
| `baoSecretPath` | str | — (required) | `BAO_SECRET_PATH` |
| `baoTlsVerify` | bool | true | `BAO_TLS_VERIFY` |
| `baoKvMount` | str | `"secret"` | `BAO_KV_MOUNT` |
| `baoJwtMount` | str | `"auth/jwt"` | `BAO_JWT_MOUNT` |
| `baoPolicy` | str | `"auth-canary-read"` | `BAO_POLICY` |
| `checkIntervalMs` | int | 60000 | `CHECK_INTERVAL_MS` |
| `failureThreshold` | int | 5 | `FAILURE_THRESHOLD` |
| `deployEnv` | str | `"production"` | `DEPLOY_ENV` |
| `credentialsFile` | nullOr path | null | → systemd `EnvironmentFile=` |
| `user` | str | `"auth-canary"` | — |
| `group` | str | `"auth-canary"` | — |

Module sets `ZITADEL_KEY_FILE_PATH=/var/lib/auth-canary/zitadel-key.json` via `Environment=` (overridable via `credentialsFile`).

`credentialsFile` must contain: `ZITADEL_ADMIN_TOKEN`, `BAO_ADMIN_TOKEN`, `ZITADEL_KEY_FILE_PATH`, `ZITADEL_CA_CERT_PATH`, `BAO_CA_CERT_PATH`, `BAO_ZITADEL_ISSUER`.

#### Systemd service
```nix
systemd.services.auth-canary = {
  description = "auth_canary credential pipeline canary";
  wantedBy = [ "multi-user.target" ];
  after = [ "network-online.target" "spire-agent.service" ];
  wants = [ "network-online.target" ];
  serviceConfig = {
    ExecStart = "${cfg.package}/bin/auth_canary start";
    Type = "exec";
    Restart = "on-failure";
    RestartSec = "10s";
    User = cfg.user;
    Group = cfg.group;
    StateDirectory = "auth-canary";
    RuntimeDirectory = "auth-canary";
    EnvironmentFile = lib.mkIf (cfg.credentialsFile != null) cfg.credentialsFile;
    # Hardening (openbao-agent pattern)
    # MemoryDenyWriteExecute intentionally omitted — BEAM JIT requires W+X pages
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    RestrictNamespaces = true;
    LockPersonality = true;
    RestrictRealtime = true;
    SystemCallFilter = "@system-service";
  };
};
```

Also: `users.users.auth-canary`, `users.groups.auth-canary`.

**AC**: File exists with all listed options and systemd service definition.

### d66.4 — Wire into pi host
In `systems/x86_64-linux/pi/services.nix`:
```nix
services.auth-canary = {
  enable = true;
  zitadelUrl = "https://homeserver:8443";
  zitadelTlsVerify = false;  # self-signed cert
  baoAddr = "https://127.0.0.1:8200";
  baoTlsVerify = false;       # self-signed cert
  baoRole = "auth-canary";
  baoSecretPath = "kv/data/auth-canary/canary-secret";  # placeholder
  # credentialsFile = config.age.secrets.auth-canary-env.path;  # wire agenix later
};
```

**AC**: `services.auth-canary.enable = true` appears in pi services config.

### d66.5 — Validate
```bash
cd /home/urist/machines_conf-auth-canary
nix flake check
nix build .#nixosConfigurations.pi.config.system.build.toplevel --dry-run
```

**AC**: Both commands exit 0. Systemd unit `auth-canary.service` appears in the built closure.

## Deferred (not blockers)
- SPIRE workload entry: `unix:uid` selector for `auth-canary` user; `jwtSVIDTTL 300`
- Production `baoSecretPath` value
- Agenix secret for `credentialsFile` on pi
- Overlay introduction when second consumer exists
