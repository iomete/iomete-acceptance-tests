# AGENTS.md

Karate API acceptance tests that customers run against their own IOMETE install. `CLAUDE.md` is a symlink to this file.

## How this repository works

- The tests are a published copy. Each IOMETE release opens a pull request here that replaces them with that release's version, so changes made to them only here are overwritten. Fix them in IOMETE's own repository instead (see `CONTRIBUTING.md`).
- `README.md` and the files that describe this repository (`CONTRIBUTING.md`, this file, `LICENSE`, the CI) are maintained here, and releases leave them alone. Keep the README in step with the commands and settings the tests use.
- Releases are tagged with the IOMETE version. A customer uses the tag that matches their install.

## Boundaries

- **Always:** keep everything customer-facing. No internal hostnames, registries, ticket numbers, team channels or incident history in code, comments or docs.
- **Never:** commit credentials, or add CI that runs against a real IOMETE install from this repository.
