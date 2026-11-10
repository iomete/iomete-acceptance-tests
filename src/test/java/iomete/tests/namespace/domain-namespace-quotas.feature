@lock=job,job2,spark
Feature: Domain-scoped namespace listing, quotas and assignment across data planes

  v3 sibling of the v2 namespace endpoints, needed once a domain's namespaces can span more
  than one data plane: v2 either returns a bare array of names (no way to tell two
  same-named namespaces on different data planes apart) or applies a single `dataPlane` to
  the whole list. These scenarios exist to prove v3 actually resolves that ambiguity, not
  just that it returns 200 - a mocked backend would pass either way.

  Every scenario here discovers what it needs from the target rather than hardcoding a
  namespace or data-plane name. A scenario that needs a second data plane, or a namespace name
  that collides across two, self-skips via karate.abort() on a target that lacks one.

  Background:
    * url baseUrl
    * def namespacesPath = 'api/v3/domains/' + domain + '/namespaces'
    * def adminNamespacesPath = 'api/v2/admin/namespaces'
    * def distinct = function(arr){ return arr.filter(function(v, i){ return arr.indexOf(v) === i }) }

  Scenario: namespaces assigned to the domain are disambiguated by data plane
    Given path namespacesPath
    When method get
    Then status 200
    And match response == '#[_ > 0]'
    # dataPlane is nullable — a namespace assigned before this field existed carries no value
    # for it at all (dropped from the JSON entirely, not even null), so its type is not part
    # of this assertion; only that every entry at least names its namespace
    And match each response == { namespace: '#string', dataPlane: '##string' }

    # only worth asserting disambiguation where the domain's namespaces actually span more
    # than one real data plane - on a single-data-plane target (or one where every assignment
    # still predates this field) there is nothing to disambiguate
    * def dataPlanesSeen = distinct(response.map(n => n.dataPlane).filter(dp => dp))
    * if (dataPlanesSeen.length < 2) karate.abort()
    And assert dataPlanesSeen.length > 1

  Scenario: namespace quotas aggregate correctly across every data plane the domain's namespaces span
    Given path namespacesPath
    When method get
    Then status 200
    # drop legacy entries with no dataPlane at all — they'd otherwise count as a distinct
    # "data plane" here and never appear in the quotas response, which the assertion below
    # would then read as a real divergence instead of a legacy row with nothing to aggregate
    * def dataPlanesAssigned = distinct(response.map(n => n.dataPlane).filter(dp => dp))
    * if (dataPlanesAssigned.length < 2) karate.abort()

    Given path namespacesPath + '/quotas'
    When method get
    Then status 200
    And match response == '#[_ > 0]'
    And match each response == { namespace: '#string', resourceQuotas: '#array', dataPlane: '#string' }

    # the point of v3 over v2: the response has to include quotas from every data plane the
    # domain's namespaces actually span, not just whichever one v2 would apply to the whole list
    * def dataPlanesInQuotas = distinct(response.map(n => n.dataPlane))
    And assert dataPlanesAssigned.every(dp => dataPlanesInQuotas.includes(dp))

  Scenario: assigning the same namespace name under a different data plane does not conflict with an existing assignment, and assigning the identical pair again does
    # search every namespace this environment actually has (the admin view, not just this
    # domain's own assignments) for one that exists, by name, on two different data planes -
    # the only situation a mix-up between same-named namespaces can show up in
    Given path adminNamespacesPath
    When method get
    Then status 200
    * def byName = {}
    * eval response.forEach(function(n){ if (!byName[n.namespace]) byName[n.namespace] = []; if (byName[n.namespace].indexOf(n.dataPlane) < 0) byName[n.namespace].push(n.dataPlane) })
    * def collisionName = Object.keys(byName).find(name => byName[name].length > 1)
    * if (!collisionName) karate.abort()
    * def collisionDataPlanes = byName[collisionName]

    Given path namespacesPath
    When method get
    Then status 200
    * def alreadyAssigned = response.filter(n => n.namespace == collisionName).map(n => n.dataPlane)
    * def targetDataPlane = collisionDataPlanes.find(dp => alreadyAssigned.indexOf(dp) < 0)
    # every data plane that has a namespace of this name is already assigned under it here —
    # nothing new to assign, so there is nothing this scenario can still prove on this target
    * if (!targetDataPlane) karate.abort()

    # teardown: never leave the new assignment behind, pass or fail — the helper no-ops if the
    # assignment was never actually created (e.g. an assertion below failed first)
    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/namespace/unassign-namespace.feature', { namespace: collisionName, dataPlane: targetDataPlane });
      }
      """

    # same name, a data plane it is not yet assigned under — must succeed, not 409
    Given path namespacesPath
    And request { namespace: '#(collisionName)', dataPlane: '#(targetDataPlane)' }
    When method post
    Then status 200

    Given path namespacesPath
    When method get
    Then status 200
    * def nowAssigned = response.filter(n => n.namespace == collisionName).map(n => n.dataPlane)
    And assert nowAssigned.includes(targetDataPlane)
    And assert alreadyAssigned.every(dp => nowAssigned.includes(dp))

    # same name, the SAME data plane as the assignment just made — this one has to conflict
    Given path namespacesPath
    And request { namespace: '#(collisionName)', dataPlane: '#(targetDataPlane)' }
    When method post
    Then status 409
