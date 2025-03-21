(define-map submitted-btc-txs (buff 128) uint)  ;; Map between accepted btc txs and swap ids

(define-read-only (get-output-segwit (tx (buff 4096)) (index uint))
  (let
    (
      (parsed-tx (contract-call? 'SP2PABAF9FTAJYNFZH93XENAJ8FVY99RRM50D2JG9.clarity-bitcoin-lib-v5 parse-wtx tx false))
    )
    (match parsed-tx
      result
      (let
        (
          (tx-data (unwrap-panic parsed-tx)) 
          (outs (get outs tx-data)) 
          (out (unwrap! (element-at? outs index) ERR_NATIVE_FAILURE))
          (scriptPubKey (get scriptPubKey out))
          (value (get value out)) 
        )
        (ok { scriptPubKey: scriptPubKey, value: value })
      )
      missing ERR_NATIVE_FAILURE
    )
  )
)

(define-read-only (parse-payload-segwit (tx (buff 4096)))
  (match (get-output-segwit tx u0)
    result
    (let
      (
        (script (get scriptPubKey result))
        (script-len (len script))
        ;; Length is dynamic - one or two bytes!
        (offset (if (is-eq (unwrap! (element-at? script u1) ERR_NATIVE_FAILURE) 0x4C) u3 u2)) 
        (payload (unwrap! (slice? script offset script-len) ERR_NATIVE_FAILURE))
      )
      (ok (from-consensus-buff? { i: uint, r: principal } payload))
    )
    not-found ERR_NATIVE_FAILURE
  )
)

(define-read-only (is-btc-receiver-match (scriptPubKey (buff 128)) (expected-receiver (buff 42)))
  (let ((script-len (len scriptPubKey)))
    (if (>= script-len u22)
      (let ((script-hash (unwrap! (slice? scriptPubKey (- script-len u20) script-len) (err ERR_NATIVE_FAILURE))))
        ;; Compare with the expected hash from btc-receiver
        (ok (is-eq script-hash expected-receiver))
      )
      (err ERR_NATIVE_FAILURE))
  )
)

(define-public (submit-swap-segwit
    (id uint)
    (height uint)
    (wtx (buff 4096))
    (header (buff 80))
    (tx-index uint)
    (tree-depth uint)
    (wproof (list 14 (buff 32)))
    (witness-merkle-root (buff 32))
    (witness-reserved-value (buff 32))
    (ctx (buff 1024))
    (cproof (list 14 (buff 32)))
    (fees <fees-trait>))
  (let ((swap (unwrap! (map-get? swaps id) ERR_INVALID_ID))
        (stx-receiver (unwrap! (get stx-receiver swap) ERR_NO_STX_RECEIVER))
        (btc-receiver (unwrap! (get btc-receiver swap) ERR_NO_BTC_RECEIVER))
        (sats (unwrap! (get sats swap) ERR_NOT_PRICED)))
      
      ;; Standard checks
      (asserts! (> burn-block-height (+ (get when swap) cooldown)) ERR_IN_COOLDOWN) 
      (asserts! (is-eq tx-sender stx-receiver) ERR_INVALID_STX_RECEIVER)
      (asserts! (not (get done swap)) ERR_ALREADY_DONE)
      (match (get expired-height swap)
              some-height (asserts! (< burn-block-height some-height) ERR_RESERVATION_EXPIRED)
              (asserts! false ERR_NOT_RESERVED))
      (asserts! (is-eq fees .zero) ERR_INVALID_FEE_CONTRACT)
      (try! (contract-call? fees pay-fees (get ustx swap)))
      
      ;; Verify transaction was mined
      (match (contract-call? 'SP2PABAF9FTAJYNFZH93XENAJ8FVY99RRM50D2JG9.clarity-bitcoin-lib-v5 was-segwit-tx-mined-compact
                height wtx header tx-index tree-depth wproof witness-merkle-root witness-reserved-value ctx cproof)
        result
          (begin
            ;; Verify the transaction hasn't been used before
            (asserts! (is-none (map-get? submitted-btc-txs result)) ERR_BTC_TX_ALREADY_USED)
            
            ;; Parse the payload (output 0) to get swap ID and receiver
            (match (parse-payload-segwit wtx)
              payload-result 
                (let ((payload (unwrap! payload-result ERR_NATIVE_FAILURE))
                      (parsed-id (get i payload))
                      (parsed-receiver (get r payload)))
                  
                  ;; Verify that the swap ID in the payload matches our swap ID
                  (asserts! (is-eq parsed-id id) ERR_TX_NOT_FOR_RECEIVER)
                  
                  ;; Verify that the STX receiver in the payload matches our expected STX receiver
                  (asserts! (is-eq parsed-receiver stx-receiver) ERR_INVALID_STX_RECEIVER)
                  
                  ;; Verify the BTC payment (output 1)
                  (match (get-output-segwit wtx u1)
                    output-result
                      (let ((output (unwrap! output-result ERR_NATIVE_FAILURE))
                            (value (get value output))
                            (scriptPubKey (get scriptPubKey output)))
                        
                        ;; Verify that amount is at least the required amount
                        (asserts! (>= value sats) ERR_TX_VALUE_TOO_SMALL)
                        
                        ;; Verify that the payment is sent to the expected BTC receiver
                        (asserts! (unwrap! (is-btc-receiver-match scriptPubKey btc-receiver) ERR_TX_NOT_FOR_RECEIVER) ERR_TX_NOT_FOR_RECEIVER)
                        
                        ;; Successfully complete the swap
                        (map-set swaps id (merge swap {done: true}))
                        (map-set submitted-btc-txs result id)
                        (as-contract (stx-transfer? (get ustx swap) tx-sender stx-receiver))
                      )
                    ERR_NATIVE_FAILURE)
                )
              ERR_NATIVE_FAILURE)
          )
        error (err (* error u1000))))