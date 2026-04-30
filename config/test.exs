import Config

# Override to prevent scheduler tick interference during tests.
# runtime.exs reads from env vars; when running tests set dummy env vars:
#   ZITADEL_URL=http://localhost:1 BAO_ADDR=http://localhost:1 \
#   BAO_ROLE=test BAO_SECRET_PATH=test/secret mix test
config :auth_canary,
  check_interval_ms: 299_000,
  failure_threshold: 5,
  zitadel_tls_verify: false,
  bao_tls_verify: false
