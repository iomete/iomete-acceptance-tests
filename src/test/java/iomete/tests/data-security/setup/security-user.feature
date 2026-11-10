@ignore
Feature: Shared onboarded query-user for data-security enforcement tests.
  Invoked once per run via karate.callSingle. Provisions karate-security-user so any
  enforcement test (deny / mask / row-filter / ...) can run a real query AS that user and
  observe Ranger enforcement. Onboarding = create + known password + an admin role (needed
  to mint an access token; does NOT make the user a Ranger superuser) + compute access.
  Also ensures the tables exist and the compute is warm (via security-db). Returns:
    user         the username
    userToken    an access token that runs queries AS the user (X-API-Token / Bearer)
    computeName  the warmed compute to target
    database     the seeded security database

  Scenario: onboard the user and hand back a ready-to-use access token
    * def sec = karate.callSingle('classpath:iomete/tests/data-security/setup/security-db.feature', { domain: domain })
    * def computeName = sec.computeName
    * def database = sec.database
    * def user = fixtures.securityUser
    * def password = 'Karate123!@#'

    * def created = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(user)' }
    * def pwd = call read('classpath:iomete/helpers/user/set-password.feature') { username: '#(user)', password: '#(password)' }
    * def roles = call read('classpath:iomete/helpers/user/add-roles.feature') { username: '#(user)', roles: ['DOMAIN_MANAGER'] }
    * def access = call read('classpath:iomete/helpers/compute/grant-compute-access.feature') { username: '#(user)', computeName: '#(computeName)', domain: '#(domain)' }
    * def token = call read('classpath:iomete/helpers/user/get-access-token.feature') { username: '#(user)', password: '#(password)' }
    * def userToken = token.accessToken
