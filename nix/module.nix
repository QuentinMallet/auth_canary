# auth-canary NixOS module — dual-pipeline (SPIRE + Zitadel) monitoring
#
# Provides two independent services:
#   - auth-canary: SPIRE JWT SVID -> OpenBao auth/jwt-spire -> KV secret (critical tier)
#   - auth-canary-zitadel: Zitadel OIDC client_credentials -> OpenBao auth/jwt -> KV secret (standard tier)
#
# Package source: the auth_canary Elixir release (same binary, different env vars).
#
# NOTE: MemoryDenyWriteExecute is intentionally omitted from hardening.
# The Erlang/OTP BEAM VM's JIT compiler requires W+X memory pages.
#
# NOTE: No overlay is used. The package is referenced inline via inputs.
{
  lib,
  pkgs,
  inputs,
  config,
  ...
}:

with lib;

let
  cfg = config.services.auth-canary;
  cfgZit = config.services.auth-canary-zitadel;

  # Shared systemd hardening — MemoryDenyWriteExecute intentionally omitted:
  # the BEAM JIT requires W+X memory pages.
  beamHardening = {
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
    ];
    RestrictNamespaces = true;
    LockPersonality = true;
    RestrictRealtime = true;
    SystemCallFilter = "@system-service";
  };
in
{
  options.services.auth-canary = {
    enable = mkEnableOption "auth_canary credential pipeline canary (SPIRE leg)";

    package = mkOption {
      type = types.package;
      inherit (inputs.auth-canary.packages.${pkgs.system}) default;
      description = "The auth_canary package to use.";
    };

    spiffeSocket = mkOption {
      type = types.str;
      default = "/run/spire/agent.sock";
      description = "Path to the SPIFFE workload API socket (SPIFFE_ENDPOINT_SOCKET).";
    };

    baoAddr = mkOption {
      type = types.str;
      description = "OpenBao server address (BAO_ADDR). Required.";
    };

    baoRole = mkOption {
      type = types.str;
      description = "OpenBao JWT auth role name (BAO_ROLE). Required.";
    };

    baoSecretPath = mkOption {
      type = types.str;
      description = "KV v2 secret path to read (BAO_SECRET_PATH). Required.";
    };

    baoTlsVerify = mkOption {
      type = types.bool;
      default = true;
      description = "Verify OpenBao TLS certificate (BAO_TLS_VERIFY).";
    };

    baoKvMount = mkOption {
      type = types.str;
      default = "secret";
      description = "OpenBao KV v2 mount path (BAO_KV_MOUNT).";
    };

    baoJwtMount = mkOption {
      type = types.str;
      default = "auth/jwt-spire";
      description = "OpenBao JWT auth mount path (BAO_JWT_MOUNT).";
    };

    baoPolicy = mkOption {
      type = types.str;
      default = "auth-canary-read";
      description = "OpenBao policy name (BAO_POLICY).";
    };

    checkIntervalMs = mkOption {
      type = types.int;
      default = 60000;
      description = "Pipeline check interval in milliseconds (CHECK_INTERVAL_MS).";
    };

    failureThreshold = mkOption {
      type = types.int;
      default = 5;
      description = "Consecutive failure threshold before alerting (FAILURE_THRESHOLD).";
    };

    deployEnv = mkOption {
      type = types.str;
      default = "production";
      description = "Deployment environment name for observability (DEPLOY_ENV).";
    };

    credentialsFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional path to a systemd EnvironmentFile for non-standard deployments.
        No secrets are required at runtime — auth_canary authenticates via SPIRE JWT
        directly to OpenBao (auth/jwt-spire); no admin token is needed.
        May override: BAO_CA_CERT_PATH, WEBHOOK_URL, SPIFFE_AUDIENCE.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "auth-canary";
      description = "System user to run auth_canary as.";
    };

    group = mkOption {
      type = types.str;
      default = "auth-canary";
      description = "System group for auth_canary.";
    };
  };

  options.services.auth-canary-zitadel = {
    enable = mkEnableOption "auth_canary Zitadel OIDC pipeline canary";

    baoZitadelRole = mkOption {
      type = types.str;
      default = "auth-canary-zitadel";
      description = "OpenBao JWT auth role for Zitadel tokens (BAO_ZITADEL_ROLE).";
    };

    baoZitadelSecretPath = mkOption {
      type = types.str;
      default = "auth-canary/zitadel-canary";
      description = "KV v2 secret path for Zitadel leg (BAO_ZITADEL_SECRET_PATH).";
    };

    baoZitadelJwtMount = mkOption {
      type = types.str;
      default = "auth/jwt";
      description = "OpenBao JWT auth mount for Zitadel tokens (BAO_ZITADEL_JWT_MOUNT).";
    };

    zitadelAddr = mkOption {
      type = types.str;
      default = "https://zitadel.local";
      description = "Zitadel base URL (ZITADEL_ADDR).";
    };

    zitadelBoundSubject = mkOption {
      type = types.str;
      default = "";
      description = ''
        Zitadel machine user subject claim (bound_claims.sub in OpenBao JWT role).
        Retrieve by decoding the access token JWT: jq .sub on the payload.
      '';
    };

    zitadelIssuerUrl = mkOption {
      type = types.str;
      default = "";
      description = "Zitadel OIDC issuer URL (bound_audiences in OpenBao JWT role).";
    };

    zitadelSecretsFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to EnvironmentFile containing ZITADEL_CLIENT_ID and ZITADEL_CLIENT_SECRET.
        Required when enable = true.
      '';
    };
  };

  config = mkMerge [
    # ---- App-infra instance: SPIRE leg (critical tier) ----
    {
      services.app-infra.instances."auth-canary" = {
        enable = true;
        tier = "critical";
        openbao.script = ./openbao-setup.sh;
        zitadel.enable = false;
        spire = {
          workloadUser = "auth-canary";
          spiffeIdSuffix = "auth-canary";
        };
      };
    }

    (mkIf cfg.enable {
      users.users.${cfg.user} = {
        isSystemUser = true;
        inherit (cfg) group;
        description = "auth_canary service user";
      };

      users.groups.${cfg.group} = { };

      systemd.services.auth-canary = {
        description = "auth_canary credential pipeline canary (SPIRE leg)";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
          "spire-agent.service"
        ];
        wants = [ "network-online.target" ];

        environment = {
          # Required: Elixir mix release start script reads releases/COOKIE which
          # does not exist in Nix store builds.  Set RELEASE_COOKIE explicitly so
          # the start script never tries to cat that absent file.
          # auth_canary is single-node; the cookie value is not security-sensitive.
          RELEASE_COOKIE = "auth_canary_service";
          # Disable distributed Erlang: auth_canary is standalone (no cluster).
          # Without this, the BEAM tries to register with epmd which fails under
          # systemd RestrictAddressFamilies + ProtectSystem=strict hardening.
          RELEASE_DISTRIBUTION = "none";
          SPIFFE_ENDPOINT_SOCKET = cfg.spiffeSocket;
          BAO_ADDR = cfg.baoAddr;
          BAO_ROLE = cfg.baoRole;
          BAO_SECRET_PATH = cfg.baoSecretPath;
          BAO_TLS_VERIFY = boolToString cfg.baoTlsVerify;
          BAO_KV_MOUNT = cfg.baoKvMount;
          BAO_JWT_MOUNT = cfg.baoJwtMount;
          BAO_POLICY = cfg.baoPolicy;
          CHECK_INTERVAL_MS = toString cfg.checkIntervalMs;
          FAILURE_THRESHOLD = toString cfg.failureThreshold;
          DEPLOY_ENV = cfg.deployEnv;
        };

        serviceConfig = {
          ExecStart = "${cfg.package}/bin/auth_canary start";
          Type = "exec";
          Restart = "on-failure";
          RestartSec = "10s";
          User = cfg.user;
          Group = cfg.group;
          StateDirectory = "auth-canary";
          RuntimeDirectory = "auth-canary";

          EnvironmentFile = mkIf (cfg.credentialsFile != null) cfg.credentialsFile;
        } // beamHardening;
      };
    })

    # ---- App-infra instance: Zitadel leg (standard tier) ----
    {
      services.app-infra.instances."auth-canary-zitadel" = {
        enable = cfgZit.enable;
        tier = "standard";
        openbao.script = ./openbao-setup-zitadel.sh;
        zitadel.enable = false;
        spire.enable = false;
      };
    }

    (mkIf cfgZit.enable {
      systemd.services.auth-canary-zitadel = {
        description = "auth_canary credential pipeline canary (Zitadel leg)";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
          "auth-canary.service"
        ];
        wants = [ "network-online.target" ];

        environment = {
          # Shared config — reuse SPIRE leg bao settings for addr/tls
          BAO_ADDR = cfg.baoAddr;
          BAO_TLS_VERIFY = boolToString cfg.baoTlsVerify;
          RELEASE_COOKIE = "auth_canary_service";
          RELEASE_DISTRIBUTION = "none";
          BAO_KV_MOUNT = cfg.baoKvMount;
          # SPIRE leg config — set but not used by Zitadel scheduler
          BAO_ROLE = cfg.baoRole;
          BAO_SECRET_PATH = cfg.baoSecretPath;
          SPIFFE_ENDPOINT_SOCKET = cfg.spiffeSocket;
          CHECK_INTERVAL_MS = toString cfg.checkIntervalMs;
          FAILURE_THRESHOLD = toString cfg.failureThreshold;
          DEPLOY_ENV = cfg.deployEnv;
          # Zitadel-specific config (non-secret)
          ZITADEL_ADDR = cfgZit.zitadelAddr;
          BAO_ZITADEL_JWT_MOUNT = cfgZit.baoZitadelJwtMount;
          BAO_ZITADEL_ROLE = cfgZit.baoZitadelRole;
          BAO_ZITADEL_SECRET_PATH = cfgZit.baoZitadelSecretPath;
        };

        serviceConfig = {
          ExecStart = "${cfg.package}/bin/auth_canary start";
          Type = "exec";
          Restart = "on-failure";
          RestartSec = "10s";
          User = cfg.user;
          Group = cfg.group;
          StateDirectory = "auth-canary-zitadel";
          RuntimeDirectory = "auth-canary-zitadel";

          # Secrets: ZITADEL_CLIENT_ID + ZITADEL_CLIENT_SECRET
          EnvironmentFile = mkIf (cfgZit.zitadelSecretsFile != null) cfgZit.zitadelSecretsFile;
        } // beamHardening;
      };
    })
  ];
}
