@ignore
Feature: The test mail sink's address and login (plumbing for search-mailbox and clear-mailbox).
  Returns: sinkUrl, and basic, the Authorization header value.

  Scenario: read them
    * def getenv = function(name){ return java.lang.System.getenv(name) || '' }
    * def sinkUrl = getenv('IOMETE_MAIL_SINK_URL')
    * def credentials = getenv('IOMETE_MAIL_SINK_USERNAME') + ':' + getenv('IOMETE_MAIL_SINK_PASSWORD')
    * def basic = 'Basic ' + Java.type('java.util.Base64').getEncoder().encodeToString(credentials.getBytes('UTF-8'))
