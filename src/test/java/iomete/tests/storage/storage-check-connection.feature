@lock=api
Feature: Storage configs — the connection check really reaches an S3 bucket

  What this checks:
  - With the right keys, the storage connection check can list, write, read and delete in the
    test bucket.
  - With a wrong secret key, every operation fails, and the write is refused by the storage's
    own signature check.

  The check is the one storage-config call that contacts S3: iom-cluster connects to the bucket
  with the given keys and tries each operation, so these results only come from a real bucket.
  It always answers 200 and reports each operation as { success, errorMessage }.

  Needs an S3-compatible bucket the platform can reach and an access key for it. Skips unless
  IOMETE_STORAGE_ENDPOINT, IOMETE_STORAGE_BUCKET, IOMETE_STORAGE_ACCESS_KEY and
  IOMETE_STORAGE_SECRET_KEY are set (see AGENTS.md).

  Only a domain owner may run the check (a platform admin is not enough), so the run's user is
  made an owner of the suite's domain first. Like the domain itself, that is shared and never
  undone. Where ownership lives on the domain's bundle instead, the check still answers 403, and
  the scenario fails saying so.

  Not tested here (covered by iom-cluster's own tests): saving, editing and listing configs,
  which never contact S3, and the permission errors.

  Background:
    * url baseUrl
    * def getenv = function(name){ return java.lang.System.getenv(name) || null }
    * def settings = ({ IOMETE_STORAGE_ENDPOINT: getenv('IOMETE_STORAGE_ENDPOINT'), IOMETE_STORAGE_BUCKET: getenv('IOMETE_STORAGE_BUCKET'), IOMETE_STORAGE_ACCESS_KEY: getenv('IOMETE_STORAGE_ACCESS_KEY'), IOMETE_STORAGE_SECRET_KEY: getenv('IOMETE_STORAGE_SECRET_KEY') })
    * def missing = Object.keys(settings).filter(k => !settings[k])
    # name what is missing, so a half-published setup is visible instead of a silent skip
    * if (missing.length) karate.log('no test bucket configured, missing:', missing.join(', '), '- skipping')
    * if (missing.length) karate.abort()

    * karate.call('classpath:iomete/helpers/domain/ensure-domain-owner.feature', { domain: domain })

    # Each run works under its own folder of the bucket. The endpoint is custom and path-style, so the
    # region is only used for signing.
    * def connection = function(secretKey) { return { storageProvider: 'S3', region: 'us-east-1', endpointUrl: settings.IOMETE_STORAGE_ENDPOINT, bucket: settings.IOMETE_STORAGE_BUCKET, basePath: 'karate-' + runId, accessKey: settings.IOMETE_STORAGE_ACCESS_KEY, secretKey: secretKey } }
    * def checkPath = 'api/v1/domains/' + domain + '/storage-configs/check-connection'
    * def operations = ['List', 'Write', 'Read', 'Delete']

  Scenario: the right keys pass every operation and a wrong secret key fails them
    # Step 1: the right keys. Every operation succeeds.
    Given path checkPath
    And request connection(settings.IOMETE_STORAGE_SECRET_KEY)
    When method post
    # A 403 here means ownership did not take: where domain ownership lives on the domain's bundle
    # (onboardDomainAuthorizationRas), the owners list the helper sets is not what is checked.
    * if (responseStatus == 403) karate.fail('still not a domain owner after ensure-domain-owner: ' + response.errorMessage + ' (is domain ownership bundle-based on this target?)')
    Then status 200
    * def failed = operations.filter(op => !response[op].success).map(op => op + ': ' + response[op].errorMessage)
    And match failed == []

    # Step 2: a wrong secret key. No operation succeeds, and the write fails on S3's own signature
    # check, which shows the storage itself judged the key: an unreachable bucket fails every
    # operation with a network error ("Unable to execute HTTP request") instead.
    Given path checkPath
    And request connection('karate-not-the-secret-key')
    When method post
    Then status 200
    * def succeeded = operations.filter(op => response[op].success)
    And match succeeded == []
    And match response.Write.errorMessage !contains 'Unable to execute'
    # wording verified against RustFS
    And match response.Write.errorMessage == '#regex (?is).*signature.*'
