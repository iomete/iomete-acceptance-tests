@lock=api
Feature: Example of your own test

  Tests in this folder run with the IOMETE tests, and IOMETE releases never change them.
  Copy this one as a starting point, or delete it.

  Background:
    # baseUrl and domain come from the suite's settings
    * url baseUrl

  Scenario: the domains can be listed
    Given path 'api/v1/admin/domains'
    When method get
    Then status 200
    And match response[*].name contains domain
