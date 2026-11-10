@ignore
Feature: Delete an event stream (plumbing).
  karate.call('classpath:iomete/helpers/event-stream/delete-stream.feature', { streamId: '...' })
  Returns: code, and deleted (true when it is gone, including when it already was).

  Scenario: delete it
    # the delete waits for the agent to remove the StatefulSet (up to 60s) before answering
    * configure readTimeout = 90000
    Given url baseUrl
    And path 'api/v1/domains/' + domain + '/event-streams', streamId
    When method delete
    * def code = responseStatus
    # 404 means someone else removed it, which is the state the caller wanted either way.
    * def deleted = code == 404 || (code >= 200 && code < 300)
