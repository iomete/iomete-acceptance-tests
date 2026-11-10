@lock=job2
Feature: Webhook notifications to a real chat app, a failed job run's alert is delivered

  What this checks, per chat app whose webhook URL is set:
  - A saved webhook of that type gets its test message (the app answers 2xx).
  - When a job subscribed On Failure fails, the alert is delivered: the webhook's latest delivery
    reads DELIVERED.

  The channel can't be read back, so delivered: true and DELIVERED only show the app accepted the
  message, not how it looks (for Teams, only that the Workflow accepted it). Every run posts to the channel. Each type skips unless its URL is set,
  and on platforms before 4.0.2. The rollout flag is handled as in webhook-delivery.feature.

  Not tested here (covered by iom-cluster's own tests): the message layout, retries, disabling
  after repeated failures, validation, rate limits and permissions.

  Background:
    * url baseUrl
    * def getenv = function(name){ return java.lang.System.getenv(name) || null }
    # webhooks arrived in 4.0.2; builds from main count as newer
    * def supported = platformAtLeast('4.0.2')
    * if (!supported) karate.log('platform ' + platformVersion + ' predates webhook notifications, skipping')
    * if (!supported) karate.abort()
    * def webhooksPath = 'api/v1/domains/' + domain + '/webhooks'

  Scenario Outline: a <type> webhook gets its test message and a failed run's alert
    * def hookUrl = getenv('<urlVar>')
    * if (!hookUrl) karate.log('<urlVar> is not set, skipping')
    * if (!hookUrl) karate.abort()

    # Step 1: make sure webhooks are on, without changing a real install.
    # In CI a skip here would hide lost coverage, so it fails instead.
    * def inCi = getenv('GITHUB_ACTIONS') == 'true'
    * def stop = function(reason) { if (inCi) karate.fail(reason); karate.log(reason, '- skipping'); karate.abort() }
    Given path webhooksPath
    When method get
    * if (responseStatus != 200 && responseStatus != 404) karate.fail('unexpected answer listing webhooks: ' + responseStatus)
    * def flagOff = responseStatus == 404
    * if (flagOff && getenv('IOMETE_WEBHOOK_SET_FLAG') != 'true') stop('the webhookNotifications rollout flag is off, and IOMETE_WEBHOOK_SET_FLAG is not true, so it is not turned on')
    * if (flagOff) karate.call('classpath:iomete/helpers/settings/enable-webhooks.feature')

    * def name = 'karate-webhook-<slug>-' + runId
    * configure afterScenario =
      """
      function() {
        // each step runs even when an earlier one fails
        var attempt = function(what, fn) { try { fn() } catch (e) { karate.log('teardown:', what, 'failed:', e) } };
        var job = karate.get('job');
        if (job) attempt('kill runs', () => karate.call('classpath:iomete/helpers/job/kill-active-runs.feature', { jobId: job.jobId }));
        attempt('delete job', () => karate.call('classpath:iomete/helpers/job/delete-job.feature', { name: name }));
        attempt('delete webhook', () => karate.call('classpath:iomete/helpers/webhook/delete-webhook.feature', { name: name }));
      }
      """
    # a repeat of `make test-one` keeps the run id, so it can meet its own leftovers
    * karate.call('classpath:iomete/helpers/webhook/delete-webhook.feature', { name: name })

    # Step 2: save the webhook and send it a test message.
    Given path webhooksPath
    And request { name: '#(name)', type: '<type>', url: '#(hookUrl)' }
    When method post
    Then status 201
    * def webhookId = response.webhook.id
    Given path webhooksPath, webhookId, 'test'
    And request {}
    When method post
    Then status 200
    And match response contains { delivered: true }

    # Step 3: a job whose runs fail as soon as the driver starts, subscribed On Failure.
    * karate.call('classpath:iomete/helpers/job/delete-job.feature', { name: name })
    * def job = karate.call('classpath:iomete/helpers/job/create-job.feature', { name: name, jobApi: 'sdk' })
    * karate.call('classpath:iomete/helpers/webhook/subscribe-job.feature', { jobId: job.jobId, webhookId: webhookId })

    # Step 4: the failed run's alert is delivered.
    * def run = karate.call('classpath:iomete/helpers/job/run-job.feature', { jobId: job.jobId, runJobApi: 'sdk', runOverrides: { arguments: ['not-a-number'] } }).run
    And match run.driverStatus == 'FAILED'
    * karate.call('classpath:iomete/helpers/webhook/wait-delivered.feature', { webhookId: webhookId })

    Examples:
      | type  | slug  | urlVar                   |
      | SLACK | slack | IOMETE_WEBHOOK_SLACK_URL |
      | TEAMS | teams | IOMETE_WEBHOOK_TEAMS_URL |
