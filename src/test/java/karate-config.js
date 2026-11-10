function fn() {
  // Which IOMETE install to run against. There is no default, so a run never lands somewhere unintended.
  let baseUrl = karate.properties['iomete.baseUrl']
    || java.lang.System.getenv('IOMETE_BASE_URL');
  if (!baseUrl) {
    throw new Error('IOMETE_BASE_URL is not set: set it to your IOMETE console address, e.g. https://iomete.example.com');
  }
  // a trailing slash would make every `path` build '//api/...'
  baseUrl = baseUrl.replace(/\/+$/, '');
  if (!/^https?:\/\//i.test(baseUrl)) {
    throw new Error('IOMETE_BASE_URL must start with https:// or http://, e.g. https://iomete.example.com (got "' + baseUrl + '")');
  }
  checkReachable(baseUrl);

  karate.configure('connectTimeout', 15000);
  karate.configure('readTimeout', 60000);

  // Shared by the logging mask and redact() below.
  const maskPatterns = [
    { regex: '(password=)[^&]*', replacement: '$1***' },
    // a Jupyter container's lab URL carries its access token as a query parameter
    { regex: '(token=)[^&"\\s]*', replacement: '$1***' },
    // Slack and Teams webhook URLs carry their secret in the path or, for Teams Workflows, the sig parameter
    { regex: '(hooks\\.slack\\.com/)[^"\\s]*', replacement: '$1***' },
    { regex: '(webhook\\.office\\.com/)[^"\\s]*', replacement: '$1***' },
    { regex: '((?:logic\\.azure|powerplatform)\\.com[^"\\s]*[?&]sig=)[^&"\\s]*', replacement: '$1***' },
    // catalog properties carry secrets as {"key": "password", "value": "..."}
    { regex: '("key"\\s*:\\s*"[^"]*(?:password|secret|token)[^"]*"\\s*,\\s*"value"\\s*:\\s*")[^"]*', replacement: '$1***' },
    // a service-account key stored as a provider key's value is a JSON string, so the jsonPath
    // mask below cannot reach the PEM inside it (its newlines are escaped, so no quote ends it)
    { regex: '-----BEGIN [A-Z ]*PRIVATE KEY-----[^"]*', replacement: '***' }
  ];

  // Keeps credentials out of the console and the karate-reports artifact. Set before the
  // first request so the bootstrap login below is covered too.
  karate.configure('logging', {
    mask: {
      headers: ['X-API-Token', 'Authorization'],
      // recursive: GET /auth/tokens returns a list, so '$.token' would miss every entry
      jsonPaths: [
        '$..token', '$..access_token', '$..refresh_token', '$..accessToken', '$..refreshToken',
        '$..password', '$..temporaryPassword', '$..newPassword', '$..confirmPassword', '$..bindCredential', '$..readCredential',
        // an S3 secret key, sent in the storage connection check's body
        '$..secretKey',
        // a Generic webhook's signing secret, returned once on create
        '$..signingSecret',
        // a Google service-account key file
        '$..private_key',
        // an SSO client secret, which the OIDC integration's GET returns
        '$..secret'
      ],
      patterns: maskPatterns
    }
  });

  const runId = resolveRunId();

  let token = karate.properties['iomete.token']
    || java.lang.System.getenv('IOMETE_TOKEN');
  const givenToken = !!token;

  if (!token) {
    // No token given, so mint one from the admin login instead. A token value can't be
    // provisioned, but the admin login is stable, so a rebuilt environment still works.
    const username = karate.properties['iomete.adminUsername']
      || java.lang.System.getenv('IOMETE_ADMIN_USERNAME')
      || 'admin';
    const password = karate.properties['iomete.adminPassword']
      || java.lang.System.getenv('IOMETE_ADMIN_PASSWORD');

    if (!password) {
      throw new Error('no credentials for ' + baseUrl + ': set IOMETE_TOKEN to use a token'
        + ' directly, or IOMETE_ADMIN_PASSWORD to mint one'
        + ' (IOMETE_ADMIN_USERNAME defaults to "admin")');
    }

    // Minted once per run. baseUrl is passed because config is not returned yet. Minting replaces
    // a token of the same name, so the name carries the run id.
    try {
      token = karate.callSingle('classpath:iomete/helpers/user/admin-token.feature', {
        baseUrl: baseUrl,
        username: username,
        password: password,
        tokenName: 'karate-e2e-admin-' + runId
      }).accessToken;
    } catch (e) {
      throw setupError('could not log in as "' + username + '"', e);
    }
  }

  // host:port as JDBC drivers want it in a connection string, with the default port spelled out
  const gatewaySsl = /^https:/i.test(baseUrl);
  const authority = baseUrl.replace(/^[a-zA-Z]+:\/\//, '').split('/')[0];
  const gatewayHostPort = authority.indexOf(':') > 0 ? authority : authority + (gatewaySsl ? ':443' : ':80');

  // Where Spark images are pulled from. IOMETE_IMAGE_REGISTRY points the suite at a mirror;
  // unset means the public IOMETE registry.
  const imageRegistry = String(karate.properties['iomete.imageRegistry']
    || java.lang.System.getenv('IOMETE_IMAGE_REGISTRY') || '').trim().replace(/\/+$/, '');
  const imageRef = function (nameAndTag) {
    return (imageRegistry || 'iomete.azurecr.io/iomete') + '/' + nameAndTag;
  };

  // The Spark image under test: a full reference as given, or a bare tag (e.g. 4.1.3-v1) of spark-py.
  // sparkMajor lets version-divergent scenarios branch or self-skip.
  const requestedImage = String(karate.properties['iomete.sparkImage']
    || java.lang.System.getenv('IOMETE_SPARK_IMAGE')
    || 'spark-py:3.5.7-latest').trim();
  const sparkImage = requestedImage.indexOf('/') < 0
    ? imageRef(requestedImage.indexOf(':') < 0 ? 'spark-py:' + requestedImage : requestedImage)
    : requestedImage;
  const sparkTag = sparkImage.substring(sparkImage.lastIndexOf(':') + 1);
  const sparkMajor = parseInt(sparkTag, 10);
  if (isNaN(sparkMajor)) {
    throw new Error('cannot parse a Spark major version from image tag "' + sparkTag + '"'
      + ' (image ' + sparkImage + '); the tag must start with the version, e.g. 4.1.3-latest');
  }
  // The image tag as a name suffix (4.1.3-latest -> "4-1-3-latest"), so two images in one run get
  // their own computes. Databases are keyed by run only, so the image legs of a run must not run
  // in parallel. Lower-cased, since compute names must match ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$.
  const computeSuffix = sparkTag.replace(/[^a-zA-Z0-9]+/g, '-').replace(/^-+|-+$/g, '').toLowerCase();
  // the same key for SQL identifiers, which take no hyphens
  const imageKey = computeSuffix.replace(/-/g, '_');

  // Size of the suite's own node types, in millicores and MB. Unset keeps the defaults;
  // a single-node target sets them smaller so its Spark pods can schedule.
  const nodeTypeCpu = parseInt(karate.properties['iomete.nodeTypeCpu']
    || java.lang.System.getenv('IOMETE_NODE_TYPE_CPU') || '0', 10);
  const nodeTypeMemory = parseInt(karate.properties['iomete.nodeTypeMemory']
    || java.lang.System.getenv('IOMETE_NODE_TYPE_MEMORY') || '0', 10);
  // CPU of the run's shared SQL compute, which every query lane leans on; unset sizes it like the rest
  const sharedComputeCpu = parseInt(karate.properties['iomete.sharedComputeCpu']
    || java.lang.System.getenv('IOMETE_SHARED_COMPUTE_CPU') || '0', 10);

  // Path to a custom SSL certificate (PEM format) for Spark Connect connections. If set, the
  // certificate is added to the trust store so Spark Connect can connect to targets with
  // self-signed or custom CA certificates (like the Python example_custom_cert.py quickstart).
  const sparkConnectCert = String(karate.properties['iomete.sparkConnectCert']
    || java.lang.System.getenv('IOMETE_SPARK_CONNECT_CERT') || '').trim() || null;

  // The fixtures a run shares across features, named once here for both their setup and
  // `make cleanup-run`. Everything else a scenario creates, it deletes itself.
  const fixtures = {
    db: 'spark_catalog.karate_db_' + runId,
    ddlDb: 'spark_catalog.karate_ddl_db_' + runId,
    dmlDb: 'spark_catalog.karate_dml_db_' + runId,
    securityDb: 'spark_catalog.karate_security_db_' + runId,
    securityUser: 'karate-security-user-' + runId,
    maintenanceCatalog: 'karate_maintenance_' + runId,
    maintenancePolicy: 'karate-maintenance-' + runId,
    eventStreamDb: 'spark_catalog.karate_es_db_' + runId,
    // The table the data catalog features share, indexed once per run. Keyed by image too, since
    // the catalog keeps a row after the Spark table is dropped.
    catalogDb: 'spark_catalog.karate_catalog_db_' + imageKey + '_' + runId,
    catalogTable: 'karate_catalog_table_' + imageKey + '_' + runId,
    // Two more tables the same sync indexes, for tests/catalog/catalog-resync.feature: it adds a
    // column to the first and drops the second in Spark, then syncs again. cleanup-run drops
    // every table in catalogDb, so they need no teardown of their own.
    catalogEvolvedTable: 'karate_catalog_evolved_' + imageKey + '_' + runId,
    catalogDroppedTable: 'karate_catalog_dropped_' + imageKey + '_' + runId,
    catalogSyncJob: 'karate-catalog-sync-' + runId,
    // The client of the OIDC integration tests/identity/oidc-manual-endpoints.feature creates. Not
    // shared: the scenario deletes it itself, and cleanup-run only removes one a cancelled run left.
    oidcClient: 'karate-oidc-' + runId,
    // The SQL and security computes are run-owned like the databases: created once per run
    // via callSingle, shared across features, dropped by cleanup-run. Still keyed by image
    // too — the two e2e legs share one run id and must not share a compute.
    sqlCompute: 'karate-tests-' + computeSuffix + '-' + runId,
    securityCompute: 'karate-security-' + computeSuffix + '-' + runId
  };
  // Tests that change platform-wide state (a setting, a marketplace app, a registry, the Model
  // Gateway's provider model) run only when this is true. Customers opt in; our CI does.
  const allowPlatformChanges = ('' + (karate.properties['iomete.allowPlatformChanges']
    || java.lang.System.getenv('IOMETE_ALLOW_PLATFORM_CHANGES') || '')).toLowerCase() == 'true';
  // Whether to build the pre-V2 compatibility compute and run the one scenario that needs it.
  // It is a whole warm compute for a single check, so only the runs that gate a release ask
  // for it; a pull request gets the capacity back instead.
  const includeCompat = ('' + (karate.properties['iomete.includeCompat']
    || java.lang.System.getenv('IOMETE_INCLUDE_COMPAT') || '')).toLowerCase() == 'true';

  const config = {
    baseUrl: baseUrl,
    token: token,
    gatewayHostPort: gatewayHostPort,
    gatewaySsl: gatewaySsl,
    runId: runId,
    fixtures: fixtures,

    imageRef: imageRef,
    sparkImage: sparkImage,
    sparkMajor: sparkMajor,
    computeSuffix: computeSuffix,
    nodeTypeCpu: nodeTypeCpu,
    nodeTypeMemory: nodeTypeMemory,
    sharedComputeCpu: sharedComputeCpu,
    sparkConnectCert: sparkConnectCert,
    includeCompat: includeCompat,
    allowPlatformChanges: allowPlatformChanges
  };

  // The gate for a test that changes platform-wide state: false (with a log line) to skip it.
  // Our CI turns it on in its workflow.
  config.platformChangesAllowed = function() {
    if (allowPlatformChanges) return true;
    karate.log('IOMETE_ALLOW_PLATFORM_CHANGES is not true, skipping a test that changes platform-wide state');
    return false;
  };

  // Every request runs as this admin token unless a feature sets `configure headers` to another
  // user's token (see helpers/query/run-query-v2-as.feature).
  karate.configure('headers', { 'X-API-Token': token, Authorization: 'Bearer ' + token });


  // The platform version, for scenarios that assert behaviour a release introduced. Gate them
  // with platformAtLeast('4.0.1'): builds from main (0.0.0-...) count as newer than any release,
  // and an unknown version as older, so an unreadable version skips rather than fails.
  // A bare '4.0.2' matches its release candidates too; '4.0.2-rc2' gates on rc2 or later.
  let platformVersion = null;
  try {
    platformVersion = '' + karate.callSingle('classpath:iomete/helpers/settings/platform-version.feature', { baseUrl: baseUrl }).version;
  } catch (e) {
    throw setupError('could not read the IOMETE version', e);
  }
  config.platformVersion = platformVersion;
  config.platformAtLeast = function(min) {
    const parse = v => {
      const m = ('' + v).match(/^v?(\d+)\.(\d+)\.(\d+)(-.*)?/);
      if (!m) return null;
      // only dev and rc builds are ordered; any other suffix is unknown
      const pre = m[4] ? m[4].match(/^-(dev|rc)\.?(\d+)$/i) : null;
      return { core: [Number(m[1]), Number(m[2]), Number(m[3])], suffix: !!m[4], label: pre ? pre[1].toLowerCase() : null, number: pre ? Number(pre[2]) : 0 };
    };
    const have = parse(platformVersion);
    if (!have) return false;
    if (have.core.join('.') == '0.0.0') return true;
    const want = parse(min);
    if (!want || (want.suffix && !want.label)) throw new Error('platformAtLeast: unreadable version "' + min + '"');
    for (let i = 0; i < 3; i++) {
      if (have.core[i] != want.core[i]) return have.core[i] > want.core[i];
    }
    if (!want.label) return true;
    if (!have.suffix) return true;
    if (!have.label) return false;
    // dev comes before rc, then by number
    if (have.label != want.label) return have.label == 'rc';
    return have.number >= want.number;
  };

  // The domain the run works in. From 4.0.2 each run creates its own and the teardown deletes
  // it; older platforms cannot delete a domain, so they share a fixed one. IOMETE_DOMAIN uses an
  // existing domain instead, which the teardown never deletes.
  const givenDomain = karate.properties['iomete.domain'] || java.lang.System.getenv('IOMETE_DOMAIN');
  const imageHash = hashString(computeSuffix).toString(36);
  config.domainOwnedByRun = !givenDomain && config.platformAtLeast('4.0.2');
  config.domainGiven = !!givenDomain;
  if (givenDomain) {
    config.domain = '' + givenDomain;
  } else if (config.domainOwnedByRun) {
    // keyed by image too: the image legs of one run share its id, and a deleted domain's id stays reserved
    config.domain = 'karate-' + runId + '-' + imageHash;
  } else {
    config.domain = 'karate';
  }
  if (config.domain.length > 36) {
    throw new Error('domain "' + config.domain + '" is longer than the platform allows (36): '
      + (givenDomain ? 'set a shorter IOMETE_DOMAIN' : 'set a shorter IOMETE_RUN_ID'));
  }

  // Objects whose Kubernetes names would clash across run domains, which share namespaces.
  // With the fixed domain, runs share them instead.
  config.eventStream = config.domainOwnedByRun ? 'karate-es-' + runId + '-' + imageHash : 'karate-es';
  config.compatCompute = config.domainOwnedByRun ? 'karate-compat-' + runId + '-' + imageHash : 'karate-tests-compatibility';

  // The domain has to exist before any feature runs, so a feature never needs its own guard.
  // It sits after the headers above: the called feature runs as admin. The domain teardown
  // skips it, so it never creates the domain it is about to delete.
  // `make check` skips it too, so checking the setup leaves no domain behind.
  config.checkOnly = karate.properties['iomete.check'] == 'true';
  if (karate.properties['iomete.teardown'] != 'true' && !config.checkOnly) {
    try {
      karate.callSingle('classpath:iomete/helpers/domain/ensure-domain.feature', {
        baseUrl: baseUrl,
        domain: config.domain,
        mustExist: !!givenDomain
      });
    } catch (e) {
      throw setupError('could not set up the test domain "' + config.domain + '"', e);
    }
  }

  // Whether domain access goes through domain bundles. With it off, domain-level permissions are
  // not enforced, so the scenarios that assert on them skip. Read after the headers: it needs the
  // admin token, like every setup call below.
  let flags = null;
  try {
    flags = karate.callSingle('classpath:iomete/helpers/settings/feature-flags.feature', { baseUrl: baseUrl }).flags;
  } catch (e) {
    throw setupError('could not read the feature flags', e);
  }
  // == not ===: the flag arrives as a Java Boolean through the JS engine, and a missing flag
  // (an older target that doesn't serve it) has to read as off rather than throw.
  config.domainBundleAuth = flags.domainLevelBundleAuthorization == true;

  // Whether the platform reports per-priority-class quotas; with it off they are always empty.
  config.priorityClassesEnabled = flags.priorityClasses == true;

  // Whether computes take Arrow Flight connections; the console only offers them when it is on.
  config.arrowFlightEnabled = flags.arrowFlightConnection == true;

  // Whether the Jupyter container API is on; with it off every call answers 409.
  config.jupyterEnabled = flags.jupyterContainers == true;

  // Whether iom-sql serves the SQL editor's schema browser through the shared Arrow Flight
  // schema server; with it off every schema endpoint answers 409.
  config.arrowFlightDbExplorerEnabled = flags.arrowFlightForDbExplorer == true;
  // dataAccessAudit makes the admin audit endpoint read the Iceberg audit table the computes
  // write to (via the event stream) instead of Ranger's ORC files; tests/audit gates on it.
  config.dataAccessAuditEnabled = flags.dataAccessAudit == true;

  // Whether the MCP server and its /mcp route are on; the chart turns both on from one value.
  config.mcpServerEnabled = flags.mcpServer == true;
  // Where the MCP calls go; IOMETE_MCP_URL points them at a locally run server, everything else stays on baseUrl.
  config.mcpBaseUrl = (karate.properties['iomete.mcpUrl']
    || java.lang.System.getenv('IOMETE_MCP_URL') || baseUrl).replace(/\/+$/, '');
  if (!/^https?:\/\//i.test(config.mcpBaseUrl)) {
    throw new Error('IOMETE_MCP_URL must start with https:// or http://, e.g. http://localhost:8000 (got "' + config.mcpBaseUrl + '")');
  }

  // Whether the AI services (Model Gateway) are enabled: a 404 or the console's HTML page means not.
  // Gate the gateway features with aiServicesEnabled() the way others use platformAtLeast();
  // any other answer counts as enabled so a real outage fails the feature.
  let aiServicesEnabled = false;
  try {
    aiServicesEnabled = karate.callSingle('classpath:iomete/helpers/settings/ai-services.feature', { baseUrl: baseUrl }).enabled;
  } catch (e) {
    throw setupError('could not check the AI services', e);
  }
  config.aiServicesEnabled = function() {
    return aiServicesEnabled;
  };

  // What the Model Gateway answers when the provider gave it nothing to relay: its own 502/504
  // "no answer" messages (a data plane with no way out, such as an air-gapped install), and the
  // statuses a busy provider answers with (its uptime, not the route's). The features that call a
  // real provider with a fake key excuse these; the list lives here so a gateway rename is one edit.
  const gatewayNoAnswerMessages = ['backend unreachable', 'backend did not respond in time', 'backend answered with a redirect', 'backend answer was cut off', 'backend credential unavailable', 'no answer from the backend'];
  config.gatewayNoAnswer = function(status, message) {
    return (status == 502 || status == 504) && gatewayNoAnswerMessages.indexOf(message) >= 0;
  };
  config.providerBusy = function(status) {
    return status == 429 || status == 500 || status == 503;
  };

  // How computes and jobs pick a data plane: users choose a strategy, never a plane. The
  // semantics live in resolve-data-planes.feature; 'local' (the default) sends no dataPlane
  // at all, the untouched pre-multi-cluster behavior.
  const dataPlaneStrategy = ('' + (karate.properties['iomete.dataPlaneStrategy']
    || java.lang.System.getenv('IOMETE_DATA_PLANE_STRATEGY') || 'local')).toLowerCase();
  if (['local', 'external', 'mixed'].indexOf(dataPlaneStrategy) < 0) {
    throw new Error('unknown data-plane strategy "' + dataPlaneStrategy
      + '" (IOMETE_DATA_PLANE_STRATEGY): use local, external or mixed');
  }
  config.dataPlaneStrategy = dataPlaneStrategy;

  // An empty result means "behave as local". 'local' on a target without a local plane is
  // refused in dataPlaneFor, not here, so teardown and API-only features still run.
  let strategyPlanes = [];
  let localPlaneExists = true;
  // `make check` skips it: it reads the run's domain, which the check never creates, and may
  // assign namespaces to it
  if (dataPlaneStrategy != 'local' && !config.checkOnly) {
    try {
      strategyPlanes = karate.callSingle('classpath:iomete/helpers/dataplane/resolve-data-planes.feature', {
        baseUrl: baseUrl,
        domain: config.domain,
        strategy: dataPlaneStrategy
      }).planes;
    } catch (e) {
      throw setupError('could not find the data planes for strategy "' + dataPlaneStrategy + '"', e);
    }
  } else {
    try {
      localPlaneExists = karate.callSingle('classpath:iomete/helpers/dataplane/has-local-plane.feature', { baseUrl: baseUrl }).hasLocalPlane;
    } catch (e) {
      throw setupError('could not list the data planes', e);
    }
  }

  // Only the compat compute is pinned to the local plane; the SQL/security pair is run-owned
  // (see fixtures) and rotates like every other per-run fixture.
  const sharedComputeNames = [
    config.compatCompute
  ];

  // Deterministic on (name, runId), so setup, reuse and teardown resolve the same plane, and
  // runs rotate across planes.
  config.dataPlaneFor = function (name) {
    if (!localPlaneExists) {
      throw new Error('data-plane strategy "local" needs a CONNECTED local (default) data plane and '
        + baseUrl + ' has none — this is a planes-only target: run with IOMETE_DATA_PLANE_STRATEGY=external (or mixed)');
    }
    if (strategyPlanes.length == 0) return null;
    if (sharedComputeNames.indexOf(name) >= 0) return null;
    return strategyPlanes[hashString(name + runId) % strategyPlanes.length];
  };

  // karate.log skips the logging mask, so logged response text goes through this, line by
  // line: the mask's patterns, secret-named JSON fields and the run's own token.
  const secretJsonField = /("(?:token|access_token|refresh_token|accessToken|refreshToken|password|temporaryPassword|newPassword|confirmPassword|bindCredential|readCredential|secretKey|signingSecret|secret)"\s*:\s*")[^"]*/g;
  config.redact = function (text) {
    return String(text).split('\n').map(line => {
      maskPatterns.forEach(p => { line = line.replace(new RegExp(p.regex, 'g'), p.replacement); });
      line = line.replace(secretJsonField, '$1***');
      return token ? line.split(token).join('***') : line;
    }).join('\n');
  };

  // The v1/v2 split in one place: v1 only reaches local-plane computes (by design), so a
  // feature checks the plane with isRemotePlane and picks its query helper with queryFeatureFor.
  config.isRemotePlane = function (dp) {
    return !!dp && dp != 'default';
  };
  config.queryFeatureFor = function (dp) {
    return config.isRemotePlane(dp)
      ? 'classpath:iomete/helpers/query/run-query-v2.feature'
      : 'classpath:iomete/helpers/query/run-query.feature';
  };

  // Identifies this run, so anything it creates can be named apart from another run's.
  // Lower-case alphanumerics only, so one id keys both dash-separated platform names and
  // underscore-separated SQL identifiers. Kept short, because it is appended to user names.
  function resolveRunId() {
    const given = karate.properties['iomete.runId'] || java.lang.System.getenv('IOMETE_RUN_ID');
    if (given) return sanitiseRunId(given);

    // The whole run id, base36 to keep it short (11 digits -> 7 chars). Not truncated: ids are
    // allocated across all of GitHub fast enough that low digits repeat within one run's
    // lifetime. The attempt distinguishes a re-run, which reuses the id.
    const ghRunId = java.lang.System.getenv('GITHUB_RUN_ID');
    if (ghRunId) {
      const attempt = java.lang.System.getenv('GITHUB_RUN_ATTEMPT') || '1';
      const shortId = java.lang.Long.toString(java.lang.Long.parseLong('' + ghRunId), 36);
      return sanitiseRunId(shortId + 'a' + attempt);
    }
    return sanitiseRunId(generateRunId());
  }

  function sanitiseRunId(value) {
    return ('' + value).replace(/[^a-zA-Z0-9]+/g, '').toLowerCase();
  }

  // Fails fast with a plain message when the install cannot be reached. Checked once per JVM.
  // TLS errors are left to Karate's own client, which accepts private certificates.
  function checkReachable(url) {
    const done = java.lang.System.getProperty('iomete.reachable.' + url);
    if (done == 'ok') return;
    if (done) throw new Error(done);
    let problem = null;
    let connection = null;
    try {
      connection = java.net.URI.create(url).toURL().openConnection();
      connection.setConnectTimeout(10000);
      connection.setReadTimeout(10000);
      const code = connection.getResponseCode();
      if (code == 404) {
        problem = url + ' answered HTTP ' + code + ': check IOMETE_BASE_URL is your IOMETE console address';
      }
    } catch (e) {
      if (!/SSL|certificat|PKIX/i.test('' + e)) {
        problem = 'cannot reach ' + url + ': check IOMETE_BASE_URL and that this machine can reach it (' + firstLine(e) + ')';
      }
    } finally {
      if (connection) connection.disconnect();
    }
    java.lang.System.setProperty('iomete.reachable.' + url, problem || 'ok');
    if (problem) throw new Error(problem);
  }

  // Turns a failed setup call into one sentence saying what to check. callSingle stays inline at
  // the call site: this engine swallows its failure inside a nested function.
  function setupError(what, e) {
    const cause = firstLine(e);
    let hint = 'the full output above has the details';
    if (/actual: 40[13]\b/.test(cause)) hint = givenToken ? 'check IOMETE_TOKEN is a valid admin access token' : 'check the credentials, and that the account is an admin';
    else if (/actual: 404\b/.test(cause)) hint = 'check IOMETE_BASE_URL is your IOMETE console address';
    else if (/actual: 5\d\d\b/.test(cause)) hint = 'the install answered with a server error';
    return new Error(what + ' on ' + baseUrl + ': ' + hint + ' (' + cause + ')');
  }

  // The innermost cause of an error (e.g. "expected status: 200, actual: 401"), short enough for one line.
  function firstLine(e) {
    const lines = ('' + e).split('\n').map(l => l.trim()).filter(l => l.indexOf('Error: ') == 0);
    let text = lines.length ? lines[lines.length - 1] : ('' + e).split('\n')[0];
    const cut = text.lastIndexOf('.feature - ');
    if (cut >= 0) text = text.substring(cut + '.feature - '.length);
    return text.replace(/^Error: /, '').substring(0, 300);
  }

  // A single plain loop in its own function: this JS engine silently drops writes from a
  // nested for to an outer-body let.
  function hashString(value) {
    let h = 0;
    for (let i = 0; i < value.length; i++) {
      h = (h * 31 + value.charCodeAt(i)) % 2147483647;
    }
    return h;
  }

  // Outside CI, generate an id once and keep it in target/, so every feature and the teardown
  // targets (separate JVMs) share it. `make test` cleans target/ first, so each full run gets a new one.
  function generateRunId() {
    const cached = java.lang.System.getProperty('iomete.generatedRunId');
    if (cached) return cached;

    const idFile = java.nio.file.Paths.get('target', '.karate-run-id');
    let runId = java.nio.file.Files.exists(idFile)
      ? ('' + java.nio.file.Files.readString(idFile)).trim()
      : null;

    if (!runId) {
      runId = 'l' + ('' + new Date().getTime()).slice(-8);
      // features start in parallel, so the first one to claim the id wins and the rest use it
      const claimed = java.lang.System.getProperties().putIfAbsent('iomete.generatedRunId', runId);
      if (claimed) return '' + claimed;

      try {
        java.nio.file.Files.createDirectories(idFile.getParent());
        java.nio.file.Files.writeString(idFile, runId);
      } catch (e) {
        karate.log('could not persist the run id, teardown targets will not match: ' + e);
      }
    }
    java.lang.System.setProperty('iomete.generatedRunId', runId);
    return runId;
  }

  return config;
}
