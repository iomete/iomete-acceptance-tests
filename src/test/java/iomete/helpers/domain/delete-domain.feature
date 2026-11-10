@ignore
Feature: Delete a domain and everything running in it (plumbing).
  The platform refuses to delete a domain while it has computes, Jupyter containers, event
  streams, or scheduled, streaming or running jobs, so this removes those first. Needs 4.0.2+.
  Call it with:
    karate.call('classpath:iomete/helpers/domain/delete-domain.feature', { domain: 'karate-x' })
  Returns:
    removed  what it deleted, one line per item
    failed   what it could not delete, one line per item

  Scenario: delete the domain's runtimes, then the domain
    * def removed = []
    * def failed = []
    * def attempt = function(what, fn){ try { fn(); removed.push(what) } catch (e) { failed.push(what + ': ' + e) } }

    # a domain that is already gone answers 400 here; anything else is a real failure
    Given url baseUrl
    And path 'api/v1/admin/domains', domain
    When method get
    * if (responseStatus == 400 || responseStatus == 404) karate.abort()
    Then status 200

    # --- computes ----------------------------------------------------------------------------
    Given url baseUrl
    And path 'api/v2/domains/' + domain + '/compute'
    When method get
    Then status 200
    * karate.forEach(response.items, c => attempt('compute ' + c.name, () => karate.call('classpath:iomete/helpers/compute/delete-compute.feature', { domain: domain, name: c.name })))

    # --- Jupyter containers --------------------------------------------------------------------
    * def containers = jupyterEnabled ? karate.call('classpath:iomete/helpers/jupyter/list-jupyter-containers.feature', { domain: domain, searchText: '' }).containers : []
    * karate.forEach(containers, c => attempt('Jupyter container ' + c.name, () => karate.call('classpath:iomete/helpers/jupyter/delete-jupyter-container.feature', { domain: domain, name: c.name })))

    # --- streaming jobs, which the job list below leaves out -----------------------------------
    Given url baseUrl
    And path 'api/v2/domains/' + domain + '/spark/streaming/jobs'
    And params { page: 0, size: 100 }
    When method get
    * def streamingJobs = responseStatus == 200 ? response.items : []
    * karate.forEach(streamingJobs, j => attempt('streaming job ' + j.name, () => karate.call('classpath:iomete/helpers/job/delete-streaming-job.feature', { domain: domain, name: j.name })))

    # --- jobs, active runs killed first since a delete is refused while one runs ---------------
    Given url baseUrl
    And path 'api/v1/domains/' + domain + '/spark/jobs'
    When method get
    Then status 200
    * def deleteJob = function(j){ karate.call('classpath:iomete/helpers/job/kill-active-runs.feature', { domain: domain, jobId: j.id }); karate.call('classpath:iomete/helpers/job/delete-job.feature', { domain: domain, name: j.name }) }
    * karate.forEach(response, j => attempt('job ' + j.name, () => deleteJob(j)))

    # --- event streams -------------------------------------------------------------------------
    Given url baseUrl
    And path 'api/v1/domains/' + domain + '/event-streams'
    And params { size: 200 }
    When method get
    * def streams = responseStatus == 200 ? response.items : []
    * def deleteStream = function(s){ if (!karate.call('classpath:iomete/helpers/event-stream/delete-stream.feature', { domain: domain, streamId: s.id }).deleted) throw 'delete failed' }
    * karate.forEach(streams, s => attempt('event stream ' + s.name, () => deleteStream(s)))

    # --- the domain ----------------------------------------------------------------------------
    # 409 while the runtimes above are still shutting down
    * configure retry = { count: 30, interval: 10000 }
    Given url baseUrl
    And path 'api/v1/admin/domains', domain
    And retry until responseStatus != 409
    When method delete
    * if (responseStatus == 204) removed.push('domain ' + domain)
    * if (responseStatus != 204) failed.push('domain ' + domain + ': ' + responseStatus + ' ' + karate.toString(response))
