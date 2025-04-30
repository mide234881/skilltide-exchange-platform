;; SkillTide Meetups Contract
;; This contract manages location-based skill exchange meetups on the SkillTide platform.
;; It handles creating, joining, and verifying in-person skill exchanges, with safety and
;; privacy features built in for real-world interactions.

;; Error Constants
(define-constant ERR-UNAUTHORIZED (err u1001))
(define-constant ERR-MEETUP-NOT-FOUND (err u1002))
(define-constant ERR-INVALID-LOCATION (err u1003))
(define-constant ERR-INSUFFICIENT-REPUTATION (err u1004))
(define-constant ERR-MEETUP-FULL (err u1005))
(define-constant ERR-ALREADY-REGISTERED (err u1006))
(define-constant ERR-NOT-REGISTERED (err u1007))
(define-constant ERR-ALREADY-CONFIRMED (err u1008))
(define-constant ERR-NOT-PARTICIPANT (err u1009))
(define-constant ERR-INVALID-TIME (err u1010))
(define-constant ERR-ATTENDANCE-VERIFICATION-FAILED (err u1011))
(define-constant ERR-MEETUP-ENDED (err u1012))
(define-constant ERR-MEETUP-NOT-STARTED (err u1013))
(define-constant ERR-INVALID-SKILL (err u1014))

;; Constants
(define-constant MINIMUM-HOST-REPUTATION u5)
(define-constant DEFAULT-MAX-PARTICIPANTS u10)
(define-constant ATTENDANCE-VERIFICATION-THRESHOLD u2) ;; Number of confirmations needed

;; Data Maps and Variables

;; Meetup map stores all information about a specific meetup
(define-map meetups
    { meetup-id: uint }
    {
        host: principal,
        title: (string-ascii 100),
        description: (string-utf8 500),
        skill-offered: (string-ascii 50),
        location-hash: (buff 32), ;; Hashed location data for privacy
        location-revealed: bool,  ;; Whether exact location has been revealed to participants
        exact-location: (optional (string-utf8 200)), ;; Only visible to confirmed participants
        max-participants: uint,
        start-time: uint,
        end-time: uint,
        status: (string-ascii 20), ;; "pending", "active", "completed", "cancelled"
        reputation-required: uint,
        created-at: uint
    }
)

;; Tracks participants of each meetup
(define-map meetup-participants
    { meetup-id: uint, participant: principal }
    {
        status: (string-ascii 20), ;; "registered", "confirmed", "attended", "no-show"
        registration-time: uint,
        confirmation-time: (optional uint),
        attendance-verified: bool
    }
)

;; Maps meetup to the list of participants for easy lookup
(define-map meetup-participant-list
    { meetup-id: uint }
    { participants: (list 50 principal) }
)

;; Tracks attendance confirmations from other participants
(define-map attendance-confirmations
    { meetup-id: uint, attendee: principal, confirmer: principal }
    { confirmed: bool, time: uint }
)

;; Counter for generating unique meetup IDs
(define-data-var last-meetup-id uint u0)

;; Private Functions

;; Generate a new unique meetup ID
(define-private (generate-meetup-id)
    (let ((current-id (var-get last-meetup-id)))
        (var-set last-meetup-id (+ current-id u1))
        (var-get last-meetup-id)
    )
)

;; Check if the user has sufficient reputation to host a meetup
(define-private (has-sufficient-host-reputation (user principal))
    ;; In a real implementation, this would query the main SkillTide contract
    ;; for the user's reputation. For this example, we'll assume all users have sufficient reputation.
    true
)

;; Check if the user has sufficient reputation to join a specific meetup
(define-private (has-sufficient-join-reputation (user principal) (meetup-id uint))
    (match (map-get? meetups { meetup-id: meetup-id })
        meetup-data
        (>= u5 (get reputation-required meetup-data)) ;; Placeholder check
        false
    )
)

;; Check if a meetup exists
(define-private (meetup-exists (meetup-id uint))
    (is-some (map-get? meetups { meetup-id: meetup-id }))
)

;; Check if a principal is the host of a meetup
(define-private (is-meetup-host (meetup-id uint) (user principal))
    (match (map-get? meetups { meetup-id: meetup-id })
        meetup-data (is-eq (get host meetup-data) user)
        false
    )
)

;; Check if a user is registered for a meetup
(define-private (is-participant (meetup-id uint) (user principal))
    (is-some (map-get? meetup-participants { meetup-id: meetup-id, participant: user }))
)

;; Add a participant to the meetup-participant-list
(define-private (add-participant-to-list (meetup-id uint) (participant principal))
    (match (map-get? meetup-participant-list { meetup-id: meetup-id })
        participant-list
        (map-set meetup-participant-list
            { meetup-id: meetup-id }
            { participants: (unwrap-panic (as-max-len? (append (get participants participant-list) participant) u50)) }
        )
        (map-set meetup-participant-list
            { meetup-id: meetup-id }
            { participants: (list participant) }
        )
    )
)

;; Get the number of current participants for a meetup
(define-private (get-participant-count (meetup-id uint))
    (match (map-get? meetup-participant-list { meetup-id: meetup-id })
        participant-list (len (get participants participant-list))
        u0
    )
)

;; Check if a meetup is full
(define-private (is-meetup-full (meetup-id uint))
    (match (map-get? meetups { meetup-id: meetup-id })
        meetup-data
        (>= (get-participant-count meetup-id) (get max-participants meetup-data))
        false
    )
)

;; Read-only Functions

;; Get meetup details (excludes exact location for privacy)
(define-read-only (get-meetup-details (meetup-id uint))
    (match (map-get? meetups { meetup-id: meetup-id })
        meetup-data
        (ok (merge meetup-data { exact-location: none })) ;; Don't expose exact location in public query
        ERR-MEETUP-NOT-FOUND
    )
)

;; Get meetup participants
(define-read-only (get-meetup-participants (meetup-id uint))
    (match (map-get? meetup-participant-list { meetup-id: meetup-id })
        participant-list (ok (get participants participant-list))
        (ok (list))
    )
)

;; Check if user is registered for meetup
(define-read-only (check-registration-status (meetup-id uint) (user principal))
    (match (map-get? meetup-participants { meetup-id: meetup-id, participant: user })
        participant-data (ok (get status participant-data))
        (err "Not registered")
    )
)

;; Get nearby meetups - in a real implementation, this would use location data
;; Here we simply return all active meetups
(define-read-only (get-nearby-meetups (user-location-hash (buff 32)) (radius uint))
    ;; This would normally filter by location proximity
    ;; For demonstration, we'd return all active meetups
    (ok (list))  ;; Simplified - would actually iterate through meetups
)

;; Get the exact meetup location (only available to confirmed participants)
(define-read-only (get-meetup-location (meetup-id uint))
    (let ((sender tx-sender))
        (match (map-get? meetup-participants { meetup-id: meetup-id, participant: sender })
            participant-data
            (if (or (is-eq (get status participant-data) "confirmed") 
                    (is-eq (get status participant-data) "attended"))
                (match (map-get? meetups { meetup-id: meetup-id })
                    meetup-data 
                    (ok (get exact-location meetup-data))
                    ERR-MEETUP-NOT-FOUND
                )
                (err "Location only available to confirmed participants")
            )
            ERR-NOT-PARTICIPANT
        )
    )
)

;; Public Functions

;; Create a new meetup
(define-public (create-meetup 
    (title (string-ascii 100))
    (description (string-utf8 500))
    (skill-offered (string-ascii 50))
    (location-hash (buff 32))
    (exact-location (string-utf8 200))
    (max-participants uint)
    (start-time uint)
    (end-time uint)
    (reputation-required uint)
)
    (let ((host tx-sender)
          (meetup-id (generate-meetup-id))
          (current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
        
        ;; Check that the host has sufficient reputation
        (asserts! (has-sufficient-host-reputation host) ERR-INSUFFICIENT-REPUTATION)
        
        ;; Validate input parameters
        (asserts! (> start-time current-time) ERR-INVALID-TIME)
        (asserts! (> end-time start-time) ERR-INVALID-TIME)
        (asserts! (> (len skill-offered) u0) ERR-INVALID-SKILL)
        
        ;; Create the meetup
        (map-set meetups
            { meetup-id: meetup-id }
            {
                host: host,
                title: title,
                description: description,
                skill-offered: skill-offered,
                location-hash: location-hash,
                location-revealed: false,
                exact-location: (some exact-location),
                max-participants: (if (> max-participants u0) max-participants DEFAULT-MAX-PARTICIPANTS),
                start-time: start-time,
                end-time: end-time,
                status: "pending",
                reputation-required: reputation-required,
                created-at: current-time
            }
        )
        
        ;; Auto-register the host as a participant
        (map-set meetup-participants
            { meetup-id: meetup-id, participant: host }
            {
                status: "confirmed",  ;; Host is automatically confirmed
                registration-time: current-time,
                confirmation-time: (some current-time),
                attendance-verified: false
            }
        )
        
        ;; Add host to participant list
        (add-participant-to-list meetup-id host)
        
        (ok meetup-id)
    )
)

;; Join a meetup
(define-public (join-meetup (meetup-id uint))
    (let ((participant tx-sender)
          (current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
        
        ;; Check meetup exists
        (asserts! (meetup-exists meetup-id) ERR-MEETUP-NOT-FOUND)
        
        ;; Check if user already registered
        (asserts! (not (is-participant meetup-id participant)) ERR-ALREADY-REGISTERED)
        
        ;; Check if meetup is full
        (asserts! (not (is-meetup-full meetup-id)) ERR-MEETUP-FULL)
        
        ;; Check participant reputation
        (asserts! (has-sufficient-join-reputation participant meetup-id) ERR-INSUFFICIENT-REPUTATION)
        
        ;; Register the participant
        (map-set meetup-participants
            { meetup-id: meetup-id, participant: participant }
            {
                status: "registered",
                registration-time: current-time,
                confirmation-time: none,
                attendance-verified: false
            }
        )
        
        ;; Add to participant list
        (add-participant-to-list meetup-id participant)
        
        (ok true)
    )
)

;; Confirm participation in a meetup
(define-public (confirm-participation (meetup-id uint))
    (let ((participant tx-sender)
          (current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
        
        ;; Check meetup exists
        (asserts! (meetup-exists meetup-id) ERR-MEETUP-NOT-FOUND)
        
        ;; Check if user is registered
        (asserts! (is-participant meetup-id participant) ERR-NOT-REGISTERED)
        
        ;; Get participant data
        (match (map-get? meetup-participants { meetup-id: meetup-id, participant: participant })
            participant-data
            ;; Check if already confirmed
            (begin
                (asserts! (is-eq (get status participant-data) "registered") ERR-ALREADY-CONFIRMED)
                
                ;; Update status to confirmed
                (map-set meetup-participants
                    { meetup-id: meetup-id, participant: participant }
                    {
                        status: "confirmed",
                        registration-time: (get registration-time participant-data),
                        confirmation-time: (some current-time),
                        attendance-verified: false
                    }
                )
                
                ;; If the participant is confirmed, they can now see the exact meetup location
                (ok true)
            )
            ERR-NOT-REGISTERED
        )
    )
)

;; Cancel registration for a meetup
(define-public (cancel-registration (meetup-id uint))
    (let ((participant tx-sender))
        
        ;; Check meetup exists
        (asserts! (meetup-exists meetup-id) ERR-MEETUP-NOT-FOUND)
        
        ;; Check if user is registered
        (asserts! (is-participant meetup-id participant) ERR-NOT-REGISTERED)
        
        ;; Can't cancel if you're the host
        (asserts! (not (is-meetup-host meetup-id participant)) (err "Host cannot cancel registration"))
        
        ;; Remove participant data
        (map-delete meetup-participants { meetup-id: meetup-id, participant: participant })
        
        ;; We should also remove from participant list, but this requires rebuilding the list
        ;; In a production contract, this would be implemented
        
        (ok true)
    )
)

;; Cancel a meetup (host only)
(define-public (cancel-meetup (meetup-id uint))
    (let ((sender tx-sender))
        
        ;; Check meetup exists
        (asserts! (meetup-exists meetup-id) ERR-MEETUP-NOT-FOUND)
        
        ;; Check if sender is the host
        (asserts! (is-meetup-host meetup-id sender) ERR-UNAUTHORIZED)
        
        ;; Update meetup status to cancelled
        (match (map-get? meetups { meetup-id: meetup-id })
            meetup-data
            (map-set meetups
                { meetup-id: meetup-id }
                (merge meetup-data { status: "cancelled" })
            )
            ERR-MEETUP-NOT-FOUND
        )
        
        (ok true)
    )
)

;; Start a meetup (host only)
(define-public (start-meetup (meetup-id uint))
    (let ((sender tx-sender)
          (current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
        
        ;; Check meetup exists
        (asserts! (meetup-exists meetup-id) ERR-MEETUP-NOT-FOUND)
        
        ;; Check if sender is the host
        (asserts! (is-meetup-host meetup-id sender) ERR-UNAUTHORIZED)
        
        ;; Get meetup data and update status
        (match (map-get? meetups { meetup-id: meetup-id })
            meetup-data
            (begin
                ;; Make sure meetup isn't already ended or cancelled
                (asserts! (not (is-eq (get status meetup-data) "completed")) ERR-MEETUP-ENDED)
                (asserts! (not (is-eq (get status meetup-data) "cancelled")) (err "Meetup is cancelled"))
                
                ;; Update status to active
                (map-set meetups
                    { meetup-id: meetup-id }
                    (merge meetup-data { 
                        status: "active",
                        location-revealed: true  ;; Reveal location to all confirmed participants
                    })
                )
                
                (ok true)
            )
            ERR-MEETUP-NOT-FOUND
        )
    )
)

;; Verify attendance of another participant
(define-public (verify-attendance (meetup-id uint) (attendee principal))
    (let ((confirmer tx-sender)
          (current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
        
        ;; Check meetup exists
        (asserts! (meetup-exists meetup-id) ERR-MEETUP-NOT-FOUND)
        
        ;; Check if meetup is active
        (match (map-get? meetups { meetup-id: meetup-id })
            meetup-data
            (asserts! (is-eq (get status meetup-data) "active") ERR-MEETUP-NOT-STARTED)
            ERR-MEETUP-NOT-FOUND
        )
        
        ;; Check if confirmer is a participant
        (asserts! (is-participant meetup-id confirmer) ERR-NOT-PARTICIPANT)
        
        ;; Check if attendee is a participant
        (asserts! (is-participant meetup-id attendee) ERR-NOT-PARTICIPANT)
        
        ;; Check that confirmer is not the attendee
        (asserts! (not (is-eq confirmer attendee)) (err "Cannot verify own attendance"))
        
        ;; Record the attendance confirmation
        (map-set attendance-confirmations
            { meetup-id: meetup-id, attendee: attendee, confirmer: confirmer }
            { confirmed: true, time: current-time }
        )
        
        ;; Count total confirmations for the attendee
        ;; In a real implementation, we would iterate through all participants and count confirmations
        ;; Since Clarity doesn't support loops, we're simplifying this check
        
        ;; Update attendance verification status if threshold is met
        ;; This simplified implementation assumes the threshold is met
        (match (map-get? meetup-participants { meetup-id: meetup-id, participant: attendee })
            participant-data
            (map-set meetup-participants
                { meetup-id: meetup-id, participant: attendee }
                (merge participant-data { 
                    status: "attended",
                    attendance-verified: true
                })
            )
            ERR-NOT-PARTICIPANT
        )
        
        (ok true)
    )
)

;; Complete a meetup (host only)
(define-public (complete-meetup (meetup-id uint))
    (let ((sender tx-sender)
          (current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
        
        ;; Check meetup exists
        (asserts! (meetup-exists meetup-id) ERR-MEETUP-NOT-FOUND)
        
        ;; Check if sender is the host
        (asserts! (is-meetup-host meetup-id sender) ERR-UNAUTHORIZED)
        
        ;; Get meetup data and update status
        (match (map-get? meetups { meetup-id: meetup-id })
            meetup-data
            (begin
                ;; Ensure meetup was active
                (asserts! (is-eq (get status meetup-data) "active") ERR-MEETUP-NOT-STARTED)
                
                ;; Update status to completed
                (map-set meetups
                    { meetup-id: meetup-id }
                    (merge meetup-data { status: "completed" })
                )
                
                ;; In a production contract, we would also handle reputation updates
                ;; and time-credit transfers here, or call into the main SkillTide contract
                
                (ok true)
            )
            ERR-MEETUP-NOT-FOUND
        )
    )
)