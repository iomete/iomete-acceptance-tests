@ignore
Feature: List the subjects of the test mail sink's messages to one recipient (helper).
  Usage:
    karate.call('classpath:iomete/helpers/mail/search-mailbox.feature', { recipient: '...' }).subjects
    karate.call('classpath:iomete/helpers/mail/search-mailbox.feature', { recipient: '...', mailboxWaitFor: '...' }).subjects
  Returns: subjects, newest first. With mailboxWaitFor (a subject) it asks again every 5s, for up to 3 minutes,
  until a message with that subject is there, and returns what it last saw either way.

  The sink is a Mailpit, read through its own API with its own login (IOMETE_MAIL_SINK_URL,
  IOMETE_MAIL_SINK_USERNAME, IOMETE_MAIL_SINK_PASSWORD). It is not part of IOMETE, so the
  suite's IOMETE headers are not sent to it.

  Scenario: search
    * def login = karate.callSingle('classpath:iomete/helpers/mail/sink-login.feature')
    * configure headers = { Authorization: '#(login.basic)' }
    # the input has a name no caller uses: karate.get also sees the caller's variables
    * def wanted = karate.get('mailboxWaitFor', null)
    * def subjectsIn = function(r) { return ((r && r.messages) || []).map(m => m.Subject) }
    * configure retry = { count: 36, interval: 5000 }
    Given url login.sinkUrl
    And path 'api/v1/search'
    And param query = 'to:"' + recipient + '"'
    And retry until responseStatus != 200 || !wanted || subjectsIn(response).indexOf(wanted) >= 0
    When method get
    Then status 200
    * def subjects = subjectsIn(response)
