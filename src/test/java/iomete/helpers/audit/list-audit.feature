@ignore
Feature: List today's data access audit rows, whatever the status (plumbing).
  For JS polling loops that cannot use `retry until`, call it with:
    karate.call('classpath:iomete/helpers/audit/list-audit.feature', { agentHostname: '...' })
  and read `status` and `rows` (the GET body, null unless 200). Leave agentHostname out to list
  every compute's rows. It never fails on the status, so a transient error is just another poll.

  Scenario: list the rows
    * def agentHostname = karate.get('agentHostname', null)
    * def query = agentHostname ? { agentHostname: agentHostname } : {}
    Given url baseUrl
    And path 'api/v1/admin/audit'
    And params query
    When method get
    * def status = responseStatus
    * def rows = responseStatus == 200 && karate.typeOf(response) == 'list' ? response : null
