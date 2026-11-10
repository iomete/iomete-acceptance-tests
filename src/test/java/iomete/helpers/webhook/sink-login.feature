@ignore
Feature: The test webhook sink's address and login (plumbing for sink-requests and clear-sink).
  Returns: sinkUrl, and basic, the Authorization header value.

  Scenario: read them
    * def getenv = function(name){ return java.lang.System.getenv(name) || '' }
    * def sinkUrl = getenv('IOMETE_WEBHOOK_SINK_URL')
    * def credentials = getenv('IOMETE_WEBHOOK_SINK_USERNAME') + ':' + getenv('IOMETE_WEBHOOK_SINK_PASSWORD')
    * def basic = 'Basic ' + Java.type('java.util.Base64').getEncoder().encodeToString(credentials.getBytes('UTF-8'))
