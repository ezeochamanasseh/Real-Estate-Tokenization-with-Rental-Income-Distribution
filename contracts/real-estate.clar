;; Real Estate Tokenization Contract

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-invalid-amount (err u102))

;; Data Variables
(define-data-var total-properties uint u0)
(define-data-var total-supply uint u0)

;; Data Maps
(define-map properties 
    uint 
    { owner: principal, 
      price: uint,
      rental-income: uint,
      total-tokens: uint })

(define-map token-holdings 
    { property-id: uint, holder: principal } 
    uint)

;; Public Functions
(define-public (add-property (price uint) (total-tokens uint))
    (let ((property-id (var-get total-properties)))
        (if (is-eq tx-sender contract-owner)
            (begin
                (map-set properties property-id
                    { owner: contract-owner,
                      price: price,
                      rental-income: u0,
                      total-tokens: total-tokens })
                (var-set total-properties (+ property-id u1))
                (ok property-id))
            err-owner-only)))

(define-public (buy-tokens (property-id uint) (amount uint))
    (let ((property (unwrap! (map-get? properties property-id) err-not-found)))
        (if (< amount (get total-tokens property))
            (begin
                (map-set token-holdings 
                    { property-id: property-id, holder: tx-sender }
                    amount)
                (ok true))
            err-invalid-amount)))

(define-public (distribute-rental-income (property-id uint) (amount uint))
    (let ((property (unwrap! (map-get? properties property-id) err-not-found)))
        (if (is-eq tx-sender contract-owner)
            (begin
                (map-set properties property-id
                    (merge property { rental-income: amount }))
                (ok true))
            err-owner-only)))

;; Read Only Functions
(define-read-only (get-property (property-id uint))
    (map-get? properties property-id))

(define-read-only (get-token-balance (property-id uint) (holder principal))
    (default-to u0
        (map-get? token-holdings { property-id: property-id, holder: holder })))




(define-public (transfer-tokens (property-id uint) (recipient principal) (amount uint))
    (let (
        (sender-balance (get-token-balance property-id tx-sender))
        (property (unwrap! (map-get? properties property-id) err-not-found))
    )
        (if (>= sender-balance amount)
            (begin
                (map-set token-holdings 
                    { property-id: property-id, holder: tx-sender }
                    (- sender-balance amount))
                (map-set token-holdings 
                    { property-id: property-id, holder: recipient }
                    (+ (get-token-balance property-id recipient) amount))
                (ok true))
            err-invalid-amount)))




(define-map property-status uint bool)  ;; true = listed, false = unlisted

(define-public (toggle-property-listing (property-id uint))
    (let ((property (unwrap! (map-get? properties property-id) err-not-found)))
        (if (is-eq tx-sender contract-owner)
            (begin
                (map-set property-status 
                    property-id 
                    (not (default-to false (map-get? property-status property-id))))
                (ok true))
            err-owner-only)))


(define-map maintenance-funds uint uint)

(define-public (add-maintenance-fund (property-id uint) (amount uint))
    (let ((current-fund (default-to u0 (map-get? maintenance-funds property-id))))
        (if (is-eq tx-sender contract-owner)
            (begin
                (map-set maintenance-funds property-id (+ current-fund amount))
                (ok true))
            err-owner-only)))




(define-map token-price-history 
    { property-id: uint, timestamp: uint } 
    uint)

(define-public (update-token-price (property-id uint) (new-price uint))
    (let ((property (unwrap! (map-get? properties property-id) err-not-found)))
        (if (is-eq tx-sender contract-owner)
            (begin
                (map-set token-price-history 
                    { property-id: property-id, timestamp: stacks-block-height }
                    new-price)
                (ok true))
            err-owner-only)))



(define-map property-ratings 
    { property-id: uint, rater: principal } 
    uint)

(define-public (rate-property (property-id uint) (rating uint))
    (if (<= rating u5)
        (begin
            (map-set property-ratings 
                { property-id: property-id, rater: tx-sender }
                rating)
            (ok true))
        err-invalid-amount))


(define-map rental-income-history
    { property-id: uint, distribution-date: uint }
    uint)

(define-public (record-rental-distribution (property-id uint) (amount uint))
    (if (is-eq tx-sender contract-owner)
        (begin
            (map-set rental-income-history
                { property-id: property-id, distribution-date: stacks-block-height }
                amount)
            (ok true))
        err-owner-only))


;; Define vote tracking
(define-map property-votes 
    { property-id: uint, proposal-id: uint }
    { yes-votes: uint, no-votes: uint, end-height: uint })

(define-map latest-proposal-ids uint uint)

(define-read-only (get-latest-proposal-id (property-id uint))
    (map-get? latest-proposal-ids property-id))

(define-map voter-records
    { property-id: uint, proposal-id: uint, voter: principal }
    bool)

(define-public (create-proposal (property-id uint) (end-blocks uint))
    (let ((proposal-id (default-to u0 (get-latest-proposal-id property-id))))
        (if (is-eq tx-sender contract-owner)
            (begin
                (map-set property-votes
                    { property-id: property-id, proposal-id: (+ proposal-id u1) }
                    { yes-votes: u0, 
                      no-votes: u0, 
                      end-height: (+ stacks-block-height end-blocks) })
                (ok (+ proposal-id u1)))
            err-owner-only)))

(define-public (cast-vote (property-id uint) (proposal-id uint) (vote bool))
    (let ((voter-weight (get-token-balance property-id tx-sender))
          (current-votes (unwrap! (map-get? property-votes { property-id: property-id, proposal-id: proposal-id }) err-not-found)))
        (if (> voter-weight u0)
            (begin
                (map-set voter-records
                    { property-id: property-id, proposal-id: proposal-id, voter: tx-sender }
                    vote)
                (ok true))
            err-invalid-amount)))


(define-map maintenance-requests 
    { property-id: uint, request-id: uint }
    { requester: principal, description: (string-ascii 256), status: (string-ascii 20) })

(define-data-var request-counter uint u0)

(define-public (submit-maintenance-request (property-id uint) (description (string-ascii 256)))
    (let ((request-id (var-get request-counter)))
        (map-set maintenance-requests
            { property-id: property-id, request-id: request-id }
            { requester: tx-sender, 
              description: description, 
              status: "pending" })
        (var-set request-counter (+ request-id u1))
        (ok request-id)))

(define-public (update-request-status (property-id uint) (request-id uint) (new-status (string-ascii 20)))
    (if (is-eq tx-sender contract-owner)
        (let ((request (unwrap! (map-get? maintenance-requests { property-id: property-id, request-id: request-id }) err-not-found)))
            (map-set maintenance-requests
                { property-id: property-id, request-id: request-id }
                (merge request { status: new-status }))
            (ok true))
        err-owner-only))


(define-map staking-positions
    { property-id: uint, staker: principal }
    { amount: uint, start-height: uint })

(define-constant BLOCKS_PER_YEAR u52560)
(define-constant REWARD_RATE u5) ;; 5% annual reward

(define-public (stake-tokens (property-id uint) (amount uint))
    (let ((balance (get-token-balance property-id tx-sender)))
        (if (>= balance amount)
            (begin
                (map-set staking-positions
                    { property-id: property-id, staker: tx-sender }
                    { amount: amount, start-height: stacks-block-height })
                (ok true))
            err-invalid-amount)))

(define-read-only (get-staking-rewards (property-id uint) (staker principal))
    (let ((position (unwrap! (map-get? staking-positions { property-id: property-id, staker: staker }) err-not-found)))
        (ok (/ (* (get amount position) REWARD_RATE (- stacks-block-height (get start-height position))) BLOCKS_PER_YEAR))))


(define-map property-documents
    { property-id: uint, doc-id: uint }
    { name: (string-ascii 64), hash: (string-ascii 128), upload-height: uint })

(define-data-var doc-counter uint u0)

(define-public (add-document (property-id uint) (name (string-ascii 64)) (hash (string-ascii 128)))
    (let ((doc-id (var-get doc-counter)))
        (if (is-eq tx-sender contract-owner)
            (begin
                (map-set property-documents
                    { property-id: property-id, doc-id: doc-id }
                    { name: name, hash: hash, upload-height: stacks-block-height })
                (var-set doc-counter (+ doc-id u1))
                (ok doc-id))
            err-owner-only)))


(define-map property-metrics
    uint
    { total-rental-income: uint,
      occupancy-rate: uint,
      maintenance-costs: uint,
      last-updated: uint })

(define-public (update-property-metrics 
    (property-id uint) 
    (rental-income uint)
    (occupancy-rate uint)
    (maintenance-costs uint))
    (if (is-eq tx-sender contract-owner)
        (begin
            (map-set property-metrics
                property-id
                { total-rental-income: rental-income,
                  occupancy-rate: occupancy-rate,
                  maintenance-costs: maintenance-costs,
                  last-updated: stacks-block-height })
            (ok true))
        err-owner-only))


(define-map rental-distribution-schedule
    uint
    { last-distribution: uint, distribution-interval: uint })

(define-public (setup-rental-distribution (property-id uint) (interval uint))
    (if (is-eq tx-sender contract-owner)
        (begin
            (map-set rental-distribution-schedule
                property-id
                { last-distribution: stacks-block-height, distribution-interval: interval })
            (ok true))
        err-owner-only))

(define-map insurance-pools uint uint)
(define-map insurance-claims 
    { property-id: uint, claim-id: uint }
    { claimant: principal, amount: uint, status: (string-ascii 20) })
(define-data-var claim-counter uint u0)

(define-public (contribute-to-insurance (property-id uint) (amount uint))
    (let ((current-pool (default-to u0 (map-get? insurance-pools property-id))))
        (begin
            (map-set insurance-pools property-id (+ current-pool amount))
            (ok true))))

(define-public (submit-insurance-claim (property-id uint) (amount uint))
    (let ((claim-id (var-get claim-counter))
          (holder-tokens (get-token-balance property-id tx-sender))
          (pool-balance (default-to u0 (map-get? insurance-pools property-id))))
        (if (and (> holder-tokens u0) (<= amount pool-balance))
            (begin
                (map-set insurance-claims
                    { property-id: property-id, claim-id: claim-id }
                    { claimant: tx-sender, amount: amount, status: "pending" })
                (var-set claim-counter (+ claim-id u1))
                (ok claim-id))
            err-invalid-amount)))




(define-map auctions 
    uint 
    { seller: principal,
      start-price: uint,
      highest-bid: uint,
      highest-bidder: (optional principal),
      end-height: uint })

(define-map auction-bids
    { auction-id: uint, bidder: principal }
    uint)

(define-public (create-auction (property-id uint) (start-price uint) (duration uint))
    (let ((token-balance (get-token-balance property-id tx-sender)))
        (if (> token-balance u0)
            (begin
                (map-set auctions property-id
                    { seller: tx-sender,
                      start-price: start-price,
                      highest-bid: start-price,
                      highest-bidder: none,
                      end-height: (+ stacks-block-height duration) })
                (ok true))
            err-invalid-amount)))

(define-public (place-bid (property-id uint) (bid-amount uint))
    (let ((auction (unwrap! (map-get? auctions property-id) err-not-found))
          (current-highest (get highest-bid auction)))
        (if (and (> bid-amount current-highest) 
                 (< stacks-block-height (get end-height auction)))
            (begin
                (map-set auctions property-id
                    (merge auction 
                        { highest-bid: bid-amount,
                          highest-bidder: (some tx-sender) }))
                (map-set auction-bids
                    { auction-id: property-id, bidder: tx-sender }
                    bid-amount)
                (ok true))
            err-invalid-amount)))



(define-map token-locks
    { property-id: uint, holder: principal }
    { amount: uint, unlock-height: uint, bonus-rate: uint })

(define-constant MINIMUM_LOCK_BLOCKS u1000)
(define-constant MAXIMUM_LOCK_BLOCKS u52560)
(define-constant BASE_BONUS_RATE u10)

(define-public (lock-tokens (property-id uint) (amount uint) (lock-blocks uint))
    (let (
        (holder-balance (get-token-balance property-id tx-sender))
        (bonus-rate (calculate-bonus-rate lock-blocks))
    )
        (if (and 
            (>= holder-balance amount)
            (>= lock-blocks MINIMUM_LOCK_BLOCKS)
            (<= lock-blocks MAXIMUM_LOCK_BLOCKS))
            (begin
                (map-set token-locks
                    { property-id: property-id, holder: tx-sender }
                    { amount: amount,
                      unlock-height: (+ stacks-block-height lock-blocks),
                      bonus-rate: bonus-rate })
                (ok true))
            err-invalid-amount)))

(define-private (calculate-bonus-rate (lock-blocks uint))
    (let ((bonus-multiplier (/ lock-blocks MINIMUM_LOCK_BLOCKS)))
        (* BASE_BONUS_RATE bonus-multiplier)))


(define-map token-listings
    { property-id: uint, seller: principal }
    { amount: uint, price-per-token: uint })

(define-map token-offers
    { property-id: uint, seller: principal, buyer: principal }
    { amount: uint, price-per-token: uint, expiry: uint })

(define-public (list-tokens (property-id uint) (amount uint) (price-per-token uint))
    (let ((balance (get-token-balance property-id tx-sender)))
        (if (>= balance amount)
            (begin
                (map-set token-listings
                    { property-id: property-id, seller: tx-sender }
                    { amount: amount, price-per-token: price-per-token })
                (ok true))
            err-invalid-amount)))



(define-public (accept-offer (property-id uint) (buyer principal))
    (let ((offer (unwrap! (map-get? token-offers { property-id: property-id, seller: tx-sender, buyer: buyer }) err-not-found))
          (balance (get-token-balance property-id tx-sender)))
        (if (and 
            (>= balance (get amount offer))
            (< stacks-block-height (get expiry offer)))
            (begin
                (try! (transfer-tokens property-id buyer (get amount offer)))
                (ok true))
            err-invalid-amount)))