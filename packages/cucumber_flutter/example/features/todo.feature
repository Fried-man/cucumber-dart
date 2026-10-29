Feature: To-do list
  Keep track of what is left to do.

  Background:
    Given the app is running

  Scenario: Adding an item
    When I add "Buy milk"
    Then the list shows:
      | Buy milk |
    And I see "1 item left"

  Scenario: Completing an item
    Given the list has:
      | Buy milk     |
      | Walk the dog |
    When I complete "Buy milk"
    Then I see "1 item left"

  @smoke
  Scenario: An empty item is not added
    When I add ""
    Then the list is empty

  Scenario Outline: Counting what is left
    When I add <count> items
    Then I see "<left>"

    Examples:
      | count | left         |
      | 1     | 1 item left  |
      | 3     | 3 items left |
