# IOMETE acceptance tests

Automated checks that your IOMETE install works end to end. The suite calls the IOMETE API the way the console and client tools do: it creates computes, runs SQL and jobs, applies data security policies, manages users, and checks each result. Nothing is mocked, so a pass means your install really works.

Run it against a test or staging install, not production. It creates its own test objects and removes them when it finishes.

## Before you start

You need:

- **An IOMETE admin account** (username and password), or an admin access token.
- **Network access** from where you run the suite to your IOMETE console address.
- **Room for several small computes.** A run keeps two computes warm for its whole length and starts up to four more at a time for single tests, each with a 3 GB driver and a 2 GB executor, plus short Spark jobs and a Jupyter container. The suite registers its own small node types for them (`karate-*`).
- **Docker**, or **Java 21** and `make` to run from source.

## Quick start with Docker

Use the image that matches your IOMETE version:

```bash
mkdir -p reports
docker run --rm -u "$(id -u):$(id -g)" \
  -e IOMETE_BASE_URL=https://iomete.example.com \
  -e IOMETE_ADMIN_PASSWORD=your-admin-password \
  -v "$PWD/reports:/suite/target/karate-reports" \
  iomete.azurecr.io/iomete/api-testing-suite:<your IOMETE version>
```

It checks that it can reach your install and log in, runs all the tests, then removes everything it created, and starts within seconds. The report lands in `./reports`. It prints a run id first, which you need only to clean up after a killed run (see [What the suite creates](#what-the-suite-creates)). A full run takes about 30 to 40 minutes.

## Quick start from source

1. Create your settings file and fill in the two required values:

   ```bash
   cp .env.example .env
   ```

   ```bash
   IOMETE_BASE_URL=https://iomete.example.com
   IOMETE_ADMIN_PASSWORD=your-admin-password
   ```

   Write values without quotes.

2. Check that the suite can reach your install and log in:

   ```bash
   make check
   ```

   You should see `Ready: https://iomete.example.com runs IOMETE <version> ...`. Otherwise it prints `Setup problem: ...` with what to fix.

3. Run the tests, then remove what they created:

   ```bash
   make test
   make cleanup
   ```

Maven is not needed. The repository includes a Maven wrapper that downloads what it needs on first run.

## Reading the results

The output shows each test as it runs (`>> RUN`), then `<< PASS`, `<< FAIL` or `<< SKIP`.

The full report is `target/karate-reports/karate-summary.html` (or `./reports` with Docker). Open it in a browser and click a test to see every request and response. Passwords and tokens are hidden.

A skipped test is not a failure. Tests skip when your install does not have the feature they check, for example a module that is turned off or a single data plane.

If you contact IOMETE support about a failure, send the whole report folder and your IOMETE version.

## Running some of the tests

```bash
make test-one FEATURE=src/test/java/iomete/tests/sql/query-ddl.feature      # one file
make test-one FEATURE=src/test/java/iomete/tests/sql/query-ddl.feature:46   # one test, by line
make test-one TAGS="@spark3"                                                # by tag
```

Tests are grouped by area under `src/test/java/iomete/tests/`: `sql`, `compute`, `job`, `data-security`, `identity`, `catalog` and others. With Docker, put the same choice after the image name, as a classpath path or a tag: `classpath:iomete/tests/sql` or `--tags @spark3`. It still cleans up afterwards.

Run `make clean` after adding, moving or renaming a test file.

## Your own tests

Put your own tests in the `custom-tests` folder, as Karate `.feature` files. Each IOMETE release replaces the IOMETE tests under `src`, but never touches `custom-tests`, so keep your tests there and not under `src`.

They run with the IOMETE tests in `make test`, and on their own with:

```bash
make test-one FEATURE=custom-tests
```

With Docker, mount the folder into the container: add `-v "$PWD/custom-tests:/suite/custom-tests"` to the `docker run` command.

Each feature needs a `@lock` tag on its first line, which decides what it may run next to. Use `@lock=api` for a test that only calls the API. `custom-tests/example.feature` shows the shape. A test can use the same settings and helpers as the IOMETE tests, for example `baseUrl` and `runId`, and `call read('classpath:iomete/helpers/...')`. Follow the test-writing rules in [CONTRIBUTING.md](CONTRIBUTING.md) so your test cleans up after itself.

## Optional tests

These tests skip unless you give them what they need in `.env` (or with `-e` for Docker). `.env.example` lists every setting.

| Test | What it checks | Settings |
|---|---|---|
| LDAP sync | Users and groups sync in from an LDAP directory and are removed when the filter stops matching | `IOMETE_LDAP_URL`, `IOMETE_LDAP_BIND_PASSWORD`, and `IOMETE_LDAP_BASE_DN` (default `dc=iomete,dc=com`); optionally `IOMETE_LDAP_BIND_DN`, `IOMETE_LDAP_USERS_DN`, `IOMETE_LDAP_GROUPS_DN` |
| GitLab | The SQL editor opens files and branches from a GitLab project | `IOMETE_GIT_REPO_URL`, `IOMETE_GIT_TOKEN` |
| GitHub | A GitHub repository can be added and its files listed | `IOMETE_GITHUB_REPO_URL`, `IOMETE_GITHUB_TOKEN` |
| Vault | A Vault secret store connects and its keys are listed | `IOMETE_VAULT_ADDRESS`, `IOMETE_VAULT_TOKEN`, `IOMETE_VAULT_SECRET_PATH`, `IOMETE_VAULT_SECRET_KEY` |
| Email notifications | A failed job sends an email, read back from a Mailpit mailbox | `IOMETE_MAIL_*`. `IOMETE_MAIL_SET_INTEGRATION=true` sets up the platform's email integration if there is none, and leaves it |
| Webhook notifications | A failed job calls a webhook | `IOMETE_WEBHOOK_*`. `IOMETE_WEBHOOK_SET_FLAG=true` turns webhook notifications on for the whole platform, and leaves them on |
| Storage check | IOMETE can list, write, read and delete in an S3 bucket | `IOMETE_STORAGE_*` |
| Platform-wide changes | Overriding a system setting, a marketplace app, a Docker registry and a Model Gateway connection. The Model Gateway test leaves a `karate-model` provider model behind, since it cannot be deleted | `IOMETE_ALLOW_PLATFORM_CHANGES=true` |

> [!WARNING]
> The LDAP test replaces every user and group imported from LDAP on the install, and removes them when it finishes. Only turn it on for a test install. It never writes to the directory.

**LDAP.** The test expects an OpenLDAP-style layout: `inetOrgPerson` users under `ou=users` and `groupOfNames` groups under `ou=groups` of the base DN, and the first group listed must have members. IOMETE must be able to reach the directory; the machine running the suite does not.

**GitLab.** Use a project with at least one file at its root and no more than 20 branches, and a token with the `read_api` scope. Give the project's browser address, not the `git@...` address.

## What the suite creates

- **A domain for each run**, named `karate-<run id>-...`. Everything the run starts lives in it, and `make cleanup` deletes it. On IOMETE versions before 4.0.2, which cannot delete a domain, the suite uses one domain named `karate` and keeps it. To use a domain you already have instead, set `IOMETE_DOMAIN`. The suite never deletes that one.
- **Six small node types** named `karate-*`. They stay, so the next run can reuse them.
- **Users, groups, catalogs, databases, policies and secrets.** Their names start with `karate-` or `karate_` and carry the run id. Each test removes what it creates, and `make cleanup` removes the rest.

`make cleanup` ends with a `WARNING:` line for each thing it leaves behind on purpose.

If a run was cancelled, `make cleanup` still removes what it left, as long as you run it from the same folder before starting another run. A Docker run cleans up when you press Ctrl-C or stop it. Give it time: `docker stop -t 300 <container>`, since plain `docker stop` kills it after 10 seconds, mid-cleanup. If the container was killed, run the image again with `-e IOMETE_RUN_ID=<the run id it printed>` and the argument `cleanup`.

## Running from GitLab CI

`.gitlab-ci.yml` runs the suite from a GitLab project, then removes what it created, whether the tests passed or failed. It points at no install of its own:

1. Mirror or copy this repository into a GitLab project.
2. Under **Settings > CI/CD > Variables**, add `IOMETE_BASE_URL`, and `IOMETE_ADMIN_PASSWORD` (or `IOMETE_TOKEN`) marked **Masked**. A **Protected** variable reaches only protected branches and tags.
3. Start it from **Build > Pipelines > Run pipeline**, or on a schedule.

It runs only when started by hand, on a schedule or through the API, and only when `IOMETE_BASE_URL` is set. A push never starts it.

Every setting in [Settings](#settings) and [Optional tests](#optional-tests) works as a CI/CD variable. The ones the pipeline file lists are defaults, and a project, group, schedule or **Run pipeline** variable of the same name overrides them. So one project can test several installs, with one schedule each and its own `IOMETE_BASE_URL` and credentials. `KARATE_OPTIONS` runs part of the suite, for example `--tags @spark3`. `JAVA_IMAGE` sets the image the jobs run in, if your runners cannot pull `eclipse-temurin:21-jdk`.

The report is kept as a job artifact, and the test results show on the pipeline's **Tests** tab. A cancelled pipeline skips the cleanup job, so retry that job to remove what the run left.

## Settings

All settings go in `.env`, or `-e` for Docker. Only the first two are required.

| Setting | Description |
|---|---|
| `IOMETE_BASE_URL` | Your IOMETE console address |
| `IOMETE_ADMIN_PASSWORD` | Password of the admin account |
| `IOMETE_ADMIN_USERNAME` | Admin username. Default `admin` |
| `IOMETE_TOKEN` | An admin access token, used instead of the username and password |
| `IOMETE_DOMAIN` | An existing domain to run in, instead of one created for the run |
| `IOMETE_IMAGE_REGISTRY` | Registry and path to pull Spark images from, if you use a mirror, e.g. `registry.example.com/iomete` |
| `IOMETE_SPARK_IMAGE` | Spark image tag to test. Default `3.5.7-latest` |
| `IOMETE_ALLOW_PLATFORM_CHANGES` | `true` also runs the tests that change platform-wide state. Default off |
| `IOMETE_DATA_PLANE_STRATEGY` | With several data planes: `local` (default), `external` or `mixed` |

If a value contains `#`, `$` or quotes, export it from your shell instead and delete its line from `.env`.

## Running without make

Set the settings as environment variables, then call the Maven wrapper directly:

```powershell
$env:IOMETE_BASE_URL = "https://iomete.example.com"
$env:IOMETE_ADMIN_PASSWORD = "your-admin-password"
.\mvnw.cmd clean test
```

| Instead of | Run |
|---|---|
| `make check` | `.\mvnw.cmd test -Diomete.check=true "-Dkarate.options=--output target/karate-probe src/test/java/iomete/helpers/probe.feature"` |
| `make test-one FEATURE=<file>` | `.\mvnw.cmd test "-Dkarate.options=<file>"` |
| `make cleanup` | the three commands below, in this order |
| | `.\mvnw.cmd test "-Dkarate.options=--output target/karate-teardown src/test/java/iomete/helpers/cleanup-run-fixtures.feature"` |
| | `.\mvnw.cmd test "-Dkarate.options=--output target/karate-teardown src/test/java/iomete/helpers/compute/delete-run-computes.feature"` |
| | `.\mvnw.cmd test -Diomete.teardown=true "-Dkarate.options=--output target/karate-teardown src/test/java/iomete/helpers/cleanup-run-domain.feature"` |

## Troubleshooting

- **`IOMETE_BASE_URL is not set`**: create `.env` from `.env.example` and fill in the address.
- **`no credentials for https://...`**: set `IOMETE_ADMIN_PASSWORD` (or `IOMETE_TOKEN`).
- **`cannot reach https://...`**: check the address, and that the machine running the suite can open it in a browser (VPN, proxy, firewall).
- **`could not log in ... actual: 401`**: the username or password is wrong, or the account is not an admin.
- **`could not set up the test domain`**: the account needs admin rights, and the install needs a namespace it can give the test domain.
- **`could not create domain ... If an earlier cleanup deleted it`**: you ran `make cleanup` and then `make test-one` again. Run `make clean` to start a new run.
- **The login fails although the password is right**: values in `.env` must be written bare. Quotes become part of the value, `#` cuts it off and `$` is expanded. Export such a password from your shell instead.
- **Tests fail with `401` after a while**: the token in `IOMETE_TOKEN` expired. Remove it and set `IOMETE_ADMIN_PASSWORD` instead.
- **"Unable to locate a Java Runtime"**: install Java 21 and make sure `java -version` shows it.
- **Computes never start**: your install cannot pull the Spark image. Set `IOMETE_IMAGE_REGISTRY` to the registry your install uses.
