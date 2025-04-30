;; skill-tide-core
;; 
;; This contract manages the SkillTide platform's core functionality:
;; - User profiles with skills, interests, and location data
;; - Skill listings and discovery
;; - Time-credit economy (earning by teaching, spending by learning)
;; - Exchange requests, confirmations, and dispute handling
;; - User reputation tracking

;; ========== Error Constants ==========

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-USER-ALREADY-EXISTS (err u101))
(define-constant ERR-USER-NOT-FOUND (err u102))
(define-constant ERR-INVALID-PROFILE-DATA (err u103))
(define-constant ERR-INSUFFICIENT-CREDITS (err u104))
(define-constant ERR-EXCHANGE-NOT-FOUND (err u105))
(define-constant ERR-INVALID-EXCHANGE-STATUS (err u106))
(define-constant ERR-INVALID-CREDIT-AMOUNT (err u107))
(define-constant ERR-INVALID-RATING (err u108))
(define-constant ERR-NOT-EXCHANGE-PARTICIPANT (err u109))
(define-constant ERR-SAME-USER (err u110))
(define-constant ERR-ALREADY-RATED (err u111))
(define-constant ERR-EXCHANGE-NOT-COMPLETED (err u112))

;; ========== Data Maps & Variables ==========

;; User profile map: stores user details, skills, interests, and location
(define-map user-profiles
  { user: principal }
  {
    username: (string-utf8 50),
    bio: (string-utf8 500),
    skills: (list 20 {
      skill-name: (string-utf8 50),
      category: (string-utf8 50),
      description: (string-utf8 200)
    }),
    interests: (list 20 (string-utf8 50)),
    location: (optional {
      latitude: decimal,
      longitude: decimal,
      city: (string-utf8 50),
      country: (string-utf8 50)
    }),
    time-credits: uint,
    reputation-score: uint,
    joined-at: uint
  }
)

;; Exchange requests
(define-map exchanges
  { exchange-id: uint }
  {
    teacher: principal,
    student: principal,
    skill: (string-utf8 50),
    credits: uint,
    status: (string-utf8 20), ;; "pending", "accepted", "completed", "disputed", "cancelled"
    created-at: uint,
    completed-at: (optional uint),
    teacher-rating: (optional uint),
    student-rating: (optional uint),
    notes: (string-utf8 500)
  }
)

;; User reputation details
(define-map user-reputation
  { user: principal }
  {
    total-exchanges: uint,
    completed-exchanges: uint,
    average-rating: uint,  ;; 0-100 scale (e.g., 85 = 4.25/5)
    ratings-received: uint,
    ratings-given: uint,
    disputes: uint
  }
)

;; Track the next exchange ID
(define-data-var next-exchange-id uint u1)

;; Platform fee percentage (in basis points, 100 = 1%)
(define-data-var platform-fee-bps uint u500) ;; 5% default fee

;; ========== Private Functions ==========

;; Check if user exists
(define-private (user-exists (user principal))
  (default-to false (map-get? user-profiles { user: user }))
)

;; Get user time credits balance
(define-private (get-user-credits (user principal))
  (default-to u0 (get time-credits (map-get? user-profiles { user: user })))
)

;; Internal function to update user credits
(define-private (update-user-credits (user principal) (amount int))
  (let (
    (current-balance (get-user-credits user))
    (new-balance (if (< amount 0)
                    (- current-balance (abs amount))
                    (+ current-balance amount)))
  )
    (map-set user-profiles
      { user: user }
      (merge (default-to
        {
          username: "",
          bio: "",
          skills: (list ),
          interests: (list ),
          location: none,
          time-credits: u0,
          reputation-score: u0,
          joined-at: u0
        }
        (map-get? user-profiles { user: user }))
        { time-credits: new-balance })
    )
  )
)

;; Generate a new exchange ID
(define-private (generate-exchange-id)
  (let ((current-id (var-get next-exchange-id)))
    (var-set next-exchange-id (+ current-id u1))
    current-id
  )
)

;; Calculate fee for an exchange
(define-private (calculate-fee (amount uint))
  (/ (* amount (var-get platform-fee-bps)) u10000)
)

;; Update reputation after a completed exchange
(define-private (update-reputation (user principal) (rating uint))
  (let (
    (user-rep (default-to {
      total-exchanges: u0,
      completed-exchanges: u0,
      average-rating: u0,
      ratings-received: u0,
      ratings-given: u0,
      disputes: u0
    } (map-get? user-reputation { user: user })))
    (current-total-rating (* (get average-rating user-rep) (get ratings-received user-rep)))
    (new-ratings-received (+ (get ratings-received user-rep) u1))
    (new-total-rating (+ current-total-rating rating))
    (new-average-rating (/ new-total-rating new-ratings-received))
  )
    (map-set user-reputation
      { user: user }
      (merge user-rep {
        ratings-received: new-ratings-received,
        average-rating: new-average-rating
      })
    )
  )
)

;; ========== Read-Only Functions ==========

;; Get user profile
(define-read-only (get-user-profile (user principal))
  (map-get? user-profiles { user: user })
)

;; Get exchange details
(define-read-only (get-exchange (exchange-id uint))
  (map-get? exchanges { exchange-id: exchange-id })
)

;; Get user reputation
(define-read-only (get-user-reputation (user principal))
  (map-get? user-reputation { user: user })
)

;; Check if a user has a certain skill
(define-read-only (has-skill (user principal) (skill-name (string-utf8 50)))
  (let (
    (profile (map-get? user-profiles { user: user }))
  )
    (if (is-none profile)
      false
      (default-to false (some (filter (lambda (skill-item) 
        (is-eq (get skill-name skill-item) skill-name)) 
        (get skills (unwrap-panic profile)))))
    )
  )
)

;; Check the platform fee rate
(define-read-only (get-platform-fee-bps)
  (var-get platform-fee-bps)
)

;; ========== Public Functions ==========

;; Register a new user
(define-public (register-user 
  (username (string-utf8 50))
  (bio (string-utf8 500))
  (location (optional {
    latitude: decimal,
    longitude: decimal,
    city: (string-utf8 50),
    country: (string-utf8 50)
  }))
)
  (let (
    (caller tx-sender)
  )
    (if (user-exists caller)
      ERR-USER-ALREADY-EXISTS
      (begin
        (map-set user-profiles
          { user: caller }
          {
            username: username,
            bio: bio,
            skills: (list ),
            interests: (list ),
            location: location,
            time-credits: u10, ;; New users get 10 starter credits
            reputation-score: u0,
            joined-at: block-height
          }
        )
        (map-set user-reputation
          { user: caller }
          {
            total-exchanges: u0,
            completed-exchanges: u0,
            average-rating: u0,
            ratings-received: u0,
            ratings-given: u0,
            disputes: u0
          }
        )
        (ok true)
      )
    )
  )
)

;; Update user profile
(define-public (update-profile
  (username (string-utf8 50))
  (bio (string-utf8 500))
  (location (optional {
    latitude: decimal,
    longitude: decimal,
    city: (string-utf8 50),
    country: (string-utf8 50)
  }))
)
  (let (
    (caller tx-sender)
    (existing-profile (map-get? user-profiles { user: caller }))
  )
    (if (is-none existing-profile)
      ERR-USER-NOT-FOUND
      (begin
        (map-set user-profiles
          { user: caller }
          (merge (unwrap-panic existing-profile)
            {
              username: username,
              bio: bio,
              location: location
            }
          )
        )
        (ok true)
      )
    )
  )
)

;; Add a skill to user profile
(define-public (add-skill
  (skill-name (string-utf8 50))
  (category (string-utf8 50))
  (description (string-utf8 200))
)
  (let (
    (caller tx-sender)
    (existing-profile (map-get? user-profiles { user: caller }))
  )
    (if (is-none existing-profile)
      ERR-USER-NOT-FOUND
      (let (
        (new-skill {
          skill-name: skill-name,
          category: category,
          description: description
        })
        (current-skills (get skills (unwrap-panic existing-profile)))
      )
        (map-set user-profiles
          { user: caller }
          (merge (unwrap-panic existing-profile)
            { skills: (append current-skills new-skill) }
          )
        )
        (ok true)
      )
    )
  )
)

;; Add an interest to user profile
(define-public (add-interest (interest (string-utf8 50)))
  (let (
    (caller tx-sender)
    (existing-profile (map-get? user-profiles { user: caller }))
  )
    (if (is-none existing-profile)
      ERR-USER-NOT-FOUND
      (let (
        (current-interests (get interests (unwrap-panic existing-profile)))
      )
        (map-set user-profiles
          { user: caller }
          (merge (unwrap-panic existing-profile)
            { interests: (append current-interests interest) }
          )
        )
        (ok true)
      )
    )
  )
)

;; Create a new exchange request
(define-public (create-exchange-request
  (teacher principal)
  (skill (string-utf8 50))
  (credits uint)
  (notes (string-utf8 500))
)
  (let (
    (caller tx-sender)
    (exchange-id (generate-exchange-id))
  )
    (asserts! (not (is-eq caller teacher)) ERR-SAME-USER)
    (asserts! (user-exists caller) ERR-USER-NOT-FOUND)
    (asserts! (user-exists teacher) ERR-USER-NOT-FOUND)
    (asserts! (has-skill teacher skill) ERR-INVALID-PROFILE-DATA)
    (asserts! (>= (get-user-credits caller) credits) ERR-INSUFFICIENT-CREDITS)
    
    ;; Lock the credits from student
    (update-user-credits caller (* -1 credits))
    
    ;; Create the exchange
    (map-set exchanges
      { exchange-id: exchange-id }
      {
        teacher: teacher,
        student: caller,
        skill: skill,
        credits: credits,
        status: "pending",
        created-at: block-height,
        completed-at: none,
        teacher-rating: none,
        student-rating: none,
        notes: notes
      }
    )
    
    ;; Update reputation stats
    (let (
      (teacher-rep (default-to {
        total-exchanges: u0,
        completed-exchanges: u0,
        average-rating: u0,
        ratings-received: u0,
        ratings-given: u0,
        disputes: u0
      } (map-get? user-reputation { user: teacher })))
      (student-rep (default-to {
        total-exchanges: u0,
        completed-exchanges: u0,
        average-rating: u0,
        ratings-received: u0,
        ratings-given: u0,
        disputes: u0
      } (map-get? user-reputation { user: caller })))
    )
      (map-set user-reputation
        { user: teacher }
        (merge teacher-rep {
          total-exchanges: (+ (get total-exchanges teacher-rep) u1)
        })
      )
      (map-set user-reputation
        { user: caller }
        (merge student-rep {
          total-exchanges: (+ (get total-exchanges student-rep) u1)
        })
      )
    )
    
    (ok exchange-id)
  )
)

;; Accept an exchange request (as teacher)
(define-public (accept-exchange (exchange-id uint))
  (let (
    (caller tx-sender)
    (exchange (map-get? exchanges { exchange-id: exchange-id }))
  )
    (asserts! (is-some exchange) ERR-EXCHANGE-NOT-FOUND)
    (let (
      (exchange-data (unwrap-panic exchange))
    )
      (asserts! (is-eq caller (get teacher exchange-data)) ERR-NOT-AUTHORIZED)
      (asserts! (is-eq (get status exchange-data) "pending") ERR-INVALID-EXCHANGE-STATUS)
      
      (map-set exchanges
        { exchange-id: exchange-id }
        (merge exchange-data { status: "accepted" })
      )
      (ok true)
    )
  )
)

;; Complete an exchange (as teacher - marks teaching as done)
(define-public (complete-exchange (exchange-id uint))
  (let (
    (caller tx-sender)
    (exchange (map-get? exchanges { exchange-id: exchange-id }))
  )
    (asserts! (is-some exchange) ERR-EXCHANGE-NOT-FOUND)
    (let (
      (exchange-data (unwrap-panic exchange))
    )
      (asserts! (is-eq caller (get teacher exchange-data)) ERR-NOT-AUTHORIZED)
      (asserts! (is-eq (get status exchange-data) "accepted") ERR-INVALID-EXCHANGE-STATUS)
      
      ;; Transfer the credits to teacher (minus platform fee)
      (let (
        (credits (get credits exchange-data))
        (fee (calculate-fee credits))
        (net-credits (- credits fee))
      )
        (update-user-credits caller net-credits)
        
        ;; Update exchange status
        (map-set exchanges
          { exchange-id: exchange-id }
          (merge exchange-data { 
            status: "completed",
            completed-at: (some block-height)
          })
        )
        
        ;; Update reputation stats
        (let (
          (teacher-rep (default-to {
            total-exchanges: u0,
            completed-exchanges: u0,
            average-rating: u0,
            ratings-received: u0,
            ratings-given: u0,
            disputes: u0
          } (map-get? user-reputation { user: caller })))
          (student-rep (default-to {
            total-exchanges: u0,
            completed-exchanges: u0,
            average-rating: u0,
            ratings-received: u0,
            ratings-given: u0,
            disputes: u0
          } (map-get? user-reputation { user: (get student exchange-data) })))
        )
          (map-set user-reputation
            { user: caller }
            (merge teacher-rep {
              completed-exchanges: (+ (get completed-exchanges teacher-rep) u1)
            })
          )
          (map-set user-reputation
            { user: (get student exchange-data) }
            (merge student-rep {
              completed-exchanges: (+ (get completed-exchanges student-rep) u1)
            })
          )
        )
        
        (ok true)
      )
    )
  )
)

;; Rate an exchange participant
(define-public (rate-exchange
  (exchange-id uint)
  (rating uint)
  (is-rating-teacher bool)
)
  (let (
    (caller tx-sender)
    (exchange (map-get? exchanges { exchange-id: exchange-id }))
  )
    (asserts! (is-some exchange) ERR-EXCHANGE-NOT-FOUND)
    (asserts! (<= rating u100) ERR-INVALID-RATING) ;; Rating must be between 0-100 (represents 0-5 stars)
    
    (let (
      (exchange-data (unwrap-panic exchange))
      (teacher (get teacher exchange-data))
      (student (get student exchange-data))
    )
      ;; Verify the exchange is completed
      (asserts! (is-eq (get status exchange-data) "completed") ERR-EXCHANGE-NOT-COMPLETED)
      
      ;; Verify caller is a participant
      (asserts! (or (is-eq caller teacher) (is-eq caller student)) ERR-NOT-EXCHANGE-PARTICIPANT)
      
      ;; Check if rating is for teacher or student and update accordingly
      (if is-rating-teacher
        (begin
          ;; Student is rating teacher
          (asserts! (is-eq caller student) ERR-NOT-AUTHORIZED)
          (asserts! (is-none (get teacher-rating exchange-data)) ERR-ALREADY-RATED)
          
          ;; Update exchange with teacher rating
          (map-set exchanges
            { exchange-id: exchange-id }
            (merge exchange-data { teacher-rating: (some rating) })
          )
          
          ;; Update teacher's reputation
          (update-reputation teacher rating)
          
          ;; Update rater's stats
          (let (
            (student-rep (default-to {
              total-exchanges: u0,
              completed-exchanges: u0,
              average-rating: u0,
              ratings-received: u0,
              ratings-given: u0,
              disputes: u0
            } (map-get? user-reputation { user: student })))
          )
            (map-set user-reputation
              { user: student }
              (merge student-rep {
                ratings-given: (+ (get ratings-given student-rep) u1)
              })
            )
          )
        )
        (begin
          ;; Teacher is rating student
          (asserts! (is-eq caller teacher) ERR-NOT-AUTHORIZED)
          (asserts! (is-none (get student-rating exchange-data)) ERR-ALREADY-RATED)
          
          ;; Update exchange with student rating
          (map-set exchanges
            { exchange-id: exchange-id }
            (merge exchange-data { student-rating: (some rating) })
          )
          
          ;; Update student's reputation
          (update-reputation student rating)
          
          ;; Update rater's stats
          (let (
            (teacher-rep (default-to {
              total-exchanges: u0,
              completed-exchanges: u0,
              average-rating: u0,
              ratings-received: u0,
              ratings-given: u0,
              disputes: u0
            } (map-get? user-reputation { user: teacher })))
          )
            (map-set user-reputation
              { user: teacher }
              (merge teacher-rep {
                ratings-given: (+ (get ratings-given teacher-rep) u1)
              })
            )
          )
        )
      )
      
      (ok true)
    )
  )
)

;; Initiate a dispute for an exchange
(define-public (dispute-exchange (exchange-id uint) (reason (string-utf8 500)))
  (let (
    (caller tx-sender)
    (exchange (map-get? exchanges { exchange-id: exchange-id }))
  )
    (asserts! (is-some exchange) ERR-EXCHANGE-NOT-FOUND)
    
    (let (
      (exchange-data (unwrap-panic exchange))
      (teacher (get teacher exchange-data))
      (student (get student exchange-data))
    )
      ;; Verify caller is a participant
      (asserts! (or (is-eq caller teacher) (is-eq caller student)) ERR-NOT-EXCHANGE-PARTICIPANT)
      
      ;; Verify the exchange is not already completed or disputed
      (asserts! (not (is-eq (get status exchange-data) "disputed")) ERR-INVALID-EXCHANGE-STATUS)
      (asserts! (not (is-eq (get status exchange-data) "completed")) ERR-INVALID-EXCHANGE-STATUS)
      
      ;; Update exchange status
      (map-set exchanges
        { exchange-id: exchange-id }
        (merge exchange-data { 
          status: "disputed",
          notes: (concat (get notes exchange-data) (concat " | Dispute: " reason))
        })
      )
      
      ;; Update dispute counter for the person who started the dispute
      (let (
        (user-rep (default-to {
          total-exchanges: u0,
          completed-exchanges: u0,
          average-rating: u0,
          ratings-received: u0,
          ratings-given: u0,
          disputes: u0
        } (map-get? user-reputation { user: caller })))
      )
        (map-set user-reputation
          { user: caller }
          (merge user-rep {
            disputes: (+ (get disputes user-rep) u1)
          })
        )
      )
      
      (ok true)
    )
  )
)

;; Administrative function to set platform fee (contract owner only)
(define-public (set-platform-fee (new-fee-bps uint))
  (begin
    (asserts! (is-eq tx-sender (contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-fee-bps u2000) ERR-INVALID-CREDIT-AMOUNT) ;; Max fee of 20%
    (var-set platform-fee-bps new-fee-bps)
    (ok true)
  )
)

;; Helper function to get contract owner
(define-read-only (contract-owner)
  (contract-call? 'SP000000000000000000002Q6VF78.poc-registry get-contract-owner)
)

;; Administrative function to resolve a dispute
(define-public (resolve-dispute 
  (exchange-id uint) 
  (resolution (string-utf8 100))
  (credits-to-teacher uint)
)
  (let (
    (caller tx-sender)
    (exchange (map-get? exchanges { exchange-id: exchange-id }))
  )
    (asserts! (is-eq caller (contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (is-some exchange) ERR-EXCHANGE-NOT-FOUND)
    
    (let (
      (exchange-data (unwrap-panic exchange))
      (teacher (get teacher exchange-data))
      (student (get student exchange-data))
      (total-credits (get credits exchange-data))
    )
      ;; Verify the exchange is disputed
      (asserts! (is-eq (get status exchange-data) "disputed") ERR-INVALID-EXCHANGE-STATUS)
      (asserts! (<= credits-to-teacher total-credits) ERR-INVALID-CREDIT-AMOUNT)
      
      ;; Calculate fee only on the portion that goes to teacher
      (let (
        (fee (calculate-fee credits-to-teacher))
        (net-credits (- credits-to-teacher fee))
        (return-to-student (- total-credits credits-to-teacher))
      )
        ;; Transfer the appropriate credits
        (update-user-credits teacher net-credits)
        (update-user-credits student return-to-student)
        
        ;; Update exchange status
        (map-set exchanges
          { exchange-id: exchange-id }
          (merge exchange-data { 
            status: "completed",
            completed-at: (some block-height),
            notes: (concat (get notes exchange-data) (concat " | Resolution: " resolution))
          })
        )
        
        (ok true)
      )
    )
  )
)