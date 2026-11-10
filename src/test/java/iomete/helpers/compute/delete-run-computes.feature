Feature: Delete every compute, Jupyter container, streaming job and event stream one run created, for cleaning up after a cancelled run.

  A cancelled or killed run skips its afterScenario hooks and the cleanup-run teardown, so the
  computes, Jupyter containers, streaming jobs and event streams it created stay up (a streaming
  job never ends on its own, and an event stream holds 2 CPU / 4 GiB per replica until deleted).
  Everything a run creates ends in -{runId}, so this deletes exactly those and leaves other runs'
  resources, the shared event stream and the shared compat compute alone.

  Run it with `make cleanup-run-computes`. It targets the local run id by default; pass
  GITHUB_RUN_ID (and GITHUB_RUN_ATTEMPT) or IOMETE_RUN_ID to clean up a CI run instead.

  Scenario: delete this run's computes
    * def suffix = '-' + runId

    Given url baseUrl
    And path 'api/v2/domains/' + domain + '/compute'
    When method get
    Then status 200
    * def computes = response.items.filter(c => c.name.slice(-suffix.length) == suffix)

    * def deleteAll =
      """
      function(computes) {
        var deleted = [];
        var failed = [];
        for (var i = 0; i < computes.length; i++) {
          var name = computes[i].name;
          try {
            karate.call('classpath:iomete/helpers/compute/delete-compute.feature', { name: name });
            deleted.push(name);
          } catch (e) {
            failed.push(name + ': ' + e);
          }
        }
        return { deleted: deleted, failed: failed };
      }
      """
    * def result = deleteAll(computes)

    # straight to stdout: `print` only reaches the HTML report
    * eval java.lang.System.out.println('run ' + runId + ': deleted ' + result.deleted.length + ' compute(s) in domain ' + domain + (result.deleted.length ? ': ' + result.deleted.join(', ') : ', none matched *' + suffix))

    * match result.failed == []


  Scenario: delete this run's Jupyter containers
    * if (!jupyterEnabled) { java.lang.System.out.println('run ' + runId + ': jupyterContainers is off, no Jupyter containers to delete'); karate.abort() }
    * def suffix = '-' + runId
    * def listed = karate.call('classpath:iomete/helpers/jupyter/list-jupyter-containers.feature', { searchText: runId }).containers
    * def containers = listed.filter(c => c.name.slice(-suffix.length) == suffix)

    * def deleteAll =
      """
      function(containers) {
        var deleted = [];
        var failed = [];
        for (var i = 0; i < containers.length; i++) {
          var name = containers[i].name;
          try {
            karate.call('classpath:iomete/helpers/jupyter/delete-jupyter-container.feature', { name: name });
            deleted.push(name);
          } catch (e) {
            failed.push(name + ': ' + e);
          }
        }
        return { deleted: deleted, failed: failed };
      }
      """
    * def result = deleteAll(containers)

    * eval java.lang.System.out.println('run ' + runId + ': deleted ' + result.deleted.length + ' Jupyter container(s) in domain ' + domain + (result.deleted.length ? ': ' + result.deleted.join(', ') : ', none matched *' + suffix))

    * match result.failed == []


  Scenario: stop and delete this run's streaming jobs
    * def suffix = '-' + runId

    Given url baseUrl
    And path 'api/v2/domains/' + domain + '/spark/streaming/jobs'
    And params { search: '#(runId)', page: 0, size: 100 }
    When method get
    # a target without the streaming API has no streaming jobs to clean up
    * if (responseStatus == 404) { java.lang.System.out.println('run ' + runId + ': no streaming jobs API, nothing to delete'); karate.abort() }
    Then status 200
    * def jobs = response.items.filter(j => j.name.slice(-suffix.length) == suffix)

    * def deleteAll =
      """
      function(jobs) {
        var deleted = [];
        var failed = [];
        for (var i = 0; i < jobs.length; i++) {
          var name = jobs[i].name;
          try {
            karate.call('classpath:iomete/helpers/job/delete-streaming-job.feature', { name: name });
            deleted.push(name);
          } catch (e) {
            failed.push(name + ': ' + e);
          }
        }
        return { deleted: deleted, failed: failed };
      }
      """
    * def result = deleteAll(jobs)

    * eval java.lang.System.out.println('run ' + runId + ': deleted ' + result.deleted.length + ' streaming job(s) in domain ' + domain + (result.deleted.length ? ': ' + result.deleted.join(', ') : ', none matched *' + suffix))

    * match result.failed == []


  Scenario: delete this run's event streams
    # streams only run on the local data plane; a planes-only target has none to delete
    * def hasLocalPlane = karate.callSingle('classpath:iomete/helpers/dataplane/has-local-plane.feature').hasLocalPlane
    * if (!hasLocalPlane) { java.lang.System.out.println('run ' + runId + ': no local data plane, no event streams to delete'); karate.abort() }
    * def suffix = '-' + runId

    Given url baseUrl
    And path 'api/v1/domains/' + domain + '/event-streams'
    And params { searchText: '#(runId)', size: 200 }
    When method get
    Then status 200
    * def streams = response.items.filter(x => x.name.slice(-suffix.length) == suffix)

    * def deleteAll =
      """
      function(streams) {
        var deleted = [];
        var failed = [];
        for (var i = 0; i < streams.length; i++) {
          var res = karate.call('classpath:iomete/helpers/event-stream/delete-stream.feature', { streamId: streams[i].id });
          if (res.deleted) deleted.push(streams[i].name);
          else failed.push(streams[i].name + ': status ' + res.code);
        }
        return { deleted: deleted, failed: failed };
      }
      """
    * def result = deleteAll(streams)

    * eval java.lang.System.out.println('run ' + runId + ': deleted ' + result.deleted.length + ' event stream(s) in domain ' + domain + (result.deleted.length ? ': ' + result.deleted.join(', ') : ', none matched *' + suffix))

    * match result.failed == []
