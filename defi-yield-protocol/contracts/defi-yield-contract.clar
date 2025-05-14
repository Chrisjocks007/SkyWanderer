;; SkyWanderer Loyalty System - Enhanced Version

;; Core Constants
(define-constant admin-key tx-sender)
(define-constant ERR-ACCESS-DENIED (err u5001))
(define-constant ERR-LOCATION-LOCKED (err u5002))
(define-constant ERR-POINTS-INVALID (err u5003))
(define-constant ERR-FUNDS-INSUFFICIENT (err u5004))
(define-constant ERR-LOCKUP-ACTIVE (err u5005))
(define-constant ERR-ACCOUNT-MISSING (err u5006))
(define-constant ERR-THRESHOLD-UNMET (err u5007))
(define-constant ERR-SYSTEM-PAUSED (err u5008))

;; Reward Token Definition
(define-fungible-token VOYAGER-POINTS)

;; System Control Flags
(define-data-var system-paused bool false)
(define-data-var safety-protocol bool false)

;; Program Parameters
(define-data-var points-reserve uint u0)
(define-data-var standard-earn-rate uint u500) ;; 5% standard rate (100 = 1%)
(define-data-var time-bonus uint u100) ;; 1% bonus for longer participation
(define-data-var entry-threshold uint u1000000) ;; Minimum participation amount

;; Data Structures
(define-map VoyagerAccount
    principal
    {
        points-locked: uint,
        earned-points: uint,
        last-activity: uint,
        rank-level: uint,
        rank-boost: uint
    }
)

(define-map JourneyPlan
    principal
    {
        points: uint,
        start-block: uint,
        last-claim: uint,
        lock-duration: uint
    }
)

(define-map RankTiers
    uint  ;; rank level
    {
        points-needed: uint,
        benefits-factor: uint
    }
)

;; System Setup
(define-public (setup-system)
    (begin
        (asserts! (is-eq tx-sender admin-key) ERR-ACCESS-DENIED)
        
        ;; Configure rank tiers
        (map-set RankTiers u1 
            {
                points-needed: u1000000,  ;; 1M uPoints
                benefits-factor: u100      ;; 1x
            })
        (map-set RankTiers u2
            {
                points-needed: u5000000,  ;; 5M uPoints
                benefits-factor: u150      ;; 1.5x
            })
        (map-set RankTiers u3
            {
                points-needed: u10000000, ;; 10M uPoints
                benefits-factor: u200      ;; 2x
            })
        
        (ok true)
    )
)

;; Lock points with optional time commitment
(define-public (lock-points (amount uint) (time-period uint))
    (let
        (
            (voyager-data (default-to 
                {
                    points-locked: u0,
                    earned-points: u0,
                    last-activity: u0,
                    rank-level: u0,
                    rank-boost: u100
                }
                (map-get? VoyagerAccount tx-sender)))
        )
        (asserts! (not (var-get system-paused)) ERR-SYSTEM-PAUSED)
        (asserts! (>= amount (var-get entry-threshold)) ERR-THRESHOLD-UNMET)
        
        ;; Transfer points to contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Calculate rank and multiplier
        (let
            (
                (new-total-locked (+ (get points-locked voyager-data) amount))
                (rank-value (determine-rank-level new-total-locked))
                (time-multiplier (calculate-time-multiplier time-period))
            )
            
            ;; Update journey plan details
            (map-set JourneyPlan
                tx-sender
                {
                    points: amount,
                    start-block: block-height,
                    last-claim: block-height,
                    lock-duration: time-period
                }
            )
            
            ;; Update voyager account with new rank data
            (map-set VoyagerAccount
                tx-sender
                (merge voyager-data
                    {
                        points-locked: new-total-locked,
                        rank-level: rank-value,
                        rank-boost: (* (rank-multiplier rank-value) time-multiplier),
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
                    last-activity: u0,
                    rank-level: u0,
                    rank-boost: u100
                }
                (map-get? VoyagerAccount tx-sender)))
            (journey-info (default-to
                {
                    points: u0,
                    start-block: u0,
                    last-claim: u0,
                    lock-duration: u0
                }
                (map-get? JourneyPlan tx-sender)))
            (current-locked (get points-locked voyager-data))
            (active-lock (get lock-duration journey-info))
        )
        (asserts! (not (var-get system-paused)) ERR-SYSTEM-PAUSED)
        (asserts! (<= amount current-locked) ERR-FUNDS-INSUFFICIENT)
        
        ;; Check if lock period is over
        (asserts! (<= (+ (get start-block journey-info) active-lock) block-height) ERR-LOCKUP-ACTIVE)
        
        ;; Transfer points from contract
        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        
        ;; Calculate new rank after withdrawal
        (let
            (
                (new-total-locked (- current-locked amount))
                (rank-value (determine-rank-level new-total-locked))
            )
            
            ;; Update voyager account with new rank data
            (map-set VoyagerAccount
                tx-sender
                (merge voyager-data
                    {
                        points-locked: new-total-locked,
                        rank-level: rank-value,
                        rank-boost: (rank-multiplier rank-value),
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
                    last-activity: u0,
                    rank-level: u0,
                    rank-boost: u100
                }
                (map-get? VoyagerAccount tx-sender)))
            (journey-info (default-to
                {
                    points: u0,
                    start-block: u0,
                    last-claim: u0,
                    lock-duration: u0
                }
                (map-get? JourneyPlan tx-sender)))
            (blocks-passed (- block-height (get last-claim journey-info)))
            (locked-points (get points-locked voyager-data))
            (boost-rate (get rank-boost voyager-data))
        )
        (asserts! (> locked-points u0) ERR-FUNDS-INSUFFICIENT)
        
        ;; Calculate rewards
        (let
            (
                (base-points (/ (* locked-points blocks-passed (var-get standard-earn-rate)) u1000000))
                (boosted-points (/ (* base-points boost-rate) u100))
            )
            
            ;; Mint reward tokens
            (try! (ft-mint? VOYAGER-POINTS boosted-points tx-sender))
            
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
                        earned-points: (+ (get earned-points voyager-data) boosted-points),
                        last-activity: block-height
                    }
                )
            )
            
            (ok boosted-points)
        )
    )
)

;; Helper Functions

;; Determine rank level based on locked points
(define-private (determine-rank-level (points-amount uint))
    (if (>= points-amount u10000000)
        u3  ;; Platinum rank
        (if (>= points-amount u5000000)
            u2  ;; Elite rank
            u1  ;; Explorer rank
        )
    )
)

;; Get rank multiplier
(define-private (rank-multiplier (rank uint))
    (if (is-eq rank u3)
        u200  ;; Platinum 2x
        (if (is-eq rank u2)
            u150  ;; Elite 1.5x
            u100  ;; Explorer 1x
        )
    )
)

;; Calculate time multiplier based on lock period
(define-private (calculate-time-multiplier (lock-period uint))
    (if (>= lock-period u8640)     ;; 2 months
        u150                        ;; 1.5x multiplier
        (if (>= lock-period u4320) ;; 1 month
            u125                    ;; 1.25x multiplier
            u100                    ;; 1x multiplier (no lock)
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

;; Toggle safety protocol
(define-public (toggle-safety-protocol (active bool))
    (begin
        (asserts! (is-eq tx-sender admin-key) ERR-ACCESS-DENIED)
        (var-set safety-protocol active)
        (ok active)
    )
)