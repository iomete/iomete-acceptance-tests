@ignore
Feature: Does this target have a CONNECTED local (default) data plane? (plumbing)
  Pre-multi-cluster components deploy through the local plane only — external event
  streams above all: the per-stream worker comes from the plane's agent (remote agents
  answer 500) and the ingest proxy resolves upstreams with cluster-local DNS. Features
  that need one gate on this and self-skip, the way the @spark3/@spark4 pairs do. Not
  about the internal iom-event-stream (the control-plane audit sink), which exists on
  every target. Invoke via callSingle (one lookup per run):
    karate.callSingle('classpath:iomete/helpers/dataplane/has-local-plane.feature')
  Returns: hasLocalPlane (boolean).

  Scenario: look for a CONNECTED plane with id 'default'
    # a fresh install lists its local plane a little before the plane reports CONNECTED
    * def localPlane = function(planes){ return planes.find(dp => dp.id == 'default') }
    * configure retry = { count: 24, interval: 5000 }
    Given url baseUrl
    And path 'api/v1/admin/multi-cluster/data-planes'
    And retry until responseStatus != 200 || !localPlane(response) || localPlane(response).status == 'CONNECTED'
    When method get
    Then status 200
    * def hasLocalPlane = !!response.find(dp => dp.id == 'default' && dp.status == 'CONNECTED')
