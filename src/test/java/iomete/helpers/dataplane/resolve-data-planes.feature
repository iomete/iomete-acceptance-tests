@ignore
Feature: Resolve which data planes this run's strategy may deploy to (plumbing).
  Called once per run from karate-config.js (via callSingle) when IOMETE_DATA_PLANE_STRATEGY
  is not 'local'. Returns { planes: [...] } — the ordered list dataPlaneFor(name) hashes into;
  an empty list means "behave as local". A plane is DEPLOYABLE when it is CONNECTED and has a
  namespace assigned to the suite's domain: connectivity and namespace assignment are
  independent, and a compute needs both. The compute-create API cannot say whether a plane is
  connected, which is why this check lives here, up front, instead of failing a warm-up
  ten minutes into the run. A connected plane missing the assignment gets one HERE, from
  the namespaces the plane itself reported, so enrolling a plane needs no manual admin
  step before the strategy can use it.

  external -> only deployable planes other than 'default'. None at all FAILS the run: a run
              explicitly asked to test external planes must not silently pass by deploying
              everything to the local one.
  mixed    -> every deployable plane, 'default' included. With no external plane the strategy
              degrades to local (planes: []) with a loud log line, so 'mixed' is safe to set
              on a workflow that also targets single-plane environments.

  Scenario: list the connected data planes and intersect with the domain's namespaces
    Given url baseUrl
    And path 'api/v1/admin/multi-cluster/data-planes'
    When method get
    Then status 200
    * def connected = response.filter(dp => dp.status == 'CONNECTED').map(dp => dp.id)

    Given url baseUrl
    And path 'api/v3/domains/' + domain + '/namespaces'
    When method get
    Then status 200
    # a legacy assignment carries no dataPlane at all — it cannot prove a plane is deployable
    * def withNamespace = response.map(n => n.dataPlane).filter(dp => dp)

    # A CONNECTED plane the domain cannot deploy to yet gets a namespace assigned here, from
    # what the plane itself reported — never iomete-system. Like the domain and the node
    # types, an assignment is shared and never deleted: it is not a run fixture, and
    # unassigning would pull it out from under a concurrent run.
    * def unassigned = connected.filter(dp => !withNamespace.includes(dp))
    Given url baseUrl
    And path 'api/v2/admin/namespaces'
    When method get
    Then status 200
    * def adminNamespaces = response
    * def assignMissing =
      """
      function() {
        var assigned = [];
        for (var i = 0; i < unassigned.length; i++) {
          var dp = unassigned[i];
          var candidate = adminNamespaces.find(n => n.dataPlane == dp && n.namespace != 'iomete-system');
          if (!candidate) {
            karate.log('data plane ' + dp + ' is CONNECTED but reports no assignable namespace — leaving it out');
            continue;
          }
          karate.log('assigning namespace ' + candidate.namespace + ' to domain ' + domain + ' on data plane ' + dp);
          karate.call('classpath:iomete/helpers/namespace/assign-namespace.feature', { baseUrl: baseUrl, domain: domain, namespace: candidate.namespace, dataPlane: dp });
          assigned.push(dp);
        }
        return assigned;
      }
      """
    * def withNamespace = withNamespace.concat(unassigned.length > 0 ? assignMissing() : [])

    # sorted, so dataPlaneFor's hash lands on the same plane whatever order the API answers in
    * def deployable = connected.filter(dp => withNamespace.includes(dp)).sort()
    * def external = deployable.filter(dp => dp != 'default')

    * if (strategy == 'external' && external.length == 0) karate.fail('data-plane strategy "external": no CONNECTED external data plane has a namespace assigned to domain ' + domain + ' (connected: [' + connected.join(', ') + '], with a namespace for the domain: [' + withNamespace.join(', ') + '])')
    * def planes = strategy == 'external' ? external : (external.length > 0 ? deployable : [])
    * if (planes.length == 0) karate.log('data-plane strategy "mixed": no deployable external data plane on this target, degrading to local (connected: [' + connected.join(', ') + '])')
    * if (planes.length > 0) karate.log('data-plane strategy "' + strategy + '": deploying across [' + planes.join(', ') + ']')
