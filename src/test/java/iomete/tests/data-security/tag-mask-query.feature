@lock=security
Feature: Data security — a tag-based mask hides a tagged column from a user (E2E enforcement)

  Proves a mask policy written against a classification tag reaches the columns carrying that
  tag, not just that the policy is stored.
  Arrange (admin): get or create a tag, attach it to customers.phone through an approved change
  request, and mask that tag with MASK_SHOW_LAST_4 for the query-user.
  Act (user): karate-security-user selects phone, as itself.
  Assert: admin still reads the real value; the user reads it with all but the last 4 hidden.
  Tags and policies reach Spark on a delay, so the query is retried until the mask applies.

  Background:
    * url baseUrl
    * def ctx = karate.callSingle('classpath:iomete/tests/data-security/setup/security-user.feature', { domain: domain })
    * def user = ctx.user
    * def database = ctx.database
    * def computeName = ctx.computeName
    * def userToken = ctx.userToken

    * def tagName = 'karate-pii-' + runId
    * def policyName = 'karate-tag-mask-phone-' + runId
    * def tagArgs = { tagName: '#(tagName)', database: '#(database)', table: 'customers', column: 'phone' }

    # teardown: the policy first, then the tag comes off the column, and only then can it go.
    # Each step is guarded so one failure does not leave the rest behind.
    * configure afterScenario =
      """
      function() {
        try { karate.call('classpath:iomete/helpers/security/delete-policy.feature', { kind: 'tag/mask', name: policyName }); } catch (e) { karate.log('policy teardown failed:', e); }
        var tagId = karate.get('tagId');
        if (!tagId) return;
        try { karate.call('classpath:iomete/helpers/security/tag-column.feature', karate.merge(tagArgs, { tagId: tagId, requestType: 'REMOVE' })); } catch (e) { karate.log('untag teardown failed:', e); }
        try { karate.call('classpath:iomete/helpers/security/delete-tag.feature', { tagId: tagId }); } catch (e) { karate.log('tag teardown failed:', e); }
      }
      """
    * def tagId = null

    # admin gets or creates the tag and attaches it to customers.phone
    * def tag = call read('classpath:iomete/helpers/security/ensure-tag.feature') { tagName: '#(tagName)' }
    * def tagId = tag.tagId
    * def added = call read('classpath:iomete/helpers/security/tag-column.feature') karate.merge(tagArgs, { tagId: tagId, requestType: 'ADD' })

    # ... and masks every column carrying the tag, for this user only
    * def tagMaskPolicy =
      """
      {
        name: '#(policyName)',
        description: 'iomete-api-testing-suite: show only the last 4 of tagged columns to the user',
        priority: 'NORMAL',
        tags: ['#(tagName)'],
        dataMaskPolicyItems: [ { dataMaskType: 'MASK_SHOW_LAST_4', users: ['#(user)'] } ]
      }
      """
    * def created = call read('classpath:iomete/helpers/security/create-policy.feature') { kind: 'tag/mask', policy: '#(tagMaskPolicy)' }

  Scenario: karate-security-user sees the tagged customers.phone with only its last 4 shown
    * def customers = read('classpath:iomete/tests/data-security/setup/data/customers.json')
    * def phone = customers.find(c => c.id == 1).phone
    * def lastFour = phone.substring(phone.length - 4)
    * def statement = "SELECT phone FROM " + database + ".customers WHERE id = 1"

    # admin (not in the policy) reads the real value
    * def adminRun = call read('classpath:iomete/helpers/query/run-query-v2.feature') { computeName: '#(computeName)', statement: '#(statement)' }
    * match adminRun.result.values == ['#(phone)']

    # the user reads it masked, retried until the tag and policy reach the compute
    * def isMasked = function(r){ return r.status == 'COMPLETED' && r.resultData != null && r.resultData.values[0] != phone }
    * def result = call read('classpath:iomete/helpers/query/run-query-v2-as.feature') { userToken: '#(userToken)', computeName: '#(computeName)', statement: '#(statement)', predicate: '#(isMasked)', attempts: 30 }

    * match result.status == 'COMPLETED'
    * def masked = result.resultData.values[0]
    * match masked != phone
    * assert masked.endsWith(lastFour)
