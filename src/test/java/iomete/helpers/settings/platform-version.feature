@ignore
Feature: Read the platform version the target runs.
  Behaviour that ships in a given release can only be asserted on targets that have it, so a
  scenario gates on the version rather than the hostname. The version is what the local
  (default) data plane reports, which matches the control plane on a single install. A
  planes-only target has no local plane, and an external plane can run another build, so there
  the version is unknown. Builds from main report v0.0.0-<suffix>. Call it once per run with:
    karate.callSingle('classpath:iomete/helpers/settings/platform-version.feature',
                      { baseUrl: baseUrl })
  Returns:
    version  the reported version, or '' when it cannot be read

  Scenario: read the version a data plane reports
    Given url baseUrl
    And path 'api/v1/admin/multi-cluster/data-planes'
    When method get
    # no assertion: a target without this endpoint reads as an unknown version, not a failed run
    * def planes = responseStatus == 200 ? response : []
    * def local = planes.find(dp => dp.id == 'default')
    * def version = local && local.version ? local.version : ''
    * karate.log('platform version: ' + (version || 'unknown'))
