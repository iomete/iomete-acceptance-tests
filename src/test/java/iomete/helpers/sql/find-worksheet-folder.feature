@ignore
Feature: Find a SQL editor folder by name (plumbing).
  Returns the folder node, or `folder` = null when it is not there:
    * def found = call read('classpath:iomete/helpers/sql/find-worksheet-folder.feature') { name: 'my-folder' }
    * def folderPath = found.folder.path

  Also returns `workspaceId` and `workspaceParam`, so a caller that needs them does not have
  to list the workspaces a second time.

  Scenario: look the folder up in the folder tree
    * def sqlPath = 'api/v2/domains/' + domain + '/sql'

    # a workspace id is required where workspaces are switched on and ignored where they are
    # not, so send whatever this environment lists
    Given url baseUrl
    And path sqlPath + '/workspaces'
    When method get
    Then status 200
    * def workspaceId = response.length > 0 ? response[0].id : null
    * def workspaceParam = workspaceId == null ? {} : { workspaceId: workspaceId }

    Given url baseUrl
    And path sqlPath + '/folders'
    And params workspaceParam
    When method get
    Then status 200
    # the listing is a tree: the workspace root is what comes back at the top level and the
    # folders in it are nested underneath, so the folder is looked for anywhere in that tree
    * def findFolder =
      """
      function(nodes, wanted) {
        function walk(list) {
          for (var i = 0; i < list.length; i++) {
            var node = list[i];
            if (node.name == wanted) return node;
            var found = walk(node.folders || []);
            if (found != null) return found;
          }
          return null;
        }
        return walk(nodes);
      }
      """
    * def folder = findFolder(response, name)
