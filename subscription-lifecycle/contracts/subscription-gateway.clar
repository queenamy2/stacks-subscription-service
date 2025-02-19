;; Subscription Service Smart Contract

;; Error codes
(define-constant ERR-NOT-CONTRACT-OWNER (err u100))
(define-constant ERR-USER-ALREADY-SUBSCRIBED (err u101))
(define-constant ERR-USER-NOT-SUBSCRIBED (err u102))
(define-constant ERR-USER-BALANCE-TOO-LOW (err u103))
(define-constant ERR-SUBSCRIPTION-PLAN-NOT-FOUND (err u104))
(define-constant ERR-SUBSCRIPTION-TERM-ENDED (err u105))
(define-constant ERR-REFUND-NOT-ALLOWED (err u106))
(define-constant ERR-ATTEMPTING-SAME-PLAN-UPGRADE (err u107))
(define-constant ERR-REFUND-WINDOW-EXPIRED (err u108))
(define-constant ERR-INVALID-PLAN-TIER-CHANGE (err u109))
(define-constant ERR-INVALID-PARAMETER-VALUE (err u110))

;; Data vars
(define-data-var contract-owner principal tx-sender)
(define-data-var minimum-subscription-cost uint u100)
(define-data-var standard-subscription-duration uint u2592000)
(define-data-var maximum-refund-window uint u259200)  ;; 3 days in seconds
(define-data-var subscription-change-penalty uint u1000000)     ;; 1 STX fee for changing plans

;; Data maps
(define-map SubscriberProfile
    principal
    {
        is-subscription-active: bool,
        subscription-activation-time: uint,
        subscription-expiration-time: uint,
        active-subscription-tier: (string-ascii 20),
        subscription-payment-amount: uint,
        subscription-credit-balance: uint
    }
)

(define-map SubscriptionTierConfiguration
    (string-ascii 20)
    {
        tier-price: uint,
        tier-duration-blocks: uint,
        tier-feature-list: (list 10 (string-ascii 50)),
        tier-level: uint,  ;; Higher number means higher tier
        tier-refund-eligibility: bool
    }
)

(define-map UserRefundLog
    { subscriber: principal, refund-timestamp: uint }
    {
        refunded-amount: uint,
        refund-justification: (string-ascii 50)
    }
)

;; Read-only functions
(define-read-only (get-subscriber-details (subscriber-address principal))
    (map-get? SubscriberProfile subscriber-address)
)

(define-read-only (get-subscription-tier-details (tier-name (string-ascii 20)))
    (map-get? SubscriptionTierConfiguration tier-name)
)

(define-read-only (calculate-subscription-time-remaining (subscriber-address principal))
    (let (
        (subscriber-info (unwrap! (map-get? SubscriberProfile subscriber-address) u0))
    )
    (if (get is-subscription-active subscriber-info)
        (- (get subscription-expiration-time subscriber-info) block-height)
        u0
    ))
)

(define-read-only (calculate-eligible-refund-amount (subscriber-address principal))
    (let (
        (subscriber-info (unwrap! (map-get? SubscriberProfile subscriber-address) u0))
        (elapsed-subscription-time (- block-height (get subscription-activation-time subscriber-info)))
        (total-subscription-duration (- (get subscription-expiration-time subscriber-info) (get subscription-activation-time subscriber-info)))
        (original-subscription-payment (get subscription-payment-amount subscriber-info))
    )
    (if (> elapsed-subscription-time (var-get maximum-refund-window))
        u0
        (/ (* original-subscription-payment (- total-subscription-duration elapsed-subscription-time)) total-subscription-duration)
    ))
)

;; Private functions
(define-private (verify-contract-owner)
    (is-eq tx-sender (var-get contract-owner))
)

(define-private (process-subscription-refund (subscriber principal) (refund-amount uint) (refund-reason (string-ascii 50)))
    (begin
        (try! (stx-transfer? refund-amount (var-get contract-owner) subscriber))
        (map-set UserRefundLog
            { subscriber: subscriber, refund-timestamp: block-height }
            {
                refunded-amount: refund-amount,
                refund-justification: refund-reason
            }
        )
        (ok true)
    )
)

(define-private (validate-feature-list (tier-features (list 10 (string-ascii 50))))
    (let ((feature-count (len tier-features)))
        (and (> feature-count u0) (<= feature-count u10))
    )
)

;; Function for creating subscription tiers
(define-public (create-subscription-tier 
    (tier-name (string-ascii 20))
    (tier-cost uint)
    (tier-duration uint)
    (tier-features (list 10 (string-ascii 50)))
    (tier-level uint)
    (allows-refunds bool))
    (begin
        (asserts! (verify-contract-owner) ERR-NOT-CONTRACT-OWNER)
        (asserts! (> tier-cost u0) ERR-INVALID-PARAMETER-VALUE)
        (asserts! (> tier-duration u0) ERR-INVALID-PARAMETER-VALUE)
        (asserts! (> tier-level u0) ERR-INVALID-PARAMETER-VALUE)
        (asserts! (validate-feature-list tier-features) ERR-INVALID-PARAMETER-VALUE)
        (asserts! (not (is-eq tier-name "")) ERR-INVALID-PARAMETER-VALUE)
        (ok (map-set SubscriptionTierConfiguration
            tier-name
            {
                tier-price: tier-cost,
                tier-duration-blocks: tier-duration,
                tier-feature-list: tier-features,
                tier-level: tier-level,
                tier-refund-eligibility: allows-refunds
            }
        ))
    )
)

;; Public functions for tier management
(define-public (purchase-subscription-tier (selected-tier-name (string-ascii 20)))
    (let (
        (tier-info (unwrap! (map-get? SubscriptionTierConfiguration selected-tier-name) ERR-SUBSCRIPTION-PLAN-NOT-FOUND))
        (current-time block-height)
        (tier-cost (get tier-price tier-info))
        (existing-subscription (get-subscriber-details tx-sender))
    )
    (asserts! (is-none existing-subscription) ERR-USER-ALREADY-SUBSCRIBED)
    (asserts! (not (is-eq selected-tier-name "")) ERR-INVALID-PARAMETER-VALUE)
    (asserts! (> tier-cost u0) ERR-INVALID-PARAMETER-VALUE)
    (try! (stx-transfer? tier-cost tx-sender (var-get contract-owner)))
    
    (ok (map-set SubscriberProfile
        tx-sender
        {
            is-subscription-active: true,
            subscription-activation-time: current-time,
            subscription-expiration-time: (+ current-time (get tier-duration-blocks tier-info)),
            active-subscription-tier: selected-tier-name,
            subscription-payment-amount: tier-cost,
            subscription-credit-balance: u0
        }
    ))
))

(define-public (request-subscription-refund (refund-reason (string-ascii 50)))
    (let (
        (subscriber-info (unwrap! (map-get? SubscriberProfile tx-sender) ERR-USER-NOT-SUBSCRIBED))
        (tier-info (unwrap! (map-get? SubscriptionTierConfiguration (get active-subscription-tier subscriber-info)) ERR-SUBSCRIPTION-PLAN-NOT-FOUND))
        (calculated-refund-amount (calculate-eligible-refund-amount tx-sender))
    )
    (asserts! (get is-subscription-active subscriber-info) ERR-USER-NOT-SUBSCRIBED)
    (asserts! (get tier-refund-eligibility tier-info) ERR-REFUND-NOT-ALLOWED)
    (asserts! (> calculated-refund-amount u0) ERR-REFUND-NOT-ALLOWED)
    (asserts! (not (is-eq refund-reason "")) ERR-INVALID-PARAMETER-VALUE)
    
    (try! (process-subscription-refund tx-sender calculated-refund-amount refund-reason))
    
    (ok (map-set SubscriberProfile
        tx-sender
        {
            is-subscription-active: false,
            subscription-activation-time: (get subscription-activation-time subscriber-info),
            subscription-expiration-time: block-height,
            active-subscription-tier: (get active-subscription-tier subscriber-info),
            subscription-payment-amount: u0,
            subscription-credit-balance: u0
        }
    ))
))

(define-public (upgrade-subscription-tier (new-tier-name (string-ascii 20)))
    (begin
        (let (
            (current-subscription (unwrap! (map-get? SubscriberProfile tx-sender) ERR-USER-NOT-SUBSCRIBED))
            (current-tier (unwrap! (map-get? SubscriptionTierConfiguration (get active-subscription-tier current-subscription)) ERR-SUBSCRIPTION-PLAN-NOT-FOUND))
            (new-tier (unwrap! (map-get? SubscriptionTierConfiguration new-tier-name) ERR-SUBSCRIPTION-PLAN-NOT-FOUND))
            (remaining-time (calculate-subscription-time-remaining tx-sender))
            (remaining-value (* (get subscription-payment-amount current-subscription) (/ remaining-time (get tier-duration-blocks current-tier))))
        )
        (asserts! (get is-subscription-active current-subscription) ERR-USER-NOT-SUBSCRIBED)
        (asserts! (> (get tier-level new-tier) (get tier-level current-tier)) ERR-INVALID-PLAN-TIER-CHANGE)
        (asserts! (not (is-eq new-tier-name (get active-subscription-tier current-subscription))) ERR-ATTEMPTING-SAME-PLAN-UPGRADE)
        
        (let (
            (upgrade-cost (- (get tier-price new-tier) remaining-value))
        )
        (try! (stx-transfer? (+ upgrade-cost (var-get subscription-change-penalty)) tx-sender (var-get contract-owner)))
        
        (ok (map-set SubscriberProfile
            tx-sender
            {
                is-subscription-active: true,
                subscription-activation-time: block-height,
                subscription-expiration-time: (+ block-height (get tier-duration-blocks new-tier)),
                active-subscription-tier: new-tier-name,
                subscription-payment-amount: (get tier-price new-tier),
                subscription-credit-balance: u0
            }
        ))
    ))
))

(define-public (downgrade-subscription-tier (new-tier-name (string-ascii 20)))
    (begin
        (let (
            (current-subscription (unwrap! (map-get? SubscriberProfile tx-sender) ERR-USER-NOT-SUBSCRIBED))
            (current-tier (unwrap! (map-get? SubscriptionTierConfiguration (get active-subscription-tier current-subscription)) ERR-SUBSCRIPTION-PLAN-NOT-FOUND))
            (new-tier (unwrap! (map-get? SubscriptionTierConfiguration new-tier-name) ERR-SUBSCRIPTION-PLAN-NOT-FOUND))
            (remaining-time (calculate-subscription-time-remaining tx-sender))
        )
        (asserts! (get is-subscription-active current-subscription) ERR-USER-NOT-SUBSCRIBED)
        (asserts! (< (get tier-level new-tier) (get tier-level current-tier)) ERR-INVALID-PLAN-TIER-CHANGE)
        
        (let (
            (remaining-value (* (get subscription-payment-amount current-subscription) (/ remaining-time (get tier-duration-blocks current-tier))))
            (credit-amount (- remaining-value (get tier-price new-tier)))
        )
        (try! (stx-transfer? (var-get subscription-change-penalty) tx-sender (var-get contract-owner)))
        
        (ok (map-set SubscriberProfile
            tx-sender
            {
                is-subscription-active: true,
                subscription-activation-time: block-height,
                subscription-expiration-time: (+ block-height (get tier-duration-blocks new-tier)),
                active-subscription-tier: new-tier-name,
                subscription-payment-amount: (get tier-price new-tier),
                subscription-credit-balance: credit-amount
            }
        ))
    ))
))

;; Admin functions
(define-public (update-refund-window (new-window-duration uint))
    (begin
        (asserts! (verify-contract-owner) ERR-NOT-CONTRACT-OWNER)
        (asserts! (> new-window-duration u0) ERR-INVALID-PARAMETER-VALUE)
        (ok (var-set maximum-refund-window new-window-duration))
    )
)

(define-public (update-tier-change-fee (new-fee-amount uint))
    (begin
        (asserts! (verify-contract-owner) ERR-NOT-CONTRACT-OWNER)
        (asserts! (>= new-fee-amount u0) ERR-INVALID-PARAMETER-VALUE)
        (ok (var-set subscription-change-penalty new-fee-amount))
    )
)

;; Initial contract setup
(begin
    ;; Add default subscription tiers
    (try! (create-subscription-tier
        "basic-tier"  ;; Basic tier plan
        u50000000  ;; 50 STX
        u2592000   ;; 30 days
        (list 
            "Basic Platform Access"
            "Standard Customer Support"
            "Core Feature Set"
        )
        u1  ;; Tier 1
        true ;; Allows refunds
    ))
    
    (try! (create-subscription-tier
        "premium-tier"  ;; Premium tier plan
        u100000000  ;; 100 STX
        u2592000    ;; 30 days
        (list 
            "Premium Platform Access"
            "24/7 Priority Support"
            "Complete Feature Set"
            "Advanced Analytics Dashboard"
        )
        u2  ;; Tier 2
        true ;; Allows refunds
    ))
)