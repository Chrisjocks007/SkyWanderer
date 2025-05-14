;; SkyWanderer Loyalty System - MVP
;; Version 0.1.0

;; Core Constants
(define-constant admin-key tx-sender)
(define-constant ERR-ACCESS-DENIED (err u5001))
(define-constant ERR-POINTS-INVALID (err u5003))
(define-constant ERR-FUNDS-INSUFFICIENT (err u5004))
(define-constant ERR-ACCOUNT-MISSING (err u5006))
(define-constant ERR-SYSTEM-PAUSED (err u5008))

;; Reward Token Definition
(define-fungible-token VOYAGER-POINTS)

;; System Control Flags
(define-data-var system-paused bool false)

;; Program Parameters
(define-data-var points-reserve uint u0)
(define-data-var standard-earn-rate uint u500) ;; 5% standard rate (100 = 1%)

;; Basic Data Structures
(define-map VoyagerAccount
    principal
    {
        points-locked: uint,
        earned-points: uint,
        last-activity: uint
    }
)

(define-map JourneyPlan
    principal
    {
        points: uint,
        start-block: uint,
        last-claim: uint
    }
)

;; System Setup
(define-public (setup-system)
    (begin
        (asserts! (is-eq tx-sender admin-key) ERR-ACCESS-DENIED)
        (ok true)
    )
)

;; Lock points 
(define-public (lock-points (amount uint))
    (let
        (
            (voyager-data (default-to 
                {
                    points-locked: u0,
                    earned-points: u0,
                    last-activity: u0
                }
                (map-get? VoyagerAccount tx-sender)))
        )
        (asserts! (not (var-get system-paused)) ERR-SYSTEM-PAUSED)
        (asserts! (> amount u0) ERR-POINTS-INVALID)
        
        ;; Transfer points to contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (let
            (
                (new-total-locked (+ (get points-locked voyager-data) amount))
            )
            
            ;; Update journey plan details
            (map-set JourneyPlan
                tx-sender
                {
                    points: amount,
                    start-block: block-height,
                    last-claim: block-height
                }
            )
            
            ;; Update voyager account
            (map-set VoyagerAccount
                tx-sender
                (merge voyager-data
                    {
                        points-locked: new-total-locked,
                        last-activity: block-height
                    }
                )
            )
            
            ;; Update points reserve
            (var-set points-reserve (+ (var-get points-reserve) amount))
            (ok true)
        )
    )
)

;; Withdraw points
(define-public (withdraw-points (amount uint))
    (let
        (
            (voyager-data (default-to 
                {
                    points-locked: u0,
                    earned-points: u0,
                    last-activity: u0
                }
                (map-get? VoyagerAccount tx-sender)))
            (current-locked (get points-locked voyager-data))
        )
        (asserts! (not (var-get system-paused)) ERR-SYSTEM-PAUSED)
        (asserts! (<= amount current-locked) ERR-FUNDS-INSUFFICIENT)
        
        ;; Transfer points from contract
        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        
        (let
            (
                (new-total-locked (- current-locked amount))
            )
            
            ;; Update voyager account
            (map-set VoyagerAccount
                tx-sender
                (merge voyager-data
                    {
                        points-locked: new-total-locked,
                        last-activity: block-height
                    }
                )
            )
            
            ;; Update points reserve
            (var-set points-reserve (- (var-get points-reserve) amount))
            (ok true)
        )
    )
)

;; Claim rewards based on locked points
(define-public (claim-rewards)
    (let
        (
            (voyager-data (default-to 
                {
                    points-locked: u0,
                    earned-points: u0,
                    last-activity: u0
                }
                (map-get? VoyagerAccount tx-sender)))
            (journey-info (default-to
                {
                    points: u0,
                    start-block: u0,
                    last-claim: u0
                }
                (map-get? JourneyPlan tx-sender)))
            (blocks-passed (- block-height (get last-claim journey-info)))
            (locked-points (get points-locked voyager-data))
        )
        (asserts! (> locked-points u0) ERR-FUNDS-INSUFFICIENT)
        
        ;; Calculate rewards
        (let
            (
                (base-points (/ (* locked-points blocks-passed (var-get standard-earn-rate)) u1000000))
            )
            
            ;; Mint reward tokens
            (try! (ft-mint? VOYAGER-POINTS base-points tx-sender))
            
            ;; Update journey plan
            (map-set JourneyPlan
                tx-sender
                (merge journey-info
                    {
                        last-claim: block-height
                    }
                )
            )
            
            ;; Update voyager account
            (map-set VoyagerAccount
                tx-sender
                (merge voyager-data
                    {
                        earned-points: (+ (get earned-points voyager-data) base-points),
                        last-activity: block-height
                    }
                )
            )
            
            (ok base-points)
        )
    )
)

;; Admin Functions

;; Set system status
(define-public (update-system-status (paused bool))
    (begin
        (asserts! (is-eq tx-sender admin-key) ERR-ACCESS-DENIED)
        (var-set system-paused paused)
        (ok paused)
    )
)