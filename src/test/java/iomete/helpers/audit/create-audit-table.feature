@ignore
Feature: Create the data access audit table on a given compute, if it is missing (helper).
  Usage: karate.call('classpath:iomete/helpers/audit/create-audit-table.feature', { domain: domain, computeName: name, computeDataPlane: plane })

  The statement is the one the docs (iom-docs user-guide/system-tables.md) ask an admin to run.
  The SQL compute's setup calls it before anything reads through that compute: events a compute
  sends before the table exists are rejected, and a compute that met many rejections then
  recorded later reads minutes late or not at all.

  Scenario: create the table if it is missing
    * def queryFeature = queryFeatureFor(computeDataPlane)
    * def run = function(statement){ karate.call(queryFeature, { domain: domain, computeName: computeName, statement: statement }) }
    * run('CREATE DATABASE IF NOT EXISTS spark_catalog.iomete_system_db')
    # Copied from the docs, so the table matches what the platform writes.
    * text ddl =
      """
      CREATE TABLE IF NOT EXISTS spark_catalog.iomete_system_db.data_access_audit (
        __id__ STRING NOT NULL, __ts__ TIMESTAMP NOT NULL, __write_id__ STRING NOT NULL,
        repositoryName STRING, repositoryType INT, clientIP STRING, accessType STRING,
        resourcePath STRING, logType STRING, agentId STRING, resultReason STRING,
        aclEnforcer STRING, requestData STRING, resourceType STRING, accessResult INT,
        eventDurationMS BIGINT, eventId STRING, zoneName STRING, policyId BIGINT,
        clientType STRING, eventCount INT, seqNum INT, sessionId STRING, eventTime BIGINT,
        additionalInfo STRING, clusterName STRING, agentHostname STRING, action STRING,
        user STRING, serviceType INT, serviceName STRING, policyVersion INT)
      USING iceberg
      PARTITIONED BY (days(__ts__), __write_id__)
      """
    * run(ddl)
