@ignore
Feature: Create the data access audit table, as the docs tell an admin to (setup).
  Usage: karate.callSingle('classpath:iomete/tests/audit/setup/audit-table.feature', { domain: domain })

  With the dataAccessAudit flag on, computes send audit events to this table, but nothing
  creates it: the docs (iom-docs user-guide/system-tables.md) ask the admin to run this
  statement first, and events are dropped until then. The table is shared and never dropped,
  and stays after the run.

  Scenario: create the table if it is missing
    * def compute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * karate.call('classpath:iomete/helpers/audit/create-audit-table.feature', { domain: domain, computeName: compute.computeName, computeDataPlane: compute.computeDataPlane })
