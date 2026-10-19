@belly
Feature: Belly
  A belly growls when it has eaten enough cucumbers and waited.

  Background:
    Given an empty belly

  @smoke
  Scenario: a few cukes
    Given I have 42 cukes in my belly
    When I wait 1 hour
    Then my belly should growl

  Scenario: not enough cukes
    Given I have 3 cukes in my belly
    When I wait 2 hours
    Then my belly should not growl

  Scenario: a meal plan
    Given I eat these cukes:
      | color | count |
      | red   | 5     |
      | green | 6     |
    Then my belly should contain 11 cukes
    And the meal plan notes are:
      """markdown
      Eat **green** ones last.
      """

  @wip
  Scenario: work in progress
    Given I have 1 cuke in my belly
    Then my belly should sing

  Rule: colours do not matter

    Scenario Outline: eating <count> <color> cukes
      Given I have <count> <color> cukes in my belly
      When I wait 1 hour
      Then my belly should <outcome>

      Examples: hungry
        | count | color | outcome   |
        | 11    | red   | growl     |
        | 12    | blue  | growl     |

      Examples: full
        | count | color | outcome   |
        | 2     | green | not growl |
