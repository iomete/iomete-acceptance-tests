# What the tests cover

A plain-language list of the scenarios the acceptance suite checks against your IOMETE install. Each check calls the IOMETE API the way the console and client tools do and confirms a real result. Nothing is mocked.

Some checks skip when your install does not have the feature turned on, or has only one data plane. A skip is not a failure.

## Platform health and settings

- The control plane is up and every tracked service reports as working.
- An admin can override a system setting. The new value shows for admins and users, and the old value can be restored.
- Enrolled data planes are listed, at least one is connected, each shows its details and quotas, and connected planes keep checking in.

## Identity and access

- **Users and groups:** an admin creates users, finds them in the user list, manages group membership and assigns roles to groups.
- **Sign-in:** a new user signs in with the temporary password they were given. A refresh token issues a new access token, a tampered token is refused, and logout works.
- **API tokens:** a personal token works until it is changed, regenerated or deleted. Service account tokens and domain tokens also stop working once deleted.
- **Roles:** an admin role given to a group reaches its members and goes away when removed.
- **Domains:** an admin creates and deletes domains, and adds and removes domain members.
- **Service accounts:** owners and IAM managers can manage who uses a service account. Unrelated users cannot.
- **Resource sharing:** a resource owner grants and revokes access to a member. Non-owners cannot.
- **Resource groups and namespaces:** a role on a resource group gives access to the resources in it. A namespace is closed to members until a domain role includes it.
- **Directory integrations:** users and groups sync in from LDAP and are removed when the filter no longer matches them. An OIDC provider can be set up with manually entered endpoints and starts a sign-in.

## Computes

- A compute starts, stops, accepts configuration changes, restarts and still runs SQL.
- Clients connect through each advertised connection string (JDBC/Thrift, Arrow Flight SQL, Spark Connect), and a bad token is refused.
- The console shows the running driver, its logs and the live Spark UI.
- A compute with the query accelerator turned on runs queries through it.
- A compute placed on a chosen data plane starts on that plane.
- A compute with an attached volume starts and keeps working after the volume is deleted.

## SQL

- **Query lifecycle:** submit, poll, read results (including large and paged results), on both the current and the previous SQL API.
- **DDL:** create, alter, drop, describe, show tables, show the create statement, create-table-as-select, and their error cases.
- **DML:** insert, update, delete and merge, and their error cases.
- **Reading data:** count, filter, sort and aggregate over seeded tables.
- **Failures:** syntax errors, missing tables or columns, Spark-version behavior for division by zero, very long statements, special characters, and multiple statements.
- **Cancel:** a running query can be cancelled by its user or an admin, and records who cancelled it.
- **Monitoring:** query metadata, performance metrics, the Spark plan graph, and live duration for running queries.
- **CSV export:** a finished query exports its header and every row.
- **Schema browser:** browse from catalog to database to table to snapshots. The current and previous API return the same listings, table details, column types, partitions, views, and not-found and access errors. Secret-looking table properties are hidden.
- **Compatibility:** the current and previous SQL APIs work side by side on the same compute, and an older compute gives a clear error.
- **Worksheets:** saved SQL is stored and comes back, and edits replace it.
- **Table discovery:** an Iceberg table can be registered from its storage folder, and a compute reloads its access rules when asked.

## Data catalog

- A table created with SQL shows up in the catalog with its columns, and later changes are picked up on the next sync.
- Catalog search finds tables by name.
- Catalog metadata is visible to domain members only.
- Admins edit a catalog's description, properties and tags, and give domains access to catalogs or take it away.
- A domain changes its Spark settings and catalog.
- External catalogs can be attached and connection-checked: an Iceberg REST catalog and a JDBC catalog. Passwords are hidden when read back.
- Catalog lists do not show plain-text secrets.
- **Private domains:** owners create, test and delete their own catalogs. Members can read them and browse storage. Platform admins cannot see them or give global catalogs to them.

## Data security

- **Enforced during queries:** deny a whole table, deny a single column, filter rows, mask a column, mask a tagged column, and deny a metastore (non-Iceberg) table.
- The admin access check names the policies that decide what a user can access.
- **Private domains:** owners create, update and delete access, mask, row-filter and tag policies, and tag their own columns.

## Audit

- Reading a table appears in the admin audit log.

## Jobs

- A Spark job runs to completion and shows its pod, logs and events. A retry can be stopped.
- A job managed with the SDK is found by name, runs with overrides, logs output, and can be cancelled.
- A scheduled job starts on its own and completes.
- A streaming job starts running, shows its output, and stops on request.
- Finished runs appear in the Spark applications list and the Spark History server.
- A job placed on a chosen data plane runs on that plane.
- A marketplace app is published, updated, deployed as a job (using the update) and removed.
- A Docker registry's credentials become a pull secret, and a tag alias decides which image a run uses.

## Event streams

- A stream is created, scaled, stopped, updated, started and deleted.
- Every event in a batch arrives exactly once.
- Simple, date/time, nested, list and map values reach the table unchanged. Missing fields become NULL.
- A column added to a live table is picked up by later events.

## Table maintenance

- An admin turns automated maintenance on and off for a catalog.
- Per-table settings override the catalog's and are written to the Iceberg table.
- Maintenance runs started by hand actually rewrite the table.

## Namespaces and quotas

- Namespaces and quotas are listed for each data plane, for admins and for domains.
- Quotas report what is actually running, such as a compute's driver.
- The same namespace name on different data planes can be assigned to a domain without a conflict. Assigning the exact same pair twice is refused.

## Storage

- A storage connection check with correct keys passes every operation, and a wrong key fails.
- The storage browser lists a table's data and metadata files.

## Secrets

- Secrets are created, listed, updated and deleted through each secret API, at admin, global and domain level.
- Only users with permission can see a domain secret, and a deleted secret disappears.
- A Vault connection accepts the right token and refuses a wrong one. A saved Vault config lists its secrets.

## Notifications

- The email integration's test message arrives. A failed run emails only its failure subscribers, and muting stops the emails.
- Webhooks (generic and chat apps) get their test message and a failed run's alert.

## Git

- A GitLab or GitHub repository is registered, its files and branches are listed, and it can be checked out. A credential the provider refuses cannot register a repository.

## Jupyter

- A Jupyter container starts and serves JupyterLab with its token, stops serving when stopped, and serves again after an update and restart.

## Dashboard

- Recently viewed items are kept separate for each domain a user belongs to.

## AI model gateway

- The provider list shows each provider's sign-in methods and API formats.
- Admins add, read, update and remove provider keys. Key values are never returned, and access depends on the admin's role.
- Connections and models are created, read, replaced, turned off and removed for the supported cloud and model providers. Invalid settings are refused.
- A connection can be tested without saving it.
- Chat requests reach the provider. Missing tokens, unknown or turned-off models and rejected keys return clear errors with a request id.

## MCP server (for AI agents)

- The tool list stays backward compatible.
- Agents run queries, page through results, view complex values as JSON and see failed EXPLAINs as failures.
- Agents cancel a running query after confirming it, and are told when a query has already finished.
- New queries go to the SQL engine version the platform setting chooses, and queries on either version can be read back and cancelled.
- Agents see which data plane each compute runs on.

## Your own tests

- Anything in `custom-tests/` runs with the rest of the suite. See `custom-tests/example.feature`.
