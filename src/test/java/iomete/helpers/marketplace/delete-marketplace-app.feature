@ignore
Feature: Remove marketplace apps by name, if any are still there (plumbing).
  Teardown helper, safe to call when nothing of that name is left:
    karate.call('classpath:iomete/helpers/marketplace/delete-marketplace-app.feature', { name: 'karate-marketplace-' + runId })

  The marketplace is platform-wide and does not keep names unique, so every app of that name
  goes. A delete is soft and renames the app to name-id, so it no longer lists under its name.

  Scenario: delete every app of that name, or do nothing if there is none
    * def marketplacePath = 'api/v1/domains/' + domain + '/marketplace'

    Given url baseUrl
    And path marketplacePath
    When method get
    Then status 200
    * def apps = response.items.filter(a => a.name == name)
    * if (apps.length == 0) karate.abort()

    # karate.http does not send the configured headers, so the admin ones are passed
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }
    * def deleteApp =
      """
      function(app) {
        var result = karate.http(baseUrl + '/' + marketplacePath + '/' + app.id).headers(adminHeaders).delete();
        if (result.status != 204 && result.status != 404) karate.fail('could not delete marketplace app ' + app.id + ': ' + result.status);
      }
      """
    * karate.forEach(apps, deleteApp)
