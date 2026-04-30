# GitHub Actions CI for auth_canary

**Date:** 2026-04-30
**Status:** APPROVED
**Complexity:** MEDIUM

---

## RALPLAN-DR Summary

### Principles

1. **Nix-first**: The project is built around `flake.nix` and `mix2nix`. CI must use Nix, not standalone Elixir/Erlang setup actions, to match the production build model.
2. **Reproducibility**: CI must produce the same results as a local `nix develop` + `mix test` run. No divergence between local and CI toolchains.
3. **Fast feedback**: Cache aggressively (Nix store, Mix deps/build) to keep CI under 5 minutes for the common case.
4. **Single source of truth**: Elixir/OTP versions are pinned by `flake.lock` (nixpkgs revision). CI must not independently pin versions.
5. **No SaaS without ask**: No Cachix, no third-party caching services beyond GitHub-native caching.

### Decision Drivers (top 3)

1. **GitHub-sourced deps** (`spiffe_ex`, `observlib`) require network access during `mix deps.get` -- they are git clones, not in `mix.nix`. This rules out `nix build` for the test path.
2. **Two test tiers**: `mix test --exclude resilience` (unit + property) and `mix test --only resilience` (Snabbkaffe). Run as separate steps for clear failure attribution.
3. **`nix build` is infeasible**: `mixRelease` runs in a Nix sandbox with no network; git deps cannot be fetched. Step removed; tracked as separate issue to add `fetchGit` overrides to `flake.nix`.

### Options

#### Option A: Nix devshell for tests (CHOSEN)

Use `cachix/install-nix-action` to install Nix, then `nix develop --command` for all Mix steps.

| Pros | Cons |
|------|------|
| Exact same toolchain as local dev | Nix install adds ~30-60s cold CI |
| Single version pin (flake.lock) | Cannot run `nix build` due to git dep sandbox restriction |
| GitHub-sourced deps fetched naturally | Two cache layers (Nix store + Mix) |

#### Option B: `erlef/setup-beam` action — INVALIDATED

**Invalidation rationale:** AGENTS.md constraint "Infra: NixOS + Nix derivations. Hard constraint." directly disqualifies bypassing Nix. Version drift between `setup-beam` pins and `flake.lock` creates a class of "works in CI, breaks in Nix build" bugs.

---

## Context

- **Project**: `auth_canary` — Elixir/OTP daemon validating SPIFFE → Zitadel → OpenBao auth chain
- **Build**: `flake.nix` with `mix2nix`, `nix build .#default` produces OTP release
- **Elixir**: `~> 1.17` (pinned by nixpkgs in `flake.lock`)
- **Deps**: 2 GitHub-sourced (`spiffe_ex@093352d`, `observlib@f611dc2`), rest from Hex
- **Tests**: `mix test` (unit + StreamData property, `@tag :resilience` excluded), `mix test --only resilience` (Snabbkaffe)
- **No existing CI**: `.github/` does not exist

---

## Task Flow

### Step 1: Create `.github/workflows/ci.yml`

Trigger: `push` + `pull_request` to `master`. Runner: `ubuntu-latest`.

### Step 2: Install Nix

Use `cachix/install-nix-action@v31` with `extra-nix-config: "experimental-features = nix-command flakes"`.

### Step 3: Cache Nix store

```yaml
- uses: actions/cache@v4
  with:
    path: /nix/store
    key: nix-store-${{ hashFiles('flake.lock', 'flake.nix') }}
    restore-keys: nix-store-
```

Key includes both `flake.lock` AND `flake.nix` (devShell derivation depends on both).

### Step 4: Cache Mix artifacts

```yaml
- uses: actions/cache@v4
  with:
    path: |
      deps
      _build
      .nix-mix
      .nix-hex
    key: mix-${{ hashFiles('mix.lock', 'mix.exs') }}
    restore-keys: mix-
```

Paths include `.nix-mix` and `.nix-hex` — set by `flake.nix` shellHook as `MIX_HOME`/`HEX_HOME`. Without these, hex/rebar reinstall on every run adds ~10-15s.

### Step 5: Fetch deps

```yaml
- run: nix develop --command mix deps.get
```

Requires network for `spiffe_ex` and `observlib` (git deps, not in `mix.nix`).

### Step 6: Compile (zero warnings)

```yaml
- run: nix develop --command mix compile --warnings-as-errors
```

### Step 7: Format check

```yaml
- run: nix develop --command mix format --check-formatted
```

Note: Create `.formatter.exs` in the same PR as this CI file.

### Step 8: Unit + property tests

```yaml
- run: nix develop --command mix test --exclude resilience
```

### Step 9: Resilience tests

```yaml
- run: nix develop --command mix test --only resilience
```

Runs Snabbkaffe fault-injection tests tagged `@tag :resilience`. Separate step for clear failure attribution.

### NOT in CI: `nix build .#default`

`mixRelease` runs in a Nix sandbox (no network). `spiffe_ex` and `observlib` are git deps absent from `mix.nix`. This step will deterministically fail until `flake.nix` is updated with `fetchGit` overrides for both git deps. Track as a follow-up issue.

---

## ADR

### Decision
Use `cachix/install-nix-action` + `nix develop --command` for all CI steps. Single workflow at `.github/workflows/ci.yml`. No `nix build` step until git deps are added to the Nix derivation.

### Drivers
1. Nix-first infrastructure constraint (AGENTS.md hard constraint)
2. Git deps require `mix deps.get` with network; incompatible with `nix build` sandbox
3. Two test tiers need separate steps for attribution

### Alternatives considered
- **setup-beam**: Faster cold start but violates Nix-first constraint. Invalidated.
- **Pure `nix build` for everything**: Requires `fetchGit` overrides for 2 git deps + transitive deps. Disproportionate effort; deferred.
- **Two separate jobs**: Doubles Nix install/cache overhead. Not needed for project size.

### Why chosen
Option A provides toolchain parity with local dev, respects AGENTS.md, handles git deps naturally, and caches correctly. The `nix build` gap is acknowledged and deferred.

### Consequences
- First CI run slow (~3-5 min) while Nix store populates; warm runs ~1-2 min
- `mix.nix` / `mix.lock` drift not caught by CI until `nix build` step is restored
- `cachix/install-nix-action` is a third-party action (MIT-licensed, widely used)

### Follow-ups
- Fix `flake.nix` with `fetchGit` overrides for `spiffe_ex` and `observlib`; re-add `nix build .#default` step
- Add `mix dialyzer` step once PLTs are configured
- Consider `DeterminateSystems/magic-nix-cache-action` for better Nix store caching
- Add branch protection rules requiring CI pass before merge

---

## Acceptance Criteria

1. Push to `master` triggers CI workflow
2. PR against `master` triggers CI workflow
3. Compiler warning fails CI at the compile step
4. Misformatted code fails CI at the format step
5. Failing unit test fails CI at the unit test step
6. Failing resilience test fails CI at the resilience step
7. Clean commit passes all steps in under 5 minutes (warm cache)

---

## Files to create

```
.github/workflows/ci.yml   (~80 lines YAML)
.formatter.exs              (Mix formatter config)
```
