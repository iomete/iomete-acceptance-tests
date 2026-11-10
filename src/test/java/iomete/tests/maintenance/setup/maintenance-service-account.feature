@ignore
Feature: Onboard the service account a maintenance run executes as.
  A triggered run executes as the service account bound to the catalog, and the binding is
  checked against what this sets up: the account is a service account, a member of the domain,
  and can CONSUME the compute. Idempotent: the user and grants are get-or-create. The caller
  owns the account and removes it (grants first, see revoke-bundle-grants.feature).
  Call it with { computeName, serviceAccount }.

  Scenario: create the service account, make it a domain member and give it CONSUME on the compute
    * def created = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(serviceAccount)', type: 'SERVICE_ACCOUNT' }
    * def member = call read('classpath:iomete/helpers/domain/grant-domain-permissions.feature') { username: '#(serviceAccount)', permissions: [] }
    * def access = call read('classpath:iomete/helpers/compute/grant-compute-access.feature') { username: '#(serviceAccount)', computeName: '#(computeName)', domain: '#(domain)' }
