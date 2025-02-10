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
