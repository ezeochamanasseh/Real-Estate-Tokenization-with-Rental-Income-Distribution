(define-constant err-unauthorized (err u300))
(define-constant err-no-claimable (err u301))
(define-constant err-invalid-property (err u302))
(define-constant PRECISION u1000000)
(define-constant BONUS_THRESHOLD u2160)
(define-constant MAX_BONUS_MULTIPLIER u150)

(define-map revenue-pools
    uint
    { total-revenue: uint,
      distributed-revenue: uint,
      last-distribution: uint,
      performance-score: uint })

(define-map holder-rewards
    { property-id: uint, holder: principal }
    { claimable-amount: uint,
      last-claim-height: uint,
      bonus-multiplier: uint,
      total-claimed: uint })

(define-map performance-metrics
    uint
    { occupancy-rate: uint,
      maintenance-efficiency: uint,
      rent-growth: uint,
      tenant-satisfaction: uint })

(define-public (initialize-revenue-pool (property-id uint))
    (let ((property (unwrap! (contract-call? .real-estate get-property property-id) err-invalid-property)))
        (map-set revenue-pools property-id
            { total-revenue: u0,
              distributed-revenue: u0,
              last-distribution: stacks-block-height,
              performance-score: u100 })
        (ok true)))

(define-public (deposit-revenue (property-id uint) (amount uint))
    (let ((pool (unwrap! (map-get? revenue-pools property-id) err-invalid-property)))
        (map-set revenue-pools property-id
            (merge pool { total-revenue: (+ (get total-revenue pool) amount) }))
        (ok true)))

(define-public (calculate-holder-reward (property-id uint) (holder principal))
    (let (
        (token-balance (contract-call? .real-estate get-token-balance property-id holder))
        (property (unwrap! (contract-call? .real-estate get-property property-id) err-invalid-property))
        (pool (unwrap! (map-get? revenue-pools property-id) err-invalid-property))
        (total-tokens (get total-tokens property))
        (undistributed (- (get total-revenue pool) (get distributed-revenue pool)))
        (base-reward (/ (* undistributed token-balance) total-tokens))
        (bonus-multiplier (calculate-performance-bonus property-id holder))
        (final-reward (/ (* base-reward bonus-multiplier) u100))
    )
        (map-set holder-rewards 
            { property-id: property-id, holder: holder }
            { claimable-amount: final-reward,
              last-claim-height: stacks-block-height,
              bonus-multiplier: bonus-multiplier,
              total-claimed: u0 })
        (ok final-reward)))

(define-public (claim-rewards (property-id uint))
    (let (
        (reward-info (unwrap! (map-get? holder-rewards { property-id: property-id, holder: tx-sender }) err-no-claimable))
        (claimable (get claimable-amount reward-info))
        (pool (unwrap! (map-get? revenue-pools property-id) err-invalid-property))
    )
        (if (> claimable u0)
            (begin
                (map-set holder-rewards
                    { property-id: property-id, holder: tx-sender }
                    (merge reward-info 
                        { claimable-amount: u0,
                          total-claimed: (+ (get total-claimed reward-info) claimable) }))
                (map-set revenue-pools property-id
                    (merge pool { distributed-revenue: (+ (get distributed-revenue pool) claimable) }))
                (ok claimable))
            err-no-claimable)))

(define-private (calculate-performance-bonus (property-id uint) (holder principal))
    (let (
        (metrics (default-to 
            { occupancy-rate: u80, maintenance-efficiency: u75, rent-growth: u100, tenant-satisfaction: u85 }
            (map-get? performance-metrics property-id)))
        (staking-duration (get-staking-duration property-id holder))
        (base-score (/ (+ (get occupancy-rate metrics) 
                         (get maintenance-efficiency metrics) 
                         (get rent-growth metrics) 
                         (get tenant-satisfaction metrics)) u4))
        (duration-bonus (if (>= staking-duration BONUS_THRESHOLD) u125 u100))
        (performance-bonus (if (>= base-score u85) u120 u100))
            (combined-bonus (min-custom (/ (* duration-bonus performance-bonus) u100) MAX_BONUS_MULTIPLIER))
        )
            combined-bonus))
    
    (define-private (min-custom (a uint) (b uint))
        (if (< a b) a b))

(define-private (get-staking-duration (property-id uint) (holder principal))
    (default-to u0 (some stacks-block-height)))

(define-public (update-performance-metrics 
    (property-id uint) 
    (occupancy uint) 
    (maintenance uint) 
    (growth uint) 
    (satisfaction uint))
    (begin
        (map-set performance-metrics property-id
            { occupancy-rate: occupancy,
              maintenance-efficiency: maintenance,
              rent-growth: growth,
              tenant-satisfaction: satisfaction })
        (ok true)))


(define-private (distribute-to-holder (holder-data { property-id: uint, holder: principal }))
    (calculate-holder-reward (get property-id holder-data) (get holder holder-data)))

(define-read-only (get-claimable-rewards (property-id uint) (holder principal))
    (map-get? holder-rewards { property-id: property-id, holder: holder }))

(define-read-only (get-revenue-pool-info (property-id uint))
    (map-get? revenue-pools property-id))

(define-read-only (get-performance-data (property-id uint))
    (map-get? performance-metrics property-id))
