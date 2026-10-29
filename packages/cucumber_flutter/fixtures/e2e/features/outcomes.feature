Feature: Outcomes

  @smoke
  Scenario: passed
    Given the counter is shown
    When I tap the button
    Then the counter shows "1"

  Scenario: failed
    Given the counter is shown
    Then the counter shows "5"

  Scenario: widget exception
    Given a widget that throws while building
    Then the counter shows "0"

  Scenario: undefined
    Given a step nobody wrote

  Scenario: pending
    Given a pending step

  Scenario: skipped
    Given a skipped step

  Scenario: flaky
    Given the counter is shown
    And a step that fails the first attempt
