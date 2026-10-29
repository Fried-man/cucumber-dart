Feature: Second file

  Scenario: from the second entry file
    Given the counter is shown
    When I tap the button
    Then the counter shows "1"
