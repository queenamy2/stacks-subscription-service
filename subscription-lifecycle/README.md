# Subscription Service Smart Contract

A Clarity smart contract for managing subscription-based services on the Stacks blockchain.

## Overview

This smart contract implements a flexible subscription system allowing users to purchase, upgrade, downgrade, and request refunds for subscription tiers. The contract supports multiple subscription tiers with different pricing, durations, and feature sets.

## Key Features

- **Multiple Subscription Tiers**: Support for various subscription levels with configurable prices, durations, and features
- **Subscription Management**: Users can purchase, upgrade, and downgrade subscriptions
- **Prorated Credits**: Automatic calculation of remaining subscription value when changing plans
- **Refund System**: Configurable refund window with automatic refund calculation
- **Admin Controls**: Contract owner can create tiers and update system parameters

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| u100 | ERR-NOT-CONTRACT-OWNER | Operation restricted to contract owner |
| u101 | ERR-USER-ALREADY-SUBSCRIBED | User already has an active subscription |
| u102 | ERR-USER-NOT-SUBSCRIBED | Operation requires an active subscription |
| u103 | ERR-USER-BALANCE-TOO-LOW | Insufficient funds for the operation |
| u104 | ERR-SUBSCRIPTION-PLAN-NOT-FOUND | Referenced subscription tier doesn't exist |
| u105 | ERR-SUBSCRIPTION-TERM-ENDED | Subscription is no longer active |
| u106 | ERR-REFUND-NOT-ALLOWED | Refund is not allowed for this tier or condition |
| u107 | ERR-ATTEMPTING-SAME-PLAN-UPGRADE | Cannot upgrade to the same plan |
| u108 | ERR-REFUND-WINDOW-EXPIRED | Refund period has expired |
| u109 | ERR-INVALID-PLAN-TIER-CHANGE | Invalid tier change direction (upgrade/downgrade) |
| u110 | ERR-INVALID-PARAMETER-VALUE | Invalid parameter provided to function |

## Contract Data

### Data Variables

- `contract-owner`: Principal address of the contract administrator
- `minimum-subscription-cost`: Minimum allowed cost for any subscription tier
- `standard-subscription-duration`: Default duration for subscription tiers
- `maximum-refund-window`: Time window during which refunds are permitted (in seconds)
- `subscription-change-penalty`: Fee charged when changing subscription plans

### Data Maps

1. **SubscriberProfile**: Stores subscriber information
   - Key: User principal
   - Values:
     - `is-subscription-active`: Boolean indicating active status
     - `subscription-activation-time`: Block when subscription began
     - `subscription-expiration-time`: Block when subscription ends
     - `active-subscription-tier`: Name of current subscription tier
     - `subscription-payment-amount`: Amount paid for current subscription
     - `subscription-credit-balance`: Unused credit from plan changes

2. **SubscriptionTierConfiguration**: Stores tier configurations
   - Key: Tier name (string-ascii 20)
   - Values:
     - `tier-price`: Cost in STX microunits
     - `tier-duration-blocks`: Duration in blocks
     - `tier-feature-list`: List of features included
     - `tier-level`: Numerical tier level (higher = better tier)
     - `tier-refund-eligibility`: Whether tier permits refunds

3. **UserRefundLog**: Tracks refund history
   - Key: Composite of subscriber principal and refund timestamp
   - Values:
     - `refunded-amount`: Amount refunded
     - `refund-justification`: Reason for refund

## Public Functions

### Subscription Management

- `purchase-subscription-tier`: Purchase a new subscription tier
- `upgrade-subscription-tier`: Upgrade to a higher-level tier
- `downgrade-subscription-tier`: Downgrade to a lower-level tier
- `request-subscription-refund`: Request a refund for current subscription

### Administrative Functions

- `create-subscription-tier`: Create a new subscription tier
- `update-refund-window`: Update the maximum refund window duration
- `update-tier-change-fee`: Update the fee for changing subscription plans

## Read-Only Functions

- `get-subscriber-details`: Get details of a subscriber's profile
- `get-subscription-tier-details`: Get details of a subscription tier
- `calculate-subscription-time-remaining`: Calculate remaining subscription time
- `calculate-eligible-refund-amount`: Calculate eligible refund amount

## Default Subscription Tiers

The contract initializes with two default subscription tiers:

1. **Basic Tier**
   - Price: 50 STX
   - Duration: 30 days
   - Features: Basic Platform Access, Standard Customer Support, Core Feature Set
   - Refund eligible: Yes

2. **Premium Tier**
   - Price: 100 STX
   - Duration: 30 days
   - Features: Premium Platform Access, 24/7 Priority Support, Complete Feature Set, Advanced Analytics Dashboard
   - Refund eligible: Yes

## Usage Examples

### Purchasing a Subscription

```clarity
(contract-call? .subscription-service purchase-subscription-tier "basic-tier")
```

### Upgrading a Subscription

```clarity
(contract-call? .subscription-service upgrade-subscription-tier "premium-tier")
```

### Requesting a Refund

```clarity
(contract-call? .subscription-service request-subscription-refund "No longer need service")
```

## Implementation Notes

- Subscription duration is tracked in blocks
- Refund calculations are prorated based on remaining subscription time
- Subscription changes (upgrades/downgrades) include a penalty fee
- Tier levels determine valid upgrade/downgrade paths