@ignore
Feature: Whether private domains can be created on this target, turning the privateDomains flag on where allowed (helper).
  Usage: karate.callSingle('classpath:iomete/helpers/settings/enable-private-domains.feature')
  Returns enabled, and flagKnown (false on a build from before the flag, or when the flag is off
  and IOMETE_PRIVATE_DOMAINS_SET_FLAG is not true, since the admin read hides it).

  Creating a private domain needs the privateDomains rollout flag, which is off by default. Where
  it is off, the helper turns it on (a global override, left on) only when
  IOMETE_PRIVATE_DOMAINS_SET_FLAG is true, which the all-in-one and e2e workflows set. Otherwise
  enabled is false and the caller skips (dev, release, a customer install). An abort here would
  only end the helper, so the caller decides. The change can take a moment to reach iom-identity, so
  create-domain.feature retries a private create the flag still refuses.

  Scenario: read the flag, turn it on where allowed
    Given url baseUrl
    And path 'api/v1/admin/feature-flags/privateDomains'
    When method get
    # the admin read answers not found for experimental flags, privateDomains among them
    * def hidden = responseStatus == 404 && karate.toString(response).contains('Rollout flag not found')
    * if (responseStatus != 200 && !hidden) karate.fail('unexpected answer reading the privateDomains flag: ' + responseStatus)
    * def defaultOn = !hidden && response.defaultEnabled == true

    # the rollout flag values hold every global override, hidden flags included
    * def globalValue = function() { return karate.call('classpath:iomete/helpers/settings/rollout-flags.feature', { baseUrl: baseUrl }).flags.privateDomains }
    * def current = globalValue()
    * def flagOn = current == null ? defaultOn : current == true
    * def allowed = java.lang.System.getenv('IOMETE_PRIVATE_DOMAINS_SET_FLAG') == 'true'
    * def set = !flagOn && allowed ? karate.call('classpath:iomete/helpers/settings/set-private-domains-flag.feature').set : false
    * if (set && globalValue() != true) karate.fail('the privateDomains override was saved, but the flag still reads off')
    * def enabled = flagOn || set
    # a hidden flag that is off and not ours to set reads the same as a missing one
    * def flagKnown = !hidden || enabled
    * if (!flagKnown) karate.log('privateDomains flag is off or not known on this target, so it cannot create private domains')
