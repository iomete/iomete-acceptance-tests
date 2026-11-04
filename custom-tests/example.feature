@lock=api
Feature: Example of your own test

  Tests in this folder run with the IOMETE tests, and IOMETE releases never change them.
  Edit or delete this file.

  Background:
    * url baseUrl

  Scenario: the install has a connected data plane
    Given path 'api/v1/admin/multi-cluster/data-planes'
    When method get
    Then status 200
    And match response[*].status contains 'CONNECTED'
