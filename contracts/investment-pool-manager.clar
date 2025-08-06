;; Investment Pool Manager Contract
;; Enables collective investment in high-value properties through managed pools

;; Error constants
(define-constant err-unauthorized (err u400))
(define-constant err-pool-not-found (err u401))
(define-constant err-invalid-amount (err u402))
(define-constant err-pool-closed (err u403))
(define-constant err-insufficient-funds (err u404))
(define-constant err-target-not-met (err u405))
(define-constant err-already-finalized (err u406))
(define-constant err-deadline-passed (err u407))
(define-constant err-invalid-property (err u408))

;; Constants
(define-constant contract-owner tx-sender)
(define-constant MINIMUM_POOL_TARGET u100000) ;; Minimum target amount for a pool
(define-constant MAXIMUM_INVESTORS_PER_POOL u50)
(define-constant DEFAULT_FUNDING_PERIOD u4320) ;; ~30 days in blocks
(define-constant PRECISION u1000000)

;; Data variables
(define-data-var pool-counter uint u0)
(define-data-var total-pools-created uint u0)

;; Investment pool structure
(define-map investment-pools
    uint
    { creator: principal,
      property-id: (optional uint),
      target-amount: uint,
      current-amount: uint,
      minimum-contribution: uint,
      maximum-contribution: uint,
      deadline: uint,
      status: (string-ascii 20),
      investor-count: uint,
      pool-fee-rate: uint,
      creation-block: uint })

;; Individual investor contributions
(define-map pool-contributions
    { pool-id: uint, investor: principal }
    { amount: uint,
      contribution-block: uint,
      share-percentage: uint,
      rewards-claimed: uint })

;; Pool investor list tracking
(define-map pool-investor-list
    { pool-id: uint, index: uint }
    principal)

;; Pool statistics for performance tracking
(define-map pool-performance
    uint
    { total-returns: uint,
      monthly-yield: uint,
      risk-score: uint,
      last-updated: uint })

;; Reward distribution tracking
(define-map pool-rewards
    uint
    { total-distributed: uint,
      pending-distribution: uint,
      last-distribution-block: uint,
      distribution-frequency: uint })

;; Pool management fee tracking
(define-map management-fees
    uint
    { collected-fees: uint,
      fee-rate: uint,
      last-collection: uint })

;; Create new investment pool
(define-public (create-investment-pool 
    (target-amount uint) 
    (min-contribution uint) 
    (max-contribution uint) 
    (funding-period uint)
    (pool-fee-rate uint))
    (let ((pool-id (var-get pool-counter)))
        (if (and 
            (>= target-amount MINIMUM_POOL_TARGET)
            (> min-contribution u0)
            (>= max-contribution min-contribution)
            (> funding-period u0)
            (<= pool-fee-rate u1000)) ;; Max 10% fee
            (begin
                (map-set investment-pools pool-id
                    { creator: tx-sender,
                      property-id: none,
                      target-amount: target-amount,
                      current-amount: u0,
                      minimum-contribution: min-contribution,
                      maximum-contribution: max-contribution,
                      deadline: (+ stacks-block-height funding-period),
                      status: "funding",
                      investor-count: u0,
                      pool-fee-rate: pool-fee-rate,
                      creation-block: stacks-block-height })
                (map-set pool-performance pool-id
                    { total-returns: u0,
                      monthly-yield: u0,
                      risk-score: u5,
                      last-updated: stacks-block-height })
                (map-set pool-rewards pool-id
                    { total-distributed: u0,
                      pending-distribution: u0,
                      last-distribution-block: stacks-block-height,
                      distribution-frequency: u2160 }) ;; ~15 days default
                (var-set pool-counter (+ pool-id u1))
                (var-set total-pools-created (+ (var-get total-pools-created) u1))
                (ok pool-id))
            err-invalid-amount)))

;; Contribute to investment pool
(define-public (contribute-to-pool (pool-id uint) (amount uint))
    (let ((pool (unwrap! (map-get? investment-pools pool-id) err-pool-not-found))
          (existing-contribution (default-to 
            { amount: u0, contribution-block: u0, share-percentage: u0, rewards-claimed: u0 }
            (map-get? pool-contributions { pool-id: pool-id, investor: tx-sender })))
          (total-contribution (+ amount (get amount existing-contribution)))
          (current-investors (get investor-count pool)))
        (if (and 
            (is-eq (get status pool) "funding")
            (< stacks-block-height (get deadline pool))
            (>= amount (get minimum-contribution pool))
            (<= total-contribution (get maximum-contribution pool))
            (< current-investors MAXIMUM_INVESTORS_PER_POOL))
            (let ((new-current-amount (+ (get current-amount pool) amount))
                  (new-investor-count (if (is-eq (get amount existing-contribution) u0) 
                                        (+ current-investors u1) 
                                        current-investors))
                  (share-percentage (calculate-share-percentage new-current-amount amount)))
                (map-set investment-pools pool-id
                    (merge pool 
                        { current-amount: new-current-amount,
                          investor-count: new-investor-count }))
                (map-set pool-contributions 
                    { pool-id: pool-id, investor: tx-sender }
                    { amount: total-contribution,
                      contribution-block: stacks-block-height,
                      share-percentage: share-percentage,
                      rewards-claimed: u0 })
                (if (is-eq (get amount existing-contribution) u0)
                    (map-set pool-investor-list 
                        { pool-id: pool-id, index: current-investors }
                        tx-sender)
                    true)
                (ok true))
            err-invalid-amount)))

;; Finalize pool when target is reached
(define-public (finalize-pool (pool-id uint) (property-id uint))
    (let ((pool (unwrap! (map-get? investment-pools pool-id) err-pool-not-found))
          (property (unwrap! (contract-call? .real-estate get-property property-id) err-invalid-property)))
        (if (and 
            (is-eq tx-sender (get creator pool))
            (is-eq (get status pool) "funding")
            (>= (get current-amount pool) (get target-amount pool)))
            (begin
                (map-set investment-pools pool-id
                    (merge pool 
                        { status: "active",
                          property-id: (some property-id) }))
                (ok true))
            err-unauthorized)))

;; Distribute rental income to pool investors
(define-public (distribute-pool-income (pool-id uint) (total-income uint))
    (let ((pool (unwrap! (map-get? investment-pools pool-id) err-pool-not-found))
          (rewards (unwrap! (map-get? pool-rewards pool-id) err-pool-not-found))
          (management-fee (/ (* total-income (get pool-fee-rate pool)) u10000))
          (distributable-income (- total-income management-fee)))
        (if (and 
            (is-eq tx-sender (get creator pool))
            (is-eq (get status pool) "active"))
            (begin
                (map-set pool-rewards pool-id
                    (merge rewards 
                        { pending-distribution: (+ (get pending-distribution rewards) distributable-income),
                          last-distribution-block: stacks-block-height }))
                (map-set management-fees pool-id
                    { collected-fees: (+ (default-to u0 (get collected-fees (map-get? management-fees pool-id))) management-fee),
                      fee-rate: (get pool-fee-rate pool),
                      last-collection: stacks-block-height })
                (try! (process-investor-distributions pool-id distributable-income))
                (ok true))
            err-unauthorized)))

;; Process distributions to all investors in pool
(define-private (process-investor-distributions (pool-id uint) (distributable-amount uint))
    (let ((pool (unwrap! (map-get? investment-pools pool-id) err-pool-not-found))
          (investor-count (get investor-count pool)))
        (fold distribute-to-investor 
              (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19)
              { pool-id: pool-id, 
                distributable-amount: distributable-amount, 
                total-amount: (get current-amount pool),
                processed: u0,
                max-investors: investor-count })
        (ok true)))

;; Distribute income to individual investor
(define-private (distribute-to-investor 
    (index uint) 
    (context { pool-id: uint, distributable-amount: uint, total-amount: uint, processed: uint, max-investors: uint }))
    (if (< (get processed context) (get max-investors context))
        (let ((investor (map-get? pool-investor-list { pool-id: (get pool-id context), index: index }))
              (contribution (map-get? pool-contributions { pool-id: (get pool-id context), investor: (default-to tx-sender investor) })))
            (match investor
                investor-principal
                (match contribution
                    contrib-data
                    (let ((investor-share (/ (* (get distributable-amount context) (get amount contrib-data)) (get total-amount context))))
                        (map-set pool-contributions
                            { pool-id: (get pool-id context), investor: investor-principal }
                            (merge contrib-data 
                                { rewards-claimed: (+ (get rewards-claimed contrib-data) investor-share) }))
                        (merge context { processed: (+ (get processed context) u1) }))
                    context)
                context))
        context))

;; Claim investor rewards from pool
(define-public (claim-pool-rewards (pool-id uint))
    (let ((contribution (unwrap! (map-get? pool-contributions { pool-id: pool-id, investor: tx-sender }) err-pool-not-found))
          (claimable-amount (get rewards-claimed contribution)))
        (if (> claimable-amount u0)
            (begin
                (map-set pool-contributions 
                    { pool-id: pool-id, investor: tx-sender }
                    (merge contribution { rewards-claimed: u0 }))
                (ok claimable-amount))
            err-invalid-amount)))

;; Withdraw contribution if pool fails to reach target
(define-public (withdraw-failed-contribution (pool-id uint))
    (let ((pool (unwrap! (map-get? investment-pools pool-id) err-pool-not-found))
          (contribution (unwrap! (map-get? pool-contributions { pool-id: pool-id, investor: tx-sender }) err-pool-not-found)))
        (if (and 
            (>= stacks-block-height (get deadline pool))
            (< (get current-amount pool) (get target-amount pool))
            (is-eq (get status pool) "funding"))
            (begin
                (map-set investment-pools pool-id
                    (merge pool { status: "failed" }))
                (map-delete pool-contributions { pool-id: pool-id, investor: tx-sender })
                (ok (get amount contribution)))
            err-unauthorized)))

;; Update pool performance metrics
(define-public (update-pool-performance 
    (pool-id uint) 
    (total-returns uint) 
    (monthly-yield uint) 
    (risk-score uint))
    (let ((pool (unwrap! (map-get? investment-pools pool-id) err-pool-not-found)))
        (if (is-eq tx-sender (get creator pool))
            (begin
                (map-set pool-performance pool-id
                    { total-returns: total-returns,
                      monthly-yield: monthly-yield,
                      risk-score: risk-score,
                      last-updated: stacks-block-height })
                (ok true))
            err-unauthorized)))

;; Calculate share percentage for investor
(define-private (calculate-share-percentage (total-pool-amount uint) (investor-amount uint))
    (if (> total-pool-amount u0)
        (/ (* investor-amount PRECISION) total-pool-amount)
        u0))

;; Read-only functions
(define-read-only (get-pool-info (pool-id uint))
    (map-get? investment-pools pool-id))

(define-read-only (get-investor-contribution (pool-id uint) (investor principal))
    (map-get? pool-contributions { pool-id: pool-id, investor: investor }))

(define-read-only (get-pool-performance-data (pool-id uint))
    (map-get? pool-performance pool-id))

(define-read-only (get-pool-rewards-info (pool-id uint))
    (map-get? pool-rewards pool-id))

(define-read-only (get-management-fees-info (pool-id uint))
    (map-get? management-fees pool-id))

(define-read-only (get-total-pools-created)
    (var-get total-pools-created))

(define-read-only (calculate-potential-returns (pool-id uint) (investor principal))
    (let ((contribution (map-get? pool-contributions { pool-id: pool-id, investor: investor }))
          (pool (map-get? investment-pools pool-id))
          (performance (map-get? pool-performance pool-id)))
        (match contribution
            contrib-data
            (match pool
                pool-data
                (match performance
                    perf-data
                    (some (/ (* (get amount contrib-data) (get monthly-yield perf-data)) PRECISION))
                    none)
                none)
            none)))

