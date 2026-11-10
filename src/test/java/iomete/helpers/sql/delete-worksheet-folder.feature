@ignore
Feature: Remove a SQL editor folder by name, if it is still there (plumbing).
  Teardown helper, safe to call when the folder is already gone:
    karate.call('classpath:iomete/helpers/sql/delete-worksheet-folder.feature', { name: 'my-folder' })

  Deletes with force, so the worksheets inside go with it. Without it the API refuses to
  delete a folder that is not empty (406).

  Scenario: find the folder and delete it, or do nothing if it does not exist
    * def sqlPath = 'api/v2/domains/' + domain + '/sql'

    * def found = call read('classpath:iomete/helpers/sql/find-worksheet-folder.feature') { name: '#(name)' }
    * if (found.folder == null) karate.abort()
    * def deleteParams = found.workspaceId == null ? { force: true } : { workspaceId: found.workspaceId, force: true }

    # the folder path is already URL encoded and goes in as a single segment, which Karate's
    # `path` step would encode a second time, so this URL is built by hand
    Given url baseUrl + '/' + sqlPath + '/folders/' + found.folder.path
    And params deleteParams
    When method delete
    Then assert responseStatus < 500
