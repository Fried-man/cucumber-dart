@shop
Feature: Cart
  Customers collect products in a cart before they pay.

  Background:
    Given the catalogue:
      | name   | price |
      | apple  | €0.50 |
      | banana | €0.25 |
      | melon  | €2.00 |

  @smoke
  Scenario: one product
    When I add 3 "apple" to the cart
    Then the cart contains 3 "apple"
    And the total is €1.50

  Scenario: the cart as a table
    When I add 1 "apple" to the cart
    And I add 4 "banana" to the cart
    # #docregion data-table
    Then the cart is:
      | product | quantity |
      | apple   | 1        |
      | banana  | 4        |
    # #enddocregion data-table
    And the cart has 5 items

  Scenario: the receipt
    When I add 2 "melon" to the cart
    # #docregion doc-string
    Then the receipt is:
      """application/json
      {"items": [{"name": "melon", "quantity": 2}], "total": 400}
      """
    # #enddocregion doc-string

  Rule: orders from €10.00 get 10% off

    Scenario Outline: <count> melons cost <total>
      When I add <count> "melon" to the cart
      Then the total is <total>

      Examples:
        | count | total  |
        | 4     | €8.00  |
        | 5     | €9.00  |
        | 10    | €18.00 |
