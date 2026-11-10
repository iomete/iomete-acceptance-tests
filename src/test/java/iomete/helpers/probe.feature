Feature: Check the environment is usable before the suite spends twenty minutes on it.

  Evaluating karate-config.js is most of the check: it mints the admin token and makes sure
  the domain and its namespace exist, which is the setup every scenario shares. When that
  cannot be done there is nothing to test against, and running the suite only turns one
  broken environment into fifty-seven identical failures.

  The workflow runs this first and skips the suite when it fails. Run it yourself with
  `make check`. Targeted by path and never scanned, so it carries no @ignore.

  Scenario: the suite can authenticate and reach its domain
    # `make check` creates nothing, so it only checks the admin can manage domains
    Given url baseUrl
    And path 'api/v1/admin/domains'
    When method get
    Then status 200
    # a given domain must already exist; the check reads it rather than creating it
    * if (checkOnly && domainGiven && !response.find(d => d.name == domain)) karate.fail('domain ' + domain + ' (IOMETE_DOMAIN) does not exist')

    # a real run also needs its domain to have a namespace
    * def namespaces = checkOnly ? null : karate.http(baseUrl + '/api/v1/domains/' + domain + '/namespaces').headers({ 'X-API-Token': token, Authorization: 'Bearer ' + token }).get()
    * if (!checkOnly && (namespaces.status != 200 || namespaces.body.length == 0)) karate.fail('domain ' + domain + ' has no namespace: status ' + namespaces.status)

    # A fresh install lists no data plane at first, and the suite reads the local plane once per run
    * def localPlane = function(planes){ return planes.find(dp => dp.id == 'default') }
    * configure retry = { count: 60, interval: 5000 }
    # the karate.http call above leaves the url on the namespace listing
    Given url baseUrl
    And path 'api/v1/admin/multi-cluster/data-planes'
    And retry until responseStatus != 200 || (response.length > 0 && (!localPlane(response) || localPlane(response).status == 'CONNECTED'))
    When method get

    # The deployed IOMETE version, for the run's report. It never fails the probe; a run that
    # stops before this point reports the version as unknown.
    Given path 'api/v1/data-planes/general-settings'
    When method get
    * def found = responseStatus == 200 && karate.typeOf(response) == 'list' ? response.filter(s => s.name == 'iometeVersion' && s.value) : []
    * if (found.length > 0) karate.write(found[0].value, 'iomete-version.txt')
    * def version = found.length > 0 ? found[0].value : 'unknown'
    * def where = checkOnly && domainOwnedByRun ? 'a new domain for each run' : 'domain "' + domain + '"'
    * eval java.lang.System.out.println('Ready: ' + baseUrl + ' runs IOMETE ' + version + ', and the suite will work in ' + where + '.')
