;; Customer Manager Contract
;; Manages customer profiles, delivery preferences, and notifications

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-CUSTOMER-NOT-FOUND (err u501))
(define-constant ERR-INVALID-PREFERENCE (err u502))
(define-constant ERR-INVALID-ADDRESS (err u503))
(define-constant ERR-NOTIFICATION-FAILED (err u504))

;; Data Variables
(define-data-var next-notification-id uint u1)
(define-data-var default-delivery-window uint u4) ;; 4 hours default

;; Data Maps
(define-map customers
  { customer: principal }
  {
    name: (string-ascii 100),
    phone: (string-ascii 20),
    email: (string-ascii 100),
    primary-address: (string-ascii 200),
    delivery-instructions: (string-ascii 300),
    preferred-time-start: uint, ;; hour of day
    preferred-time-end: uint, ;; hour of day
    notification-preferences: (string-ascii 100),
    total-deliveries: uint,
    average-rating: uint, ;; 1-5 scale * 10
    status: (string-ascii 20),
    created-at: uint
  }
)

(define-map delivery-addresses
  { customer: principal, address-id: uint }
  {
    address: (string-ascii 200),
    address-type: (string-ascii 50), ;; home, office, etc.
    latitude: int,
    longitude: int,
    special-instructions: (string-ascii 200),
    access-code: (optional (string-ascii 20)),
    is-default: bool,
    active: bool
  }
)

(define-map delivery-preferences
  { customer: principal }
  {
    preferred-delivery-window: uint, ;; hours
    allow-weekend-delivery: bool,
    require-signature: bool,
    leave-at-door: bool,
    notify-on-dispatch: bool,
    notify-on-arrival: bool,
    notify-on-delivery: bool,
    preferred-drone-type: (optional (string-ascii 50))
  }
)

(define-map notifications
  { notification-id: uint }
  {
    customer: principal,
    package-id: uint,
    notification-type: (string-ascii 50),
    message: (string-ascii 300),
    sent-at: uint,
    delivery-method: (string-ascii 20), ;; sms, email, push
    status: (string-ascii 20),
    read-at: (optional uint)
  }
)

(define-map customer-feedback
  { customer: principal, package-id: uint }
  {
    delivery-rating: uint, ;; 1-5
    service-rating: uint, ;; 1-5
    drone-performance: uint, ;; 1-5
    comments: (optional (string-ascii 500)),
    would-recommend: bool,
    submitted-at: uint
  }
)

;; Public Functions

;; Register new customer
(define-public (register-customer
  (name (string-ascii 100))
  (phone (string-ascii 20))
  (email (string-ascii 100))
  (primary-address (string-ascii 200)))
  (begin
    (asserts! (> (len name) u0) ERR-INVALID-PREFERENCE)
    (asserts! (> (len primary-address) u0) ERR-INVALID-ADDRESS)
    (ok (map-set customers
      { customer: tx-sender }
      {
        name: name,
        phone: phone,
        email: email,
        primary-address: primary-address,
        delivery-instructions: "",
        preferred-time-start: u9, ;; 9 AM
        preferred-time-end: u17, ;; 5 PM
        notification-preferences: "email,sms",
        total-deliveries: u0,
        average-rating: u50, ;; 5.0 * 10
        status: "active",
        created-at: block-height
      }
    ))
  )
)

;; Add delivery address
(define-public (add-delivery-address
  (address-id uint)
  (address (string-ascii 200))
  (address-type (string-ascii 50))
  (latitude int)
  (longitude int)
  (special-instructions (string-ascii 200))
  (access-code (optional (string-ascii 20)))
  (is-default bool))
  (begin
    (asserts! (is-some (map-get? customers { customer: tx-sender })) ERR-CUSTOMER-NOT-FOUND)
    (asserts! (> (len address) u0) ERR-INVALID-ADDRESS)
    (ok (map-set delivery-addresses
      { customer: tx-sender, address-id: address-id }
      {
        address: address,
        address-type: address-type,
        latitude: latitude,
        longitude: longitude,
        special-instructions: special-instructions,
        access-code: access-code,
        is-default: is-default,
        active: true
      }
    ))
  )
)

;; Update delivery preferences
(define-public (update-delivery-preferences
  (delivery-window uint)
  (allow-weekend bool)
  (require-signature bool)
  (leave-at-door bool)
  (notify-dispatch bool)
  (notify-arrival bool)
  (notify-delivery bool))
  (begin
    (asserts! (is-some (map-get? customers { customer: tx-sender })) ERR-CUSTOMER-NOT-FOUND)
    (asserts! (and (> delivery-window u0) (<= delivery-window u12)) ERR-INVALID-PREFERENCE)
    (ok (map-set delivery-preferences
      { customer: tx-sender }
      {
        preferred-delivery-window: delivery-window,
        allow-weekend-delivery: allow-weekend,
        require-signature: require-signature,
        leave-at-door: leave-at-door,
        notify-on-dispatch: notify-dispatch,
        notify-on-arrival: notify-arrival,
        notify-on-delivery: notify-delivery,
        preferred-drone-type: none
      }
    ))
  )
)

;; Send notification to customer
(define-public (send-notification
  (customer principal)
  (package-id uint)
  (notification-type (string-ascii 50))
  (message (string-ascii 300))
  (delivery-method (string-ascii 20)))
  (let ((notification-id (var-get next-notification-id)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? customers { customer: customer })) ERR-CUSTOMER-NOT-FOUND)
    (var-set next-notification-id (+ notification-id u1))
    (ok (map-set notifications
      { notification-id: notification-id }
      {
        customer: customer,
        package-id: package-id,
        notification-type: notification-type,
        message: message,
        sent-at: block-height,
        delivery-method: delivery-method,
        status: "sent",
        read-at: none
      }
    ))
  )
)

;; Mark notification as read
(define-public (mark-notification-read (notification-id uint))
  (let ((notification (unwrap! (map-get? notifications { notification-id: notification-id }) ERR-NOTIFICATION-FAILED)))
    (asserts! (is-eq (get customer notification) tx-sender) ERR-NOT-AUTHORIZED)
    (ok (map-set notifications
      { notification-id: notification-id }
      (merge notification { read-at: (some block-height) })
    ))
  )
)

;; Submit customer feedback
(define-public (submit-feedback
  (package-id uint)
  (delivery-rating uint)
  (service-rating uint)
  (drone-performance uint)
  (comments (optional (string-ascii 500)))
  (would-recommend bool))
  (begin
    (asserts! (is-some (map-get? customers { customer: tx-sender })) ERR-CUSTOMER-NOT-FOUND)
    (asserts! (and (>= delivery-rating u1) (<= delivery-rating u5)) ERR-INVALID-PREFERENCE)
    (asserts! (and (>= service-rating u1) (<= service-rating u5)) ERR-INVALID-PREFERENCE)
    (asserts! (and (>= drone-performance u1) (<= drone-performance u5)) ERR-INVALID-PREFERENCE)
    (ok (map-set customer-feedback
      { customer: tx-sender, package-id: package-id }
      {
        delivery-rating: delivery-rating,
        service-rating: service-rating,
        drone-performance: drone-performance,
        comments: comments,
        would-recommend: would-recommend,
        submitted-at: block-height
      }
    ))
  )
)

;; Update customer profile
(define-public (update-customer-profile
  (name (string-ascii 100))
  (phone (string-ascii 20))
  (email (string-ascii 100))
  (delivery-instructions (string-ascii 300)))
  (let ((customer (unwrap! (map-get? customers { customer: tx-sender }) ERR-CUSTOMER-NOT-FOUND)))
    (ok (map-set customers
      { customer: tx-sender }
      (merge customer {
        name: name,
        phone: phone,
        email: email,
        delivery-instructions: delivery-instructions
      })
    ))
  )
)

;; Update customer statistics (called by system)
(define-public (update-customer-stats (customer principal) (new-rating uint))
  (let ((customer-data (unwrap! (map-get? customers { customer: customer }) ERR-CUSTOMER-NOT-FOUND))
        (total-deliveries (get total-deliveries customer-data))
        (current-avg (get average-rating customer-data))
        (new-total (+ total-deliveries u1))
        (new-avg (/ (+ (* current-avg total-deliveries) (* new-rating u10)) new-total)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set customers
      { customer: customer }
      (merge customer-data {
        total-deliveries: new-total,
        average-rating: new-avg
      })
    ))
  )
)

;; Read-only functions

(define-read-only (get-customer (customer principal))
  (map-get? customers { customer: customer })
)

(define-read-only (get-delivery-address (customer principal) (address-id uint))
  (map-get? delivery-addresses { customer: customer, address-id: address-id })
)

(define-read-only (get-delivery-preferences (customer principal))
  (map-get? delivery-preferences { customer: customer })
)

(define-read-only (get-notification (notification-id uint))
  (map-get? notifications { notification-id: notification-id })
)

(define-read-only (get-customer-feedback (customer principal) (package-id uint))
  (map-get? customer-feedback { customer: customer, package-id: package-id })
)

(define-read-only (is-customer-registered (customer principal))
  (is-some (map-get? customers { customer: customer }))
)
