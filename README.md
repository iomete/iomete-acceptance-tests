# IOMETE acceptance tests

Automated checks that your IOMETE install works end to end. The suite calls the IOMETE API the way the console and client tools do: it creates computes, runs SQL and jobs, applies data security policies and manages users, then checks each result. Nothing is mocked, so a pass means your install really works.

Run it against a test or staging install, not production. It creates its own test objects and removes them when it finishes.

## Quick start

```bash
docker run --rm \
  -e IOMETE_BASE_URL=https://iomete.example.com \
  -e IOMETE_ADMIN_PASSWORD=your-admin-password \
  -v "$PWD/reports:/suite/target/karate-reports" \
  iomete.azurecr.io/iomete/api-testing-suite:<your IOMETE version>
```

It checks that it can reach your install and log in, runs all the tests, then removes everything it created. The report lands in `./reports`.

Use the version of this repository that matches your IOMETE version. The tests and full instructions arrive here with each IOMETE release.

## Questions and problems

Open an issue in this repository, or contact IOMETE support. For a failed run, attach the report folder and your IOMETE version.
