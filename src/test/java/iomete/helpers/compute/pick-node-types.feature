@ignore
Feature: Pick node types that exist in the target environment.
  Node type catalogues differ per environment, so a hardcoded name only works where it was
  written. Registers the suite's own small types first (ensure-node-types.feature), then keeps
  the preferred name when the environment has it, otherwise takes the smallest offered for each
  role. Call it with:
    karate.call('classpath:iomete/helpers/compute/pick-node-types.feature',
                { preferredDriver: 'karate-driver', preferredExecutor: 'karate-exec' })
  Returns:
    driverNodeType    name to use for the driver
    executorNodeType  name to use for executors

  Scenario: resolve a driver and an executor node type
    * karate.callSingle('classpath:iomete/helpers/compute/ensure-node-types.feature')

    Given url baseUrl
    And path 'api/v1/admin/node-types'
    When method get
    Then status 200
    * def nodeTypes = response
    * def pick =
      """
      function(component, preferred) {
        var i, t, best = null;
        for (i = 0; i < nodeTypes.length; i++) {
          if (nodeTypes[i].name == preferred) return preferred;
        }
        for (i = 0; i < nodeTypes.length; i++) {
          t = nodeTypes[i];
          if (t.components.indexOf(component) < 0) continue;
          // sized for an idle JupyterLab, far too small for a Spark driver
          if (t.name == 'karate-jupyter') continue;
          if (best == null || t.cpu < best.cpu || (t.cpu == best.cpu && t.memory < best.memory)) best = t;
        }
        return best.name;
      }
      """
    * def driverNodeType = pick('DRIVER', preferredDriver)
    * def executorNodeType = pick('EXECUTOR', preferredExecutor)
