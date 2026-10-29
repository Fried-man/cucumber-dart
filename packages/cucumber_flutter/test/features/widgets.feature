Feature: Widgets

  Scenario: tapping a button
    Given a button that counts taps
    When I tap it 2 times
    Then it shows "2"

  Scenario: a new widget tree
    Then there is no button
