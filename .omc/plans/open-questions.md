# Open Questions

## github-actions-ci - 2026-04-30
- [ ] Should resilience tests run in a separate job to allow unit tests to report independently? — Affects CI feedback granularity vs. complexity
- [ ] Pin `cachix/install-nix-action` to a specific SHA or use `@v31`? — SHA pinning is more secure but harder to maintain
- [ ] Should the workflow also run on pushes to feature branches, or only master + PRs? — Broader triggers catch issues earlier but consume more CI minutes
- [ ] Is `mix dialyzer` desired as a future CI step? — Not currently configured in mix.exs (no `:dialyxir` dep), but AGENTS.md mentions type checking
