@lock=api
Feature: Worksheets, saved SQL really goes to storage and comes back

  A worksheet is not a database row: the SQL text is written to the platform's object storage
  and read back from there.

  Renaming, moving and sharing belong in the service's own tests.

  Background:
    * url baseUrl
    * def sqlPath = 'api/v2/domains/' + domain + '/sql'
    * def folderName = 'karate-worksheets-' + runId
    * def worksheetName = 'karate-storage-round-trip-' + runId
    * def savedSql = 'SELECT 1 AS one'
    * def editedSql = 'SELECT 2 AS two -- edited by the API test'

    # a workspace id is required where workspaces are switched on and ignored where they are
    # not, so send whatever this environment lists
    Given path sqlPath + '/workspaces'
    When method get
    Then status 200
    * def workspaceId = response.length > 0 ? response[0].id : null
    * def workspaceParam = workspaceId == null ? {} : { workspaceId: workspaceId }

    # the names carry the run id, so only a repeat of `make test-one` (which keeps the id)
    # can find its own folder still there, holding a worksheet of this name
    * def clearedFolder = call read('classpath:iomete/helpers/sql/delete-worksheet-folder.feature') { name: '#(folderName)' }

    # teardown: takes the folder and everything still in it away, pass or fail
    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/sql/delete-worksheet-folder.feature', { name: folderName });
      }
      """

  Scenario: a worksheet keeps the SQL it was saved with, and an edit replaces it
    * def folderRequest = workspaceId == null ? { name: folderName } : { name: folderName, workspaceId: workspaceId }

    # 409 means a repeat run under the same id left the folder behind, which is fine: it gets
    # reused. Either way the path is read off the listing, not off the create.
    Given url baseUrl
    And path sqlPath + '/folders'
    And request folderRequest
    When method post
    Then assert responseStatus == 200 || responseStatus == 201 || responseStatus == 409

    * def found = call read('classpath:iomete/helpers/sql/find-worksheet-folder.feature') { name: '#(folderName)' }
    * match found.folder == '#notnull'
    * def folderPath = found.folder.path

    # create it with content, which is what the editor does on the first save
    * def createRequest = { name: '#(worksheetName)', folderPath: '#(folderPath)', content: '#(savedSql)' }
    * eval if (workspaceId != null) createRequest.workspaceId = workspaceId

    Given url baseUrl
    And path sqlPath + '/worksheets'
    And request createRequest
    When method post
    Then assert responseStatus == 200 || responseStatus == 201
    * def worksheetPath = response.path
    And match worksheetPath == '#notnull'

    # read it back: the content comes out of storage, not out of the create response, which
    # reports neither the content nor where it went
    Given url baseUrl + '/' + sqlPath + '/worksheets/' + worksheetPath
    And params workspaceParam
    When method get
    Then status 200
    And match response.content == savedSql

    # and the read says where the platform put the file, which is the file we asked for
    And match response.storagePath == '#notnull'
    And match response.storagePath contains worksheetName

    # an edit has to replace what is stored, not sit in front of it
    * def contentRequest = { content: '#(editedSql)' }
    * eval if (workspaceId != null) contentRequest.workspaceId = workspaceId

    Given url baseUrl + '/' + sqlPath + '/worksheets/' + worksheetPath + '/content'
    And request contentRequest
    When method put
    Then assert responseStatus >= 200 && responseStatus < 300

    Given url baseUrl + '/' + sqlPath + '/worksheets/' + worksheetPath
    And params workspaceParam
    When method get
    Then status 200
    And match response.content == editedSql

    # deleting it takes it out of the folder people look at. force, because the API refuses to
    # delete a worksheet that still holds SQL (406)
    * def forceParam = workspaceId == null ? { force: true } : { workspaceId: workspaceId, force: true }

    Given url baseUrl + '/' + sqlPath + '/worksheets/' + worksheetPath
    And params forceParam
    When method delete
    Then assert responseStatus >= 200 && responseStatus < 300

    Given url baseUrl + '/' + sqlPath + '/folders/' + folderPath
    And params workspaceParam
    When method get
    Then status 200
    * def remaining = (response.worksheets || []).map(w => w.name)
    And match remaining !contains worksheetName
