# AGENTS.md

Karate API acceptance tests that customers run against their own IOMETE install. `CLAUDE.md` is a symlink to this file.

## How this repository works

- It is a published copy. Each IOMETE release opens a pull request here that replaces the tests and docs with that release's version, so changes made only here are overwritten.
- Fix things in IOMETE's own repository instead. A change here is only a proposal that we port over (see `CONTRIBUTING.md`).
- Releases are tagged with the IOMETE version. A customer uses the tag that matches their install.

## Boundaries

- **Always:** keep everything customer-facing. No internal hostnames, registries, ticket numbers, team channels or incident history in code, comments or docs.
- **Never:** commit credentials, or add CI that runs against a real IOMETE install from this repository.
