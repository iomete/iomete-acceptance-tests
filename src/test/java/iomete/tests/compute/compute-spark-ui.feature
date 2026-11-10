@lock=sql
Feature: Spark UI, the live UI of a running compute shows the query it just ran

  The console links each compute to its Spark UI (endpoints.sparkUI), which iom-core proxies to
  the driver on the compute's data plane. So the scenario runs a query of its own on the shared
  SQL compute and finds it in the driver's UI: the application is listed, and one of its Spark
  jobs carries the query's id as a job tag and its statement as the description. Only the live
  driver can answer that.

  It only reads, so it borrows the run's shared SQL compute rather than starting one. The query
  goes through the V2 SQL API, which reaches a compute on any plane, and the link already names
  the plane.

  Not tested here: the history server, which tests/job/job-run-history.feature covers.

  Background:
    * url baseUrl
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * def computeName = sqlCompute.computeName
    * def computePath = 'api/v2/domains/' + domain + '/compute'

  Scenario: the compute's Spark UI lists its application and the job of a query it just ran
    Given path computePath, sqlCompute.computeId
    When method get
    Then status 200
    * def uiBase = baseUrl + '/' + response.endpoints.sparkUI
    And match response.endpoints.sparkUI == '#regex spark-ui/.+'

    * def statement = "SELECT 'karate-spark-ui-" + runId + "-" + java.util.UUID.randomUUID() + "' AS marker"
    * def query = karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: statement })

    # one running application: the compute's driver
    Given url uiBase + '/api/v1/applications'
    When method get
    Then status 200
    And match response == '#[1]'
    And match response[0].name == 'cc-' + computeName
    And match response[0].attempts[0].completed == false
    * def appId = response[0].id

    # the driver's listener reports the job a moment after the query completes
    * configure retry = { count: 12, interval: 5000 }
    * def queryJobs = function(jobs){ return !Array.isArray(jobs) ? [] : jobs.filter(j => (j.jobTags || []).includes(query.queryId) && j.status == 'SUCCEEDED') }
    Given url uiBase + '/api/v1/applications/' + appId + '/jobs'
    And retry until responseStatus == 200 && queryJobs(response).length > 0
    When method get
    * def job = queryJobs(response)[0]
    And match job.description == statement

    # and the page the console links to renders
    Given url uiBase + '/jobs/'
    When method get
    Then status 200
    And match response contains 'Spark Jobs'
