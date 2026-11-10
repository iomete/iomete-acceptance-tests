Feature: Save the target's OpenAPI specs next to the report.

  The gateway serves each backend service's spec at /openapi/<service>, but only to an
  authenticated caller. Saving them into the run's artifact lets tooling outside the suite
  (Backstage's API coverage view) compare what the suite called against the whole API surface
  of the exact build it ran on, without IOMETE credentials of its own.

  The workflow runs this after the suite, with its own --output so it cannot touch the suite's
  report. A spec that cannot be read is logged and skipped; this never fails a run. Targeted by
  path and never scanned, so it carries no @ignore.

  Scenario Outline: save the <service> spec
    Given url baseUrl
    And path 'openapi', '<service>'
    And param format = 'json'
    When method get
    * def saved = responseStatus == 200 && karate.typeOf(response) == 'map' && response.paths != null
    * if (saved) karate.write(response, 'openapi/<service>.json')
    * if (!saved) karate.log('could not save the <service> spec: HTTP', responseStatus)

    Examples:
      | service      |
      | core         |
      | cluster      |
      | iam          |
      | sql          |
      | catalog      |
      | rest-catalog |
      | maintenance  |
