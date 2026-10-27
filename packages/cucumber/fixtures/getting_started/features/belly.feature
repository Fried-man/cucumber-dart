Feature: Belly
  A belly growls when it has eaten enough cucumbers and waited.

  @smoke
  Scenario: a few cukes
    Given I have 42 cukes in my belly
    When I wait 1 hour
    Then my belly should growl

  Scenario: not enough cukes
    Given I have 3 cukes in my belly
    When I wait 2 hours
    Then my belly should not growl

  Scenario Outline: eating <count> cukes
    Given I have <count> cukes in my belly
    When I wait 1 hour
    Then my belly should <outcome>

    Examples:
      | count | outcome   |
      | 11    | growl     |
      | 10    | not growl |
