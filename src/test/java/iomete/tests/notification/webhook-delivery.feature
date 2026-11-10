@lock=job2
Feature: Webhook notifications, a failed job run reaches a Generic webhook

  What this checks:
  - A URL can be tested before it is saved, and the test message arrives.
  - A saved Generic webhook gets its test message, and the admin list of every domain's webhooks
    shows it.
  - When a job subscribed On Failure fails, the webhook gets exactly one FAILED event in the
    documented JSON shape, and the webhook's latest delivery reads DELIVERED.

  Delivery leaves no trace this suite can read through IOMETE apart from the latest delivery, so
  only a receiver proves it: the scenario points the webhook at a test webhook sink and reads it
  back through the sink's own API. Every scenario uses its own sink channel.

  Needs a webhook sink the platform can reach over https. Skips unless IOMETE_WEBHOOK_SINK_URL,
  IOMETE_WEBHOOK_SINK_USERNAME and IOMETE_WEBHOOK_SINK_PASSWORD are set, and on platforms before
  4.0.2 (see AGENTS.md).

  Webhooks are behind the platform-wide webhookNotifications rollout flag. Where it is off the
  scenario turns it on, but only when IOMETE_WEBHOOK_SET_FLAG is true, and leaves it on (an
  overlapping run may be using it). Otherwise it skips, and in CI it fails, so lost coverage shows.

  Not tested here (covered by iom-cluster's own tests): request signing, editing, rotating the signing secret,
  Slack and Teams messages, retries, disabling after repeated failures, validation, rate limits
  and permissions.

  Background:
    * url baseUrl
    * def getenv = function(name){ return java.lang.System.getenv(name) || null }
    * def settings = ({ IOMETE_WEBHOOK_SINK_URL: getenv('IOMETE_WEBHOOK_SINK_URL'), IOMETE_WEBHOOK_SINK_USERNAME: getenv('IOMETE_WEBHOOK_SINK_USERNAME'), IOMETE_WEBHOOK_SINK_PASSWORD: getenv('IOMETE_WEBHOOK_SINK_PASSWORD') })
    * def missing = Object.keys(settings).filter(k => !settings[k])
    # name what is missing, so a half-published setup is visible instead of a silent skip
    * if (missing.length) karate.log('no test webhook sink configured, missing:', missing.join(', '), '- skipping')
    * if (missing.length) karate.abort()
    # webhooks arrived in 4.0.2; builds from main count as newer
    * def supported = platformAtLeast('4.0.2')
    * if (!supported) karate.log('platform ' + platformVersion + ' predates webhook notifications, skipping')
    * if (!supported) karate.abort()

    * def webhooksPath = 'api/v1/domains/' + domain + '/webhooks'
    * def settingsPath = 'api/v1/domains/' + domain + '/notification-settings'
    * def channel = 'karate-' + runId + '-' + java.util.UUID.randomUUID().toString().substring(0, 8)
    * def sinkUrl = settings.IOMETE_WEBHOOK_SINK_URL.endsWith('/') ? settings.IOMETE_WEBHOOK_SINK_URL.slice(0, -1) : settings.IOMETE_WEBHOOK_SINK_URL
    * def hookUrl = sinkUrl + '/hooks/' + channel
    # Waits up to 3 minutes for an event of this type, then returns the events of that type.
    * def waitForEvents = function(type) { return karate.call('classpath:iomete/helpers/webhook/sink-requests.feature', { channel: channel, sinkWaitFor: type }).events.filter(e => e.json.eventType == type) }
    * def clearSink = function() { karate.call('classpath:iomete/helpers/webhook/clear-sink.feature', { channel: channel }) }

  Scenario: a Generic webhook gets its test messages and a failed run's event
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

    * def webhookName = 'karate-webhook-' + runId
    * def jobName = 'karate-webhook-' + runId
    * configure afterScenario =
      """
      function() {
        // each step runs even when an earlier one fails
        var attempt = function(what, fn) { try { fn() } catch (e) { karate.log('teardown:', what, 'failed:', e) } };
        var job = karate.get('job');
        if (job) attempt('kill runs', () => karate.call('classpath:iomete/helpers/job/kill-active-runs.feature', { jobId: job.jobId }));
        attempt('delete job', () => karate.call('classpath:iomete/helpers/job/delete-job.feature', { name: jobName }));
        attempt('delete webhook', () => karate.call('classpath:iomete/helpers/webhook/delete-webhook.feature', { name: webhookName }));
        attempt('clear sink', () => clearSink());
      }
      """
    # a repeat of `make test-one` keeps the run id, so it can meet its own leftovers
    * karate.call('classpath:iomete/helpers/webhook/delete-webhook.feature', { name: webhookName })

    # Step 2: test the sink's URL before saving it. The message arrives.
    # The platform gives the sink 10s per test call and the sink is reached over the internet, so
    # a call that timed out (no status code) is tried again, 3 attempts in all.
    * configure retry = { count: 3, interval: 5000 }
    * def timedOut = function() { return responseStatus == 200 && !response.delivered && response.statusCode == null }
    Given path webhooksPath, 'test'
    And request { type: 'GENERIC', url: '#(hookUrl)' }
    And retry until !timedOut()
    When method post
    Then status 200
    And match response contains { delivered: true, statusCode: 200 }
    * def tests = waitForEvents('TEST')
    And match tests[0].json contains { title: 'IOMETE - Test message', id: '#string', occurredAt: '#string' }
    * clearSink()

    # Step 3: save it as a Generic webhook.
    Given path webhooksPath
    And request { name: '#(webhookName)', type: 'GENERIC', url: '#(hookUrl)' }
    When method post
    Then status 201
    And match response.webhook contains { id: '#string', name: '#(webhookName)', type: 'GENERIC', enabled: true }
    And match response.webhook.url !contains channel
    * def webhookId = response.webhook.id

    # Step 4: a test message to the saved webhook arrives.
    Given path webhooksPath, webhookId, 'test'
    And request {}
    And retry until !timedOut()
    When method post
    Then status 200
    And match response contains { delivered: true, statusCode: 200 }
    # a late message from step 2 can land here too; only a saved webhook's message names it
    * def namedTests = function() { return waitForEvents('TEST').filter(e => e.json.body && e.json.body.includes('Webhook:')) }
    * def waitForNamed = function() { for (var i = 0; i < 12; i++) { var t = namedTests(); if (t.length) return t; java.lang.Thread.sleep(5000) } return [] }
    * def tests = waitForNamed()
    And match tests == '#[_ > 0]'
    And match tests[0].json contains { title: 'IOMETE - Test message', body: '#string' }
    * clearSink()

    # Step 5: account admins see it in the list of every domain's webhooks.
    Given path 'api/v1/admin/webhooks'
    And param size = 200
    When method get
    Then status 200
    And match response.items contains deep { id: '#(webhookId)', domain: '#(domain)', name: '#(webhookName)', type: 'GENERIC', enabled: true }

    # Step 6: a job whose runs fail as soon as the driver starts (SparkPi with a non-numeric
    # argument), subscribed to the webhook On Failure.
    * karate.call('classpath:iomete/helpers/job/delete-job.feature', { name: jobName })
    * def job = karate.call('classpath:iomete/helpers/job/create-job.feature', { name: jobName, jobApi: 'sdk' })
    Given path settingsPath, 'resource', job.jobId
    And request { recipient: '#(webhookId)', eventTypes: ['FAILED'], channel: 'WEBHOOK' }
    When method post
    Then status 204

    # Step 7: a failed run sends exactly one FAILED event, carrying the run.
    * def run = karate.call('classpath:iomete/helpers/job/run-job.feature', { jobId: job.jobId, runJobApi: 'sdk', runOverrides: { arguments: ['not-a-number'] } }).run
    And match run.driverStatus == 'FAILED'
    * def failures = waitForEvents('FAILED')
    And match failures == '#[1]'
    * def failed = failures[0]
    * def failedTitle = "IOMETE - Spark Job '" + jobName + "' Failed"
    And match failed.json contains { id: '#string', eventType: 'FAILED', resourceType: 'SPARK_JOB', resourceId: '#(job.jobId)', occurredAt: '#string', title: '#(failedTitle)', body: '#string' }
    And match failed.json.data contains { domain: '#(domain)', jobId: '#(job.jobId)', jobName: '#(jobName)', runId: '#(run.id)' }

    # Step 8: the webhook's latest delivery reads DELIVERED.
    * configure retry = { count: 12, interval: 5000 }
    Given path webhooksPath, webhookId
    And retry until responseStatus == 200 && response.lastDelivery && response.lastDelivery.status == 'DELIVERED'
    When method get
    Then status 200
    And match response.lastDelivery contains { at: '#string', status: 'DELIVERED' }

    # Step 9: delete the webhook. It is gone from the domain's list.
    Given path webhooksPath, webhookId
    When method delete
    Then status 204
    Given path webhooksPath
    When method get
    Then status 200
    And match response.items[*].id !contains webhookId
