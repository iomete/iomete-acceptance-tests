@ignore
Feature: Cancel a query via the V2 API until it is no longer active (plumbing, for teardown).
  Call it with:
    karate.call('classpath:iomete/helpers/query/cancel-query-v2.feature', { queryId: id })
  A query still PENDING cannot be cancelled yet (iom-sql answers 400) and would start once the
  scenario's lane is released, so the cancel is sent again every 2s, for up to a minute, until the
  query has finished or iom-sql does not know it. A query still active after that is logged by
  id, not failed: a teardown must not turn a slow cancel into a failed scenario.

  Scenario: cancel until finished
    # UNKNOWN: the status read failed, so the query may still be active
    * def active = ['PENDING', 'SUBMITTED', 'RUNNING', 'CANCELLING', 'UNKNOWN']
    * def attempt = function(){ return karate.call('classpath:iomete/helpers/query/cancel-query-v2-attempt.feature', { domain: domain, queryId: queryId }).status }
    * def cancelUntilFinished = function(){ var s; for (var i = 0; i < 30; i++) { s = attempt(); if (!s || !active.includes(s)) return s; java.lang.Thread.sleep(2000) } return s }
    * def status = cancelUntilFinished()
    * if (status && active.includes(status)) karate.log('WARNING: could not cancel query', queryId, '- it is still', status, 'and may keep the compute busy')
