@lock=api
Feature: Identity, an admin creates a domain and deletes it

  Deleting asks iom-cluster what the domain still runs, so this checks a fresh domain with
  nothing in it really goes. The rules about what blocks a delete stay in iom-identity's tests.

  Background:
    * if (!platformAtLeast('4.0.2')) { karate.log('domain deletion ships in 4.0.2+: skipping on ' + platformVersion); karate.abort() }
    * url baseUrl
    # per attempt, not just per run: a deleted domain keeps its id reserved, so a retry needs a new one
    * def domainId = 'karate-delete-' + runId + '-' + java.lang.Long.toString(java.lang.System.currentTimeMillis(), 36)

  Scenario: a created domain can be deleted
    * karate.call('classpath:iomete/helpers/domain/create-domain.feature', { domainId: domainId })

    Given path 'api/v1/admin/domains', domainId
    When method delete
    Then status 204

    Given path 'api/v1/admin/domains'
    When method get
    Then status 200
    And match response[*].id !contains domainId
