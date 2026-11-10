@lock=sql
Feature: Namespace quotas report what is really running in the namespace

  The quota endpoints report the namespace's Kubernetes ResourceQuota status: v1/v2 ask the
  data plane's agent live, v3 reads what the agent last pushed to the control plane. Either
  way the usage has to account for the pods the platform really scheduled there. The anchor
  is the shared SQL compute: while it is ACTIVE its driver pod requests exactly its node
  type's CPU, so the namespace's CPU-requests usage can never be below that. Other runs share
  the namespace and change its usage under us, so every check is a lower bound from this run's
  own compute, never an exact total.

  Validation, authorization and the response shapes stay in iom-cluster's namespace
  resource tests; see the end of this file for the endpoints left out on purpose.

  Background:
    * url baseUrl
    * def sql = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })

    Given path 'api/v2/domains', domain, 'compute', sql.computeId
    When method get
    Then status 200
    And match response.driverStatus == 'ACTIVE'
    * def computeNamespace = response.namespace
    # the strategy may have put the compute on a remote plane; rows are matched on both
    * def computePlane = response.dataPlane || 'default'
    * def driverNodeTypeName = response.nodeTypes.driver

    Given path 'api/v1/admin/node-types'
    When method get
    Then status 200
    * def driverNodeType = response.find(t => t.name == driverNodeTypeName)
    And match driverNodeType == '#notnull'
    # node types are in millicores, quota rows in cores
    * def driverCpuCores = driverNodeType.cpu / 1000

    * def cpuRequests = function(row){ return row ? row.resourceQuotas.find(q => q.resourceType == 'CPU requests') : null }

  Scenario: the namespace's CPU-requests usage covers the running compute's driver (v3 quotas)
    # the pushed copy, so this also proves the push pipeline carries current usage, not just
    # limits. The copy is the agent's last push, so a push still in flight gets a few seconds.
    # A namespace with no ResourceQuota answers no quotas at all, and so does a plane whose read
    # fails; quotas are optional, so that skips with a log line
    * def computeRow = function(rows) { return rows.find(n => n.namespace == computeNamespace && n.dataPlane == computePlane) }
    # a missing row still fails: only a row with an empty quota list skips
    * def hasQuotas = function(rows) { var row = computeRow(rows); return row == null || row.resourceQuotas.length > 0 }
    * def covers = function(rows) { var cpu = cpuRequests(computeRow(rows)); return cpu != null && cpu.currentValueNumeric >= driverCpuCores }
    * configure retry = { count: 6, interval: 5000 }
    Given path 'api/v3/domains', domain, 'namespaces', 'quotas'
    And retry until responseStatus == 200 && (covers(response) || !hasQuotas(response))
    When method get
    * if (!hasQuotas(response)) karate.log('no ResourceQuota on ' + computeNamespace + ' (' + computePlane + '), skipping')
    * if (!hasQuotas(response)) karate.abort()
    And assert covers(response)
    * def cpu = cpuRequests(computeRow(response))
    * karate.log('CPU requests in ' + computeNamespace + ': ' + cpu.currentValueNumeric + ' of ' + cpu.maxValueNumeric + ' cores, driver alone requests ' + driverCpuCores)

  Scenario: quotas scoped to the compute priority class cover the running compute's driver (v3 by-resource-type)
    Given path 'api/v3/domains', domain, 'namespaces', 'quotas', 'by-resource-type'
    When method get
    Then status 200
    # empty unless the plane maps priority classes AND the namespace has a ResourceQuota scoped
    # to one, which most installs lack, so this only proves something where both exist
    * def computeRows = response.COMPUTE || []
    * def cpu = cpuRequests(computeRows.find(n => n.namespace == computeNamespace && n.dataPlane == computePlane))
    * if (!cpu) karate.log('no COMPUTE-scoped CPU requests quota on ' + computeNamespace + ' (' + computePlane + ') — skipping')
    * if (!cpu) karate.abort()
    And assert cpu.currentValueNumeric >= driverCpuCores

  Scenario: a namespace assigned to a domain answers that domain with its live usage (v1)
    # v1 assign and the v1 quota read both act on the local plane only
    * def planes = karate.callSingle('classpath:iomete/helpers/dataplane/has-local-plane.feature')
    * if (!planes.hasLocalPlane || computePlane != 'default') karate.log('compute is not on a CONNECTED local plane — the v1 assign path cannot be shown here')
    * if (!planes.hasLocalPlane || computePlane != 'default') karate.abort()

    # A domain of its own, so the suite's domain never loses a namespace mid-run. Per attempt where
    # domains can be deleted (a deleted id stays reserved); before 4.0.2 a fixed, shared one.
    * def assignDomain = domainOwnedByRun ? 'karate-ns-' + runId + '-' + java.lang.Long.toString(java.lang.System.currentTimeMillis(), 36) : 'karate-namespace-assign'
    * configure afterScenario = function(){ if (domainOwnedByRun) karate.call('classpath:iomete/helpers/domain/delete-domain.feature', { domain: assignDomain }) }
    Given path 'api/v1/admin/domains', assignDomain
    When method get
    # a missing domain answers 400 BAD_INPUT here, not 404
    Then assert responseStatus == 200 || responseStatus == 400 || responseStatus == 404
    # another run can create it in between, so a failed create only counts if the domain is still missing
    * def createDomain = function(){ try { karate.call('classpath:iomete/helpers/domain/create-domain.feature', { domainId: assignDomain }) } catch (e) { karate.log('domain create failed, checking whether another run made it:', e) } }
    * if (responseStatus != 200) createDomain()
    Given path 'api/v1/admin/domains', assignDomain
    When method get
    Then status 200

    # creating a domain does not make its creator a member, and every read below needs access;
    # membership is all it needs, so no bundle grant is written. 204 is what this answers; 409 =
    # already a member
    Given path 'api/v1/user'
    When method get
    Then status 200
    Given path 'api/v1/admin/domains', assignDomain, 'members'
    And request [ { type: 'USER', value: '#(response.username)' } ]
    When method post
    Then assert responseStatus == 201 || responseStatus == 204 || responseStatus == 409

    # Never unassigned: on the shared domain a run that removed it could pull it from under another
    # run between that run's assign and its read. 409 is the assignment an earlier run already made.
    Given url baseUrl
    And path 'api/v1/domains', assignDomain, 'namespaces', computeNamespace
    # a domain created just above can answer 403 for a few seconds
    * configure retry = { count: 15, interval: 2000 }
    And retry until responseStatus != 403
    When method post
    Then assert responseStatus == 200 || responseStatus == 409

    # the agent's live answer for the namespace now reaches this domain, the shared compute included;
    # a membership added just above can answer 403 for a few seconds
    * configure retry = { count: 15, interval: 2000 }
    Given path 'api/v1/domains', assignDomain, 'namespaces', 'quotas'
    And retry until responseStatus != 403
    When method get
    Then status 200
    * def row = response.find(n => n.namespace == computeNamespace)
    And match row == '#notnull'
    * if (row.resourceQuotas.length == 0) karate.log('no ResourceQuota on ' + computeNamespace + ', skipping')
    * if (row.resourceQuotas.length == 0) karate.abort()
    * def cpu = cpuRequests(row)
    And match cpu == '#notnull'
    And assert cpu.currentValueNumeric >= driverCpuCores

  # Left out on purpose:
  # - v1 DELETE {namespace} (unassign): it only removes iom-cluster's own mapping row, and doing
  #   it on the shared domain would race a concurrent run (see the assign scenario).
  # - {namespace}/utilization (v1, v2): the data plane's agent does not implement the call it
  #   relays to (resource-consuming-pods), so it answers 500 on every target.
  # - quotas/system-resources (v1, v2): only the tightest hard limit per resource, from the
  #   same agent call as quotas, with no usage — what is left to check is iom-cluster's unit
  #   conversion, which belongs in its tests.
  # - v2 quotas and v1/v2 by-resource-type: the same live agent call v1 quotas makes above (v3
  #   by-resource-type reads the pushed copy v3 quotas does); what differs between versions is
  #   which namespaces are gathered, which is iom-cluster logic.
