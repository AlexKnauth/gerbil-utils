(export #t)
;; Simple extensible vectors, byte-vectors, and bit-vectors
;; They double their size each time they need to grow,
;; or you can insist on controlling what size they grow to.

(import
  :gerbil/gambit/bits :gerbil/gambit/bytes :gerbil/gambit/exact
  :std/misc/bytes :std/srfi/43 :std/sugar
  ./number)

(defstruct evector (values fill-pointer) transparent: #t)
(def (evector<-vector v) (make-evector v (vector-length v)))
(def (evector<-list l) (evector<-vector (list->vector l)))
(def (new-evector length: l initial-value: (v (void)) fill-pointer: (p l))
  (make-evector (make-vector (max l p) v) p))
(def (evector-ref v i)
  ;;(assert! (< i (evector-fill-pointer v)))
  (vector-ref (evector-values v) i))
(def (evector-set! v i x)
  ;;(assert! (< i (evector-fill-pointer v)))
  (vector-set! (evector-values v) i x))
(def evector-ref-set! evector-set!)
(def (extend-evector! e ll initial-value: (iv #f))
  (def v (evector-values e))
  (when (> ll (vector-length v))
    (set! (evector-values e) (vector-copy v 0 ll iv))))
(def (evector-set-fill-pointer! e fp initial-value: (iv #f) extend: (extend #f))
  (def l (vector-length (evector-values e)))
  (let/cc return
    (when (> fp l)
      (unless (or (eq? extend #t) (and (exact-integer? extend) (< 0 extend)))
        (return #f))
      (extend-evector! e (if (eq? extend #t)
                           (arithmetic-shift 1 (max 4 (integer-length fp)))
                           (+ extend fp))
                       initial-value: iv))
    (set! (evector-fill-pointer e) fp)
    fp))
(def (evector-push! e x initial-value: (iv #f) extend: (extend #f))
  (def i (evector-fill-pointer e))
  (and (evector-set-fill-pointer! e (1+ i) initial-value: iv extend: extend)
       (begin
         (vector-set! (evector-values e) i x)
         i)))
(def (vector<-evector e)
  (vector-copy (evector-values e) 0 (evector-fill-pointer e)))

;;; Since we're dealing with recursively defined sequences,
;;; let's define utilities to memoize the start of such sequences.
(def (auto-evector cache: (cache (evector<-list '())) fun: fun)
  (lambda (n)
    (assert! (nat? n))
    (if (< n (evector-fill-pointer cache))
      (evector-ref cache n)
      (let (value (fun n))
        (evector-push! cache value extend: #t)
        value))))


(defstruct ebytes (bytes fill-pointer) transparent: #t)
(def (ebytes<-bytes b) (make-ebytes b (u8vector-length b)))
(def (ebytes<-string s) (ebytes<-bytes (string->bytes s)))
(def (new-ebytes length: l initial-value: (v 0) fill-pointer: (p l))
  (make-ebytes (make-bytes (max l p) v) p))
(def (ebytes-ref e i) (bytes-ref (ebytes-bytes e) i))
(def (ebytes-set! e i x) (bytes-set! (ebytes-bytes e) i x))
(def ebytes-ref-set! ebytes-set!)
(def (extend-ebytes! e ll initial-value: (iv 0))
  (def b (ebytes-bytes e))
  (when (> ll (u8vector-length b))
    (let (bb (make-bytes ll iv))
      (set! (ebytes-bytes e) bb)
      (subu8vector-move! b 0 (ebytes-fill-pointer e) bb 0))))
(def (ebytes-set-fill-pointer! e fp initial-value: (iv 0) extend: (extend #f))
  (def l (u8vector-length (ebytes-bytes e)))
  (let/cc return
    (when (> fp l)
      (unless (or (eq? extend #t) (and (exact-integer? extend) (< 0 extend)))
        (return #f))
      (extend-ebytes! e (if (eq? extend #t)
                         (arithmetic-shift 1 (max 4 (integer-length fp)))
                         (+ extend fp))
                     initial-value: iv))
    (set! (ebytes-fill-pointer e) fp)
    fp))
(def (ebytes-push! e x initial-value: (iv 0) extend: (extend #f))
  (def i (ebytes-fill-pointer e))
  (def bb (cond
           ((bytes? x) x)
           ((exact-integer? x) (make-bytes 1 x))
           ((string? x) (string->bytes x))))
  (def ll (u8vector-length bb))
  (and (ebytes-set-fill-pointer! e (+ i ll) initial-value: iv extend: extend)
       (begin
         (subu8vector-move! bb 0 ll (ebytes-bytes e) i)
         i)))
(def (bytes<-ebytes e)
  (subu8vector (ebytes-bytes e) 0 (ebytes-fill-pointer e)))

;; Bytes as extensible bit vectors in little-endian way
(defstruct ebits (bits fill-pointer) transparent: #t)
(def (ebits<-bits b l)
  (def ll (n-bytes<-n-bits l))
  (def bb (make-bytes ll 0))
  (u8vector-uint-set! bb 0 b little ll)
  (make-ebits bb l))
(def (new-ebits length: l initial-value: (b 0) fill-pointer: (p l))
  (make-ebits (make-bytes (n-bytes<-n-bits (max l p)) (if (zero? b) b 255)) p))
(def (ebits-set? e i)
  (bit-set? (bitwise-and i 7) (bytes-ref (ebits-bits e) (arithmetic-shift i -3))))
(def (ebits-ref e i) (if (ebits-set? e i) 1 0))
(def (ebits-set! e i x)
  (def ii (arithmetic-shift i -3))
  (def bit (arithmetic-shift 1 (bitwise-and i 7)))
  (def b (ebits-bits e))
  (def y (bytes-ref b ii))
  (bytes-set! b ii (if (zero? x) (bitwise-and y (bitwise-not bit)) (bitwise-ior y bit))))
(def ebits-ref-set! ebits-set!)
(def (extend-ebits! e ll initial-value: (iv 0))
  (def b (ebits-bits e))
  (def bl (n-bytes<-n-bits ll))
  (when (> bl (u8vector-length b))
    (let (bb (make-bytes bl (if (zero? iv) 0 255)))
      (set! (ebits-bits e) bb)
      (subu8vector-move! b 0 (n-bytes<-n-bits (ebits-fill-pointer e)) bb 0))))
(def (ebits-set-fill-pointer! e fp initial-value: (iv 0) extend: (extend #f))
  (def l (u8vector-length (ebits-bits e)))
  (def bl (n-bytes<-n-bits fp))
  (let/cc return
    (when (> bl l)
      (unless (or (eq? extend #t) (and (exact-integer? extend) (< 0 extend)))
        (return #f))
      (extend-ebits! e (if (eq? extend #t)
                         (arithmetic-shift 1 (max 6 (integer-length fp)))
                         (+ extend fp))
                     initial-value: iv))
    (set! (ebits-fill-pointer e) fp)
    fp))
(def (ebits-push! e x initial-value: (iv 0) extend: (extend #f))
  (def i (ebits-fill-pointer e))
  (and (ebits-set-fill-pointer! e (1+ i) initial-value: iv extend: extend)
       (begin
         (ebits-set! e i x)
         i)))
(def (bits<-ebits e)
  (def l (ebits-fill-pointer e))
  (values (clear-bit-field 8 l (u8vector-uint-ref (ebits-bits e) 0 little (n-bytes<-n-bits l))) l))