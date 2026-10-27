@shop
Feature: Checkout

  Background:
    Given the catalogue:
      | name  | price |
      | apple | €0.50 |

  @smoke
  Scenario: paying
    Given I add 2 "apple" to the cart
    When I pay
    Then the payment of €1.00 is accepted

  @slow
  Scenario: paying after the payment service restarted
    Given the payment service restarts once
    And I add 1 "apple" to the cart
    When I pay
    Then the payment of €0.50 is accepted

  Scenario: paying in Swiss francs
    Given I pay in CHF
    When I pay
    Then the payment of €0.00 is accepted

  @wip
  Scenario: an emailed invoice
    Given I add 1 "apple" to the cart
    When I pay
    Then the invoice is emailed
