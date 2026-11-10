@lock=job
Feature: Docker settings, a registry becomes a pull secret and a tag alias decides the image a run pulls

  Both are only bookkeeping until the cluster sees them. A registry is written to Kubernetes as a
  pull secret named after it, and the registry's detail reads its username back out of that
  secret, so the read proves the secret is there. A tag alias is resolved by iom-cluster when it
  builds a run's Spark application, so a job whose image names an alias only runs if the alias
  turned into a real tag.

  Registries are shared by every domain and their names are unique across the platform, so the
  registry carries the run id; the alias does too, and stays within the 24 characters the
  platform stores. Listing, merging and validation are iom-cluster's own logic and stay in its
  tests.

  Background:
    * url baseUrl
    * def registriesPath = 'api/v1/admin/docker-registries'
    * def aliasesPath = 'api/v2/domains/' + domain + '/docker/tag-aliases'

  Scenario: a registry's credentials are written to its pull secret and replaced in it
    # a registry is platform-wide, so it runs only where the install allows that
    * if (!platformChangesAllowed()) karate.abort()
    * def registryName = 'karate-reg-' + runId
    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/docker/delete-registry.feature', { name: registryName });
      }
      """
    * def cleared = call read('classpath:iomete/helpers/docker/delete-registry.feature') { name: '#(registryName)' }

    # the host is never contacted, so a placeholder serves; no namespace means the release one
    Given path registriesPath
    And request { name: '#(registryName)', host: 'karate-registry.invalid', username: 'karate-user-1', password: 'karate-password-1' }
    When method post
    Then status 200
    * def registryId = response.id

    # the username comes out of the pull secret, not out of the registry's row: iom-cluster parses
    # it from the Kubernetes secret on every read, and answers 404 when the secret is missing
    Given path registriesPath, registryId
    When method get
    Then status 200
    And match response.username == 'karate-user-1'

    Given path registriesPath, registryId
    And request { host: 'karate-registry.invalid', username: 'karate-user-2', password: 'karate-password-2' }
    When method put
    Then status 200

    Given path registriesPath, registryId
    When method get
    Then status 200
    And match response.username == 'karate-user-2'


  Scenario: a job whose image names a tag alias runs the image the alias points at
    * def alias = 'k' + runId
    * assert alias.length <= 24
    # a published Spark version other than the job's default tag, so the run can only pull it
    # through the alias
    Given path 'api/v1/docker/spark/versions'
    And param appType = 'python'
    When method get
    Then status 200
    * def tags = response.map(v => ('' + (v.image || v.name || v)).split(':').pop()).filter(t => t != '3.5.7-latest')
    # with only the default published, the run could not tell an alias from no alias
    * if (tags.length == 0) { karate.log('skipping: no Spark version besides the default is published on', baseUrl); karate.abort() }
    * def aliasedTag = tags[0]
    * karate.log('tag alias', alias, '->', aliasedTag)
    * def jobName = 'karate-tag-alias-' + runId
    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/job/delete-job.feature', { name: jobName });
        karate.call('classpath:iomete/helpers/docker/delete-tag-alias.feature', { alias: alias });
      }
      """
    * def cleared = call read('classpath:iomete/helpers/job/delete-job.feature') { name: '#(jobName)' }
    * def clearedAlias = call read('classpath:iomete/helpers/docker/delete-tag-alias.feature') { alias: '#(alias)' }

    # an upsert: a repeat of `make test-one` points the same alias at the same tag
    Given path aliasesPath
    And request { alias: '#(alias)', tag: '#(aliasedTag)' }
    When method post
    Then status 200

    # the map is what the console's job form reads aliases from; it and the resolution behind it
    # sit behind a 10s cache, so wait until the new alias is live
    * configure retry = { count: 10, interval: 2000 }
    Given path aliasesPath, 'map'
    And retry until response[alias] == aliasedTag
    When method get
    Then status 200

    # the image names the alias, not the tag; iom-cluster resolves it when the run is built
    * def job = karate.call('classpath:iomete/helpers/job/create-job.feature', { name: jobName, sparkVersion: '${' + alias + '}' })
    * def result = karate.call('classpath:iomete/helpers/job/run-job.feature', { jobId: job.jobId })
    * if (result.run.driverStatus != 'COMPLETED') karate.log('run did not complete:', result.run)
    And match result.run.driverStatus == 'COMPLETED'

    # and the driver pod pulled the tag the alias names
    # 'pulled' and 'already present' events both name the image, so match the image, not the verb
    * configure retry = { count: 6, interval: 5000 }
    Given path 'api/v2/domains/' + domain + '/spark/jobs', job.jobId, 'runs', result.run.id, 'events'
    And retry until responseStatus == 200 && response.map(e => e.note || '').join('\n').includes('spark-py:' + aliasedTag)
    When method get
    Then status 200
    * def notes = response.map(e => e.note || '').join('\n')
    And match notes contains 'spark-py:' + aliasedTag
