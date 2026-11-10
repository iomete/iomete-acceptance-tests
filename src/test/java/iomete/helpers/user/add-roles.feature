@ignore
Feature: Grant admin roles to a data-plane user.
  Helper for tests that need a user with elevated privileges — call it with a username
  and one or more admin role enum names:
    karate.call('classpath:iomete/helpers/user/add-roles.feature',
                { username: 'karate-test-user', roles: ['IAM_MANAGER', 'DOMAIN_MANAGER'] })
  Valid roles: DOMAIN_MANAGER, IAM_MANAGER, SPARK_CATALOG_MANAGER,
  DATA_SECURITY_AND_AUDIT_MANAGER, COMPUTE_RESOURCES_MANAGER, ADMINISTRATION_MANAGER,
  MULTI_CLUSTER_MANAGER, READ_ONLY_ADMIN. An unknown name rejects the whole request.
  Returns:
    roles  the user's roles after the grant, as returned by GET .../roles

  Scenario: grant the roles, then reload the user's roles
    * def username = username.toLowerCase()
    * def rolesPath = 'api/v1/admin/identity/users/' + username + '/roles'

    Given url baseUrl
    And path rolesPath
    And request roles
    When method post
    # 200 = granted; 409 = the user already has (some of) these roles, which is fine
    Then assert responseStatus == 200 || responseStatus == 409

    Given url baseUrl
    And path rolesPath
    When method get
    Then status 200
    * def roles = response
