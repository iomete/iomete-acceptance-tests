@ignore
Feature: Whether role grants count on this target, turning the resourceGroupRoles flag on where allowed (helper).
  Usage: karate.callSingle('classpath:iomete/helpers/settings/enable-resource-group-roles.feature').rolesCount

  Role grants on resource groups and namespaces only count with this flag on, and it is off by
  default. The helper turns it on only when IOMETE_RESOURCE_GROUP_ROLES_SET_FLAG is true, and leaves
  it on. The change takes up to about 90s to reach every service, so callers wait on the access they
  expect rather than on this call. With the flag off and not allowed to change, rolesCount is false
  and the caller skips.

  A 404 naming the flag as unknown means the target predates it, where role grants count without
  it. Any other 404 still fails.

  Scenario: read the flag, turn it on where allowed
    Given url baseUrl
    And path 'api/v1/admin/feature-flags/resourceGroupRoles'
    When method get
    * def unknownFlag = responseStatus == 404 && karate.toString(response).contains('Rollout flag not found')
    * if (responseStatus != 200 && !unknownFlag) karate.fail('unexpected answer reading the resourceGroupRoles flag: ' + responseStatus)
    * def flagKnown = responseStatus == 200
    * def globalOverride = flagKnown ? (response.overrides || []).find(o => o.scopeType == 'GLOBAL') : null
    * def flagOn = !flagKnown || (globalOverride ? globalOverride.enabled == true : response.defaultEnabled == true)
    * def turnOn = !flagOn && java.lang.System.getenv('IOMETE_RESOURCE_GROUP_ROLES_SET_FLAG') == 'true'

    * if (turnOn) karate.call('classpath:iomete/helpers/settings/set-resource-group-roles-flag.feature')
    * def rolesCount = flagOn || turnOn
    * if (!flagKnown) karate.log('resourceGroupRoles flag not known on this target, role grants are not gated there')
