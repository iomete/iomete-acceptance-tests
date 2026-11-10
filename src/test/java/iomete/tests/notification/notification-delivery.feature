@lock=job2
Feature: Notifications — IOMETE really sends email, and a job run emails only its subscribers

  What this checks:
  - The email integration's test send reaches a real mailbox.
  - When a job run fails, the recipient subscribed to failures gets exactly one "Failed" email,
    and a recipient subscribed only to successes gets none.
  - While a job's notifications are silenced, a failed run sends nothing; once the silence is
    removed, the next failed run emails again.

  Delivery leaves no trace this suite can read through IOMETE, so only a mailbox proves it: these
  scenarios read a test mail sink (Mailpit) through its own API. Every recipient is unique to the
  scenario.

  Needs an SMTP sink the platform can reach and its read API. Skips unless IOMETE_MAIL_SMTP_HOST,
  IOMETE_MAIL_SMTP_PORT, IOMETE_MAIL_SINK_URL, IOMETE_MAIL_SINK_USERNAME and
  IOMETE_MAIL_SINK_PASSWORD are set (see AGENTS.md).

  The job scenario needs the platform's email integration to send through that sink. Where none
  is configured it saves one, but only when IOMETE_MAIL_SET_INTEGRATION is true, and leaves it in
  place (it is platform-wide, so removing it could cut off an overlapping run). Where one points
  elsewhere it never changes it: it skips, and in CI it fails instead, so lost coverage shows.

  Not tested here (covered by iom-cluster's own tests): saving, editing and listing notification
  settings and silences, validation, and permissions.

  Background:
    * url baseUrl
    * def getenv = function(name){ return java.lang.System.getenv(name) || null }
    * def port = parseInt(getenv('IOMETE_MAIL_SMTP_PORT'))
    * def settings = ({ IOMETE_MAIL_SMTP_HOST: getenv('IOMETE_MAIL_SMTP_HOST'), IOMETE_MAIL_SMTP_PORT: isNaN(port) ? null : port, IOMETE_MAIL_SINK_URL: getenv('IOMETE_MAIL_SINK_URL'), IOMETE_MAIL_SINK_USERNAME: getenv('IOMETE_MAIL_SINK_USERNAME'), IOMETE_MAIL_SINK_PASSWORD: getenv('IOMETE_MAIL_SINK_PASSWORD') })
    * def missing = Object.keys(settings).filter(k => !settings[k])
    # name what is missing, so a half-published setup is visible instead of a silent skip
    * if (missing.length) karate.log('no test mail sink configured, missing:', missing.join(', '), '- skipping')
    * if (missing.length) karate.abort()

    # The sink takes plain SMTP without a login.
    * def sinkConfig = { host: '#(settings.IOMETE_MAIL_SMTP_HOST)', port: '#(port)', security: 'NONE', authRequired: false, username: null, password: null, defaultSenderEmail: 'karate@example.com', defaultSenderName: 'IOMETE API tests' }
    * def recipientFor = function(who) { return 'karate-' + who + '-' + runId + '-' + java.util.UUID.randomUUID().toString().substring(0, 8) + '@example.com' }
    * def subjectsFor = function(recipient) { return karate.call('classpath:iomete/helpers/mail/search-mailbox.feature', { recipient: recipient }).subjects }
    # Waits up to 3 minutes for the recipient's mailbox to hold a message with this subject.
    * def waitForSubject = function(recipient, subject) { return karate.call('classpath:iomete/helpers/mail/search-mailbox.feature', { recipient: recipient, mailboxWaitFor: subject }).subjects }
    * def clearMailbox = function(recipient) { karate.call('classpath:iomete/helpers/mail/clear-mailbox.feature', { recipient: recipient }) }

  Scenario: the email integration's test send reaches the mailbox
    # Step 1: send a test email through the sink's settings. Nothing is saved.
    * def recipient = recipientFor('validate')
    * configure afterScenario = function() { clearMailbox(recipient) }
    Given path 'api/v1/admin/integrations/email/validate'
    And request { emailConfig: '#(sinkConfig)', recipients: ['#(recipient)'] }
    When method post
    Then status 204

    # Step 2: exactly one test email arrives.
    * def subjects = waitForSubject(recipient, 'IOMETE Email Configuration Test')
    And match subjects == ['IOMETE Email Configuration Test']

  Scenario: a failed run emails its failure subscriber, not its success subscriber, and silencing stops it until removed
    # Step 1: make sure the platform sends through the sink, without changing a real setup.
    # In CI a skip here would hide lost coverage, so it fails instead.
    * def inCi = getenv('GITHUB_ACTIONS') == 'true'
    * def stop = function(reason) { if (inCi) karate.fail(reason); karate.log(reason, '- skipping'); karate.abort() }
    * def sameHost = function(a, b) { var bare = h => ('' + h).toLowerCase().replace(/\.cluster\.local$/, ''); return bare(a) == bare(b) }
    Given path 'api/v1/admin/integrations/email'
    When method get
    * if (responseStatus != 200 && responseStatus != 404) karate.fail('unexpected answer reading the email integration: ' + responseStatus)
    * if (responseStatus == 200 && !sameHost(response.host, sinkConfig.host)) stop('the email integration points at ' + response.host + ', not the test sink, and is never changed')
    * if (responseStatus == 404 && getenv('IOMETE_MAIL_SET_INTEGRATION') != 'true') stop('no email integration, and IOMETE_MAIL_SET_INTEGRATION is not true, so none is saved')
    * if (responseStatus == 404) karate.call('classpath:iomete/helpers/mail/set-email-integration.feature', { emailConfig: sinkConfig })

    # Step 2: a job whose runs fail as soon as the driver starts (SparkPi with a non-numeric
    # argument), with two subscribers.
    * def jobName = 'karate-notify-' + runId
    * def failureSubscriber = recipientFor('failed')
    * def successSubscriber = recipientFor('succeeded')
    * configure afterScenario =
      """
      function() {
        // each step runs even when an earlier one fails
        var attempt = function(what, fn) { try { fn() } catch (e) { karate.log('teardown:', what, 'failed:', e) } };
        var job = karate.get('job');
        if (job) attempt('kill runs', () => karate.call('classpath:iomete/helpers/job/kill-active-runs.feature', { jobId: job.jobId }));
        attempt('delete job', () => karate.call('classpath:iomete/helpers/job/delete-job.feature', { name: jobName }));
        attempt('clear mailbox', () => clearMailbox(failureSubscriber));
        attempt('clear mailbox', () => clearMailbox(successSubscriber));
      }
      """
    * karate.call('classpath:iomete/helpers/job/delete-job.feature', { name: jobName })
    * def job = karate.call('classpath:iomete/helpers/job/create-job.feature', { name: jobName, jobApi: 'sdk' })
    * def settingsPath = 'api/v1/domains/' + domain + '/notification-settings'
    Given path settingsPath, 'resource', job.jobId
    And request { recipient: '#(failureSubscriber)', eventTypes: ['FAILED'] }
    When method post
    Then status 204
    Given path settingsPath, 'resource', job.jobId
    And request { recipient: '#(successSubscriber)', eventTypes: ['SUCCEEDED'] }
    When method post
    Then status 204

    * def failingRun = function() { return karate.call('classpath:iomete/helpers/job/run-job.feature', { jobId: job.jobId, runJobApi: 'sdk', runOverrides: { arguments: ['not-a-number'] } }).run }
    * def failedSubject = "IOMETE - Spark Job '" + jobName + "' Failed"

    # Step 3: a failed run emails the failure subscriber exactly once, and the success subscriber not at all.
    * def run = failingRun()
    And match run.driverStatus == 'FAILED'
    * def subjects = waitForSubject(failureSubscriber, failedSubject)
    And match subjects == ['#(failedSubject)']
    And match subjectsFor(successSubscriber) == []

    # Step 4: silence the job for an hour. A failed run sends nothing, given a minute to arrive.
    * clearMailbox(failureSubscriber)
    Given path settingsPath, 'silence', 'resource', job.jobId
    And request { silenceDurationInSeconds: 3600 }
    When method post
    Then status 204
    * def run = failingRun()
    And match run.driverStatus == 'FAILED'
    * java.lang.Thread.sleep(60000)
    And match subjectsFor(failureSubscriber) == []

    # Step 5: remove the silence. The next failed run emails again, exactly once.
    Given path settingsPath, 'silence', 'resource', job.jobId
    When method delete
    Then status 204
    * def run = failingRun()
    And match run.driverStatus == 'FAILED'
    * def subjects = waitForSubject(failureSubscriber, failedSubject)
    And match subjects == ['#(failedSubject)']
