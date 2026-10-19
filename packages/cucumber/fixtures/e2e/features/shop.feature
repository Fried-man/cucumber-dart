@shop
Feature: Shop
  Every outcome that the dart test host maps (design §6).

  Background:
    Given a shop

  @smoke
  Scenario: passing
    Given a step passes

  Scenario: failing
    Given a step passes
    When a step fails with "boom"
    Then a step passes

  Scenario: pending
    Given a pending step

  Scenario: undefined
    Given a step passes
    And an undefined step with 3 cukes

  Scenario: ambiguous
    Given an ambiguous step

  @issue:123 @smoke
  Scenario: skipped
    Given a step skips

  Scenario: flaky
    Given a step that passes the second time

  Scenario: world parameters
    Then the world parameters are logged

  @wip
  Scenario: work in progress
    Given a step passes

  Rule: Payments

    @card
    Scenario Outline: pay with <method>
      Given I pay with "<method>"

      Examples: Cards
        | method |
        | visa   |
        | amex   |

      @cash
      Examples:
        | method |
        | cash   |
