---
name: ppcc-order-disruption-triage
description: >-
  Use this skill when a supplier delay, inventory shortage, or shipment risk
  may affect open Northwind customer orders.
version: lab-1
---

# Order disruption triage

**Policy version:** `lab-1`

## Evidence to gather

1. Identify the product and supplier from the disruption.
2. Read product reorder, target, and minimum reorder values.
3. Calculate available stock from inventory transactions.
4. Identify open order lines requiring the affected product.
5. Capture customer, order value, promised date, and current state.
6. Do not infer missing evidence. Escalate when required data cannot be read.

## Prioritization

1. Treat the event as a disruption when available stock is below reorder level
   and at least one order is exposed.
2. Rank orders by missed-SLA risk, customer tier, order value, then promised
   date.
3. Create one prioritized review Task.

## Recovery policy

When available stock is zero and three or more open orders are affected:

1. Recommend **Split Shipment** as the primary recovery.
2. Keep **Expedite Reorder** as the secondary option.
3. Require human approval before changing an order, committing spend, making a
   supplier commitment, sending communication, or invoking carrier automation.

## Completion and audit

1. Persist evidence, recommendation, alternatives, policy version, and approval
   requirement.
2. After approval, execute only the action named in the decision.
3. Record deterministic and Computer Use outcomes with timestamps.
4. Never send external communication in this lab.
