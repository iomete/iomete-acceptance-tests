@lock=security
Feature: Data security: the admin access check names the policies that decide a user's access

  Proves the admin access check answers from the policies the catalog service actually loaded.
  Arrange (admin): onboard the query-user, deny it all access to salaries, hash-mask customers.email
  and row-filter customers to region 'AMER' for it.
  Act (admin): check the user's access to salaries and to customers.
  Assert: select on salaries is denied by the deny policy; select on customers is allowed, with email
  masked and rows filtered by those policies, each matched on the user.
  The catalog service pulls new policies on a delay (~10s), so each check is retried until its policies show.

  Background:
    * url baseUrl
    * if (!platformAtLeast('4.0.2')) { karate.log('the access check ships in 4.0.2+: skipping on ' + platformVersion); karate.abort() }
    * def ctx = karate.callSingle('classpath:iomete/tests/data-security/setup/security-user.feature', { domain: domain })
    * def user = ctx.user
    * def catalog = ctx.database.split('.')[0]
    * def database = ctx.database.split('.')[1]

    # Set before the creates so a failed create still removes the ones made; each delete runs even if another fails.
    * configure afterScenario =
      """
      function() {
        var policies = [['access', 'deny'], ['mask', 'mask'], ['filter', 'filter']];
        policies.forEach(function(p) {
          var created = karate.get(p[1]);
          if (!created) return;
          try {
            karate.call('classpath:iomete/helpers/security/delete-policy.feature', { kind: p[0], name: created.policyName });
          } catch (e) {
            karate.log('could not delete the ' + p[0] + ' policy ' + created.policyName + ': ' + e);
          }
        });
      }
      """

    * def deny = call read('classpath:iomete/tests/data-security/setup/policies/deny-salaries-policy.feature') { user: '#(user)', database: '#(ctx.database)' }
    * def mask = call read('classpath:iomete/tests/data-security/setup/policies/mask-email-policy.feature') { user: '#(user)', database: '#(ctx.database)' }
    * def filter = call read('classpath:iomete/tests/data-security/setup/policies/filter-region-policy.feature') { user: '#(user)', database: '#(ctx.database)' }

  Scenario: salaries is denied by the deny policy, customers is allowed with email masked and rows filtered
    * def selectOf = function(r){ return r.actions.find(a => a.action == 'select') }
    * def emailOf = function(r){ return r.columns.find(c => c.column == 'email') }
    * def accessPath = 'api/v1/admin/data-security/users/' + user + '/access'
    * def byUser = { type: 'USER', name: '#(user)' }

    * configure retry = { count: 15, interval: 5000 }
    Given path accessPath
    And params { catalog: '#(catalog)', database: '#(database)', table: 'salaries' }
    And retry until responseStatus == 200 && selectOf(response).policy != null && selectOf(response).policy.id == deny.policyId
    When method get
    Then status 200
    * def select = selectOf(response)
    * match select.allowed == false
    * match select.policy contains { name: '#(deny.policyName)', type: 'ACCESS' }
    * match select.principal == byUser

    * def masked = function(r){ var e = emailOf(r); return e != null && e.mask != null && e.mask.policy != null && e.mask.policy.id == mask.policyId }
    * def filtered = function(r){ return r.rowFilter != null && r.rowFilter.policy != null && r.rowFilter.policy.id == filter.policyId }
    Given path accessPath
    And params { catalog: '#(catalog)', database: '#(database)', table: 'customers' }
    And retry until responseStatus == 200 && masked(response) && filtered(response)
    When method get
    Then status 200
    * match selectOf(response).allowed == true
    * def email = emailOf(response)
    * match email.allowed == true
    * match email.mask.type == 'MASK_HASH'
    * match email.mask.policy contains { name: '#(mask.policyName)', type: 'MASK' }
    * match email.mask.principal == byUser
    * match response.rowFilter.expression == "region = 'AMER'"
    * match response.rowFilter.policy contains { name: '#(filter.policyName)', type: 'ROW_FILTER' }
    * match response.rowFilter.principal == byUser
