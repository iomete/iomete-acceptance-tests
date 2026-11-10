@ignore
Feature: Whether V1's domain and admin schema routes answer from V2 on this target (helper)
  Usage: karate.callSingle('classpath:iomete/tests/sql/schema-parity/setup/v1-forwarding.feature').forwarding

  V1 forwards to V2 while arrowFlightForDbExplorer is on and, from LKH-1156, the
  schemaV1ForwardToV2 rollout flag is on too (off by default). On a platform without that flag
  (404) forwarding follows arrowFlightForDbExplorer alone. Where platform-wide changes are allowed
  the flag is turned on, so the forwarding path stays covered, and left on like the other rollout
  flags the suite sets; services read flags through a cache of about a minute, so that waits.

  Scenario: read the flag, turn it on where allowed
    Given url baseUrl
    And path 'api/v1/admin/feature-flags/schemaV1ForwardToV2'
    When method get
    * def flagKnown = responseStatus == 200
    * def globalOn = flagKnown && (response.overrides || []).some(o => o.scopeType == 'GLOBAL' && o.enabled)
    * def turnOn = flagKnown && !globalOn && arrowFlightDbExplorerEnabled && platformChangesAllowed()
    * if (turnOn) karate.call('classpath:iomete/tests/sql/schema-parity/setup/enable-v1-forwarding.feature')
    * def forwarding = arrowFlightDbExplorerEnabled && (!flagKnown || globalOn || turnOn)
    * karate.log('V1 schema routes ' + (forwarding ? 'forward to V2' : 'run their own code') + (flagKnown ? '' : ' (no schemaV1ForwardToV2 flag on this platform)'))
