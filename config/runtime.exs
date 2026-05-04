import Config

# Required — crash at boot if missing
config :auth_canary,
  bao_addr: System.fetch_env!("BAO_ADDR"),
  bao_role: System.fetch_env!("BAO_ROLE"),
  bao_secret_path: System.fetch_env!("BAO_SECRET_PATH")

# TLS — optional CA cert paths
config :auth_canary,
  bao_ca_cert: System.get_env("BAO_CA_CERT_PATH"),
  bao_tls_verify: System.get_env("BAO_TLS_VERIFY", "true") != "false"

# Optional with defaults
config :auth_canary,
  spiffe_socket: System.get_env("SPIFFE_ENDPOINT_SOCKET", "/run/spire/agent.sock"),
  spiffe_audience: System.get_env("SPIFFE_AUDIENCE", "openbao"),
  check_interval_ms: String.to_integer(System.get_env("CHECK_INTERVAL_MS", "60000")),
  failure_threshold: String.to_integer(System.get_env("FAILURE_THRESHOLD", "5")),
  webhook_url: System.get_env("WEBHOOK_URL")

# Setup optional admin credentials
config :auth_canary,
  bao_admin_token: System.get_env("BAO_ADMIN_TOKEN"),
  bao_policy: System.get_env("BAO_POLICY", "auth-canary-read"),
  bao_kv_mount: System.get_env("BAO_KV_MOUNT", "secret"),
  bao_jwt_mount: System.get_env("BAO_JWT_MOUNT", "auth/jwt-spire")

# Zitadel OIDC machine account (optional — if absent, Zitadel pipeline is skipped)
config :auth_canary,
  zitadel_addr: System.get_env("ZITADEL_ADDR"),
  zitadel_client_id: System.get_env("ZITADEL_CLIENT_ID"),
  zitadel_client_secret: System.get_env("ZITADEL_CLIENT_SECRET"),
  bao_zitadel_jwt_mount: System.get_env("BAO_ZITADEL_JWT_MOUNT", "auth/jwt"),
  bao_zitadel_role: System.get_env("BAO_ZITADEL_ROLE"),
  bao_zitadel_secret_path: System.get_env("BAO_ZITADEL_SECRET_PATH")

# Observlib — config under :observlib app key (not :auth_canary, :observlib)
# Keys confirmed from source: service_name, otlp_endpoint, resource_attributes, telemetry_events
# Call ObservLib.configure() in application.ex after supervisor start (no setup/1 function)
config :observlib,
  service_name: "auth_canary",
  resource_attributes: %{
    "service.version" => "0.1.0",
    "deployment.environment" => System.get_env("DEPLOY_ENV", "production")
  }
