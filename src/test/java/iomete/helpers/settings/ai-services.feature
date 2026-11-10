@ignore
Feature: Find out whether the target runs the AI services (Model Gateway).
  The AI services are optional, and their version endpoint exists only where they are enabled.
  Where they are not, the endpoint answers 404, or 200 with the console's HTML page when the
  console's catch-all serves the path. Call it once per run with:
    karate.callSingle('classpath:iomete/helpers/settings/ai-services.feature', { baseUrl: baseUrl })
  Returns:
    status   the HTTP status of `ai-services/version`
    enabled  false on a 404 or a 200 HTML page, true otherwise

  Scenario: read the AI services version endpoint
    Given url baseUrl
    And path 'ai-services/version'
    When method get
    # no assertion: any other failure surfaces in the feature's own first call to the gateway,
    # instead of passing as a skip
    * def status = responseStatus
    * def contentType = karate.response.header('content-type') || ''
    # an outage's HTML error page (502, 503) still counts as enabled, so it fails the feature
    * def enabled = status != 404 && !(status == 200 && contentType.indexOf('text/html') >= 0)
    * karate.log('AI services version endpoint: ' + status + ' ' + contentType)
