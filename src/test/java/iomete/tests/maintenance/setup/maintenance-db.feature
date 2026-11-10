@ignore
Feature: Database in the maintenance catalog that the maintenance tests create tables in, invoked once per run via karate.callSingle.
  Runs on the shared SQL compute, which a full run starts before this catalog exists. Two things
  lag behind on it: the catalog's access policy (~10s to arrive, answered `Permission denied`)
  and, on Spark 4, the catalog itself (~40s, answered `REQUIRES_SINGLE_PART_NAMESPACE`, Spark
  reading the catalog name as a spark_catalog namespace). The first CREATE DATABASE is retried
  on those two answers and only those.
  Returns: catalogName, computeName, database.

  Scenario: create the database once access to the catalog has arrived
    * def catalog = karate.callSingle('classpath:iomete/tests/maintenance/setup/maintenance-catalog.feature', { domain: domain })
    * def catalogName = catalog.catalogName
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * def computeName = sqlCompute.computeName
    * def database = 'karate_maintenance_db'

    * def statement = 'CREATE DATABASE IF NOT EXISTS ' + catalogName + '.' + database

    # Retry only while the catalog or its policy has not arrived: anything else is a real
    # failure and must fail now, with its message. Either answer can come back at submit (500)
    # or as a FAILED query, so both are read; a fresh query per attempt, since a failed one
    # never changes. 40 attempts 3s apart, a few times the slower of the two lags.
    * def attempt =
      """
      function() {
        var o = karate.call('classpath:iomete/helpers/query/run-query-v2-as.feature', { userToken: token, computeName: computeName, statement: statement });
        o.error = o.submitStatus != 200 ? 'refused at submit (' + o.submitStatus + '): ' + karate.toJson(o.submitBody)
                : o.status != 'COMPLETED' ? o.status + ': ' + o.queryResponse.errorMessage : null;
        return o;
      }
      """
    # Spark 3.5 reports the catalog lag as _LEGACY_ERROR_TEMP_1055, Spark 4 as REQUIRES_SINGLE_PART_NAMESPACE
    * def lagging = ['Permission denied', 'REQUIRES_SINGLE_PART_NAMESPACE', '_LEGACY_ERROR_TEMP_1055']
    * def createUntilAllowed =
      """
      function() {
        var o;
        for (var i = 0; i < 40; i++) {
          o = attempt();
          if (!o.error || !lagging.some(function(m){ return o.error.indexOf(m) >= 0 })) return o;
          karate.log('CREATE DATABASE not allowed yet, waiting for the catalog to reach the compute (' + (39 - i) + ' attempt(s) left): ' + o.error.substring(0, 200));
          java.lang.Thread.sleep(3000);
        }
        return o;
      }
      """
    * def outcome = createUntilAllowed()
    * if (outcome.error) karate.fail('CREATE DATABASE ' + outcome.error)
