# Contributing

Thanks for helping improve the IOMETE acceptance tests.

This repository is published from IOMETE's own repository with each IOMETE release, so a release replaces whatever changed here in between. Because of that:

- **Report a problem or ask for a test** by opening an issue. Include your IOMETE version, the test that failed and, if you can, the report folder.
- **Pull requests are welcome** as a way to show a fix. We apply the change in our repository, and it reaches this one with the next release. We then close your pull request with a link to the release.

When you write a test:

- Cover the main flow of a feature end to end, not every edge case.
- Name everything a test creates with the run id (`'karate-<what>-' + runId`), and delete it in an `afterScenario` so it is removed even when the test fails.
- Never point at a specific environment, or commit credentials. Settings come from `.env` or environment variables.
