;;; $ wat2wasm ichigo.wat -o ichigo.wasm
;;;
;;; <LISP POINTER>
;;;
;;; Lisp pointer is a 4-byte pointer that contains an address or number with
;;; tags. The last 3 bits in Lisp pointers are used as tags:
;;;   [MSB]                      [LSB] (32 bit)
;;;   XXXXXXXXXXXXXXXXXXXXXXXXXXXXXNFG
;;;     N: whether it's a non-double-word-cell pointer
;;;     F: whether it's a fixnum
;;;     G: whether it's marked in GC
;;;
;;; Lisp pointers can represent 3 types of data using the tags:
;;;   ...X1G: fixnum (N bit is used as a part of a 30-bit integer)
;;;   ...00G: pointer to a double-word cell
;;;   ...10G: pointer to an other object
;;;
;;; Examples:
;;;    0: a pointer to a double-word cell located at 0 (NIL)
;;;    8: a pointer to a double-word cell located at 8 (PNAME)
;;;    2: a fixnum representing 0
;;;    6: a fixnum representing 1
;;;   -2: a fixnum representing -1
;;;
;;;
;;; <DOUBLE WORD CELL>
;;;
;;; Double-word cell is an 8-byte object that consists of 2 Lisp pointers. The
;;; former one is called CAR and the latter one is called CDR.
;;; Garbage collector marks the G bit only in the CAR part. The G bit in the
;;; CDR part is never used.
;;; The CAR part can contain special values to represent some types of objects
;;; such as symbols or errors. Double-word cells which don't contain the
;;; special values are called "cons cells".
;;;
;;; Special values:
;;;   -4 (1...11100): represents a symbol
;;;   -12 (1...10100): represents an error
;;;
;;; The special values are pseudo pointers that cannot be accessed.
;;;
;;;
;;; <Terminologies>
;;;
;;; name: list of fixnums representing packed characters like ("abc" "de\00")
;;; name1: a fixnum representing packed characters like "abc"

(module
 (func $log (import "console" "log") (param i32))
 (func $logstr (import "console" "logstr") (param i32))
 (func $printlnString (import "io" "printlnString") (param i32))
 (func $outputString (import "io" "outputString") (param i32))
 ;; page 0: any
 ;; page 1: free list
 ;; page 2: stack
 ;; page 3: expr/fexpr
 (import "js" "memory" (memory 4))
 (import "js" "table" (table 256 funcref))

 (type $subr_type (func (result i32)))
 (type $fsubr_type (func (result i32)))

 (global $mark_bit i32 (i32.const 1))
 (global $unmark_mask i32 (i32.const 0xfffffffe))

 (global $tag_symbol i32 (i32.const -4))
 (global $tag_error i32 (i32.const -12))

 ;; start address of the heap (inclusive)
 (global $heap_start (mut i32) (i32.const 65536))
 ;; points to the head of free list
 (global $fp (mut i32) (i32.const 65536))
 ;; fill pointer of heap
 (global $fillp (mut i32) (i32.const 0))
 ;; end address of the heap (exclusive)
 (global $heap_end (mut i32) (i32.const 131072))
 ;; address of stack bottom
 (global $stack_bottom (mut i32) (i32.const 131072))
 ;; stack pointer
 (global $sp (mut i32) (i32.const 131072))

 (global $boffo i32 (i32.const 10240))
 (global $boffop (mut i32) (i32.const 10240))
 (global $readp (mut i32) (i32.const 0))
 (global $printp (mut i32) (i32.const 0))

 (global $oblist (mut i32) (i32.const 0))

 ;;; Symbol strings [2000 - 4095]
 (data (i32.const 2000) "NIL\00")  ;; 4
 (global $str_nil i32 (i32.const 2000))
 (data (i32.const 2010) "PNAME\00")  ;; 6
 (global $str_pname i32 (i32.const 2010))
 (data (i32.const 2020) "APVAL\00")  ;; 6
 (global $str_apval i32 (i32.const 2020))
 (data (i32.const 2030) "F\00")  ;; 2
 (global $str_f i32 (i32.const 2030))
 (data (i32.const 2040) "T\00")  ;; 2
 (global $str_t i32 (i32.const 2040))
 (data (i32.const 2050) "*T*\00")  ;; 4
 (global $str_tstar i32 (i32.const 2050))
 (data (i32.const 2060) ".\00")  ;; 2
 (global $str_dot i32 (i32.const 2060))
 (data (i32.const 2070) "QUOTE\00")  ;; 6
 (global $str_quote i32 (i32.const 2070))
 (data (i32.const 2080) "+\00")  ;; 2
 (global $str_plus_sign i32 (i32.const 2080))
 (data (i32.const 2090) "SUBR\00")  ;; 5
 (global $str_subr i32 (i32.const 2090))
 (data (i32.const 2100) "FSUBR\00")  ;; 6
 (global $str_fsubr i32 (i32.const 2100))
 (data (i32.const 2110) "EXPR\00")  ;; 5
 (global $str_expr i32 (i32.const 2110))
 (data (i32.const 2120) "FEXPR\00")  ;; 6
 (global $str_fexpr i32 (i32.const 2120))
 (data (i32.const 2130) "CAR\00")  ;; 4
 (global $str_car i32 (i32.const 2130))
 (data (i32.const 2140) "CDR\00")  ;; 4
 (global $str_cdr i32 (i32.const 2140))
 (data (i32.const 2150) "CONS\00")  ;; 5
 (global $str_cons i32 (i32.const 2150))
 (data (i32.const 2160) "ATOM\00")  ;; 5
 (global $str_atom i32 (i32.const 2160))
 (data (i32.const 2170) "EQ\00")  ;; 3
 (global $str_eq i32 (i32.const 2170))
 (data (i32.const 2180) "EQUAL\00")  ;; 6
 (global $str_equal i32 (i32.const 2180))
 (data (i32.const 2190) "LIST\00")  ;; 5
 (global $str_list i32 (i32.const 2190))
 (data (i32.const 2200) "IF\00")  ;; 3
 (global $str_if i32 (i32.const 2200))
 (data (i32.const 2210) "LAMBDA\00")  ;; 7
 (global $str_lambda i32 (i32.const 2210))
 (data (i32.const 2220) "PUTPROP\00")  ;; 8
 (global $str_putprop i32 (i32.const 2220))
 (data (i32.const 2230) "RECLAIM\00")  ;; 8
 (global $str_reclaim i32 (i32.const 2230))
 (data (i32.const 2240) "PLUS\00")  ;; 5
 (global $str_plus i32 (i32.const 2240))
 (data (i32.const 2250) "PROG\00")  ;; 5
 (global $str_prog i32 (i32.const 2250))
 (data (i32.const 2260) "PRINT\00")  ;; 6
 (global $str_print i32 (i32.const 2260))
 (data (i32.const 2270) "PRIN1\00")  ;; 6
 (global $str_prin1 i32 (i32.const 2270))
 (data (i32.const 2280) "TERPRI\00")  ;; 7
 (global $str_terpri i32 (i32.const 2280))
 (data (i32.const 2290) "GO\00")  ;; 3
 (global $str_go i32 (i32.const 2290))
 (data (i32.const 2300) "RETURN\00")  ;; 7
 (global $str_return i32 (i32.const 2300))
 (data (i32.const 2310) "SET\00")  ;; 4
 (global $str_set i32 (i32.const 2310))
 (data (i32.const 2320) "SETQ\00")  ;; 5
 (global $str_setq i32 (i32.const 2320))
 (data (i32.const 2330) "PROG2\00")  ;; 6
 (global $str_prog2 i32 (i32.const 2330))
 (data (i32.const 2340) "-\00")  ;; 2
 (global $str_minus_sign i32 (i32.const 2340))
 (data (i32.const 2350) "MINUS\00")  ;; 6
 (global $str_minus i32 (i32.const 2350))
 (data (i32.const 2360) "DIFFERENCE\00")  ;; 11 !!!
 (global $str_difference i32 (i32.const 2360))
 (data (i32.const 2380) "*\00")  ;; 2
 (global $str_star_sign i32 (i32.const 2380))
 (data (i32.const 2390) "TIMES\00")  ;; 6
 (global $str_times i32 (i32.const 2390))
 (data (i32.const 2400) "/\00")  ;; 2
 (global $str_slash_sign i32 (i32.const 2400))
 (data (i32.const 2410) "DIVIDE\00")  ;; 7
 (global $str_divide i32 (i32.const 2410))
 (data (i32.const 2420) "QUOTIENT\00")  ;; 9
 (global $str_quotient i32 (i32.const 2420))
 (data (i32.const 2430) "REMAINDER\00")  ;; 10
 (global $str_remainder i32 (i32.const 2430))
 (data (i32.const 2440) "1+\00")  ;; 3
 (global $str_oneplus i32 (i32.const 2440))
 (data (i32.const 2450) "ADD1\00")  ;; 5
 (global $str_add1 i32 (i32.const 2450))
 (data (i32.const 2460) "1-\00")  ;; 3
 (global $str_oneminus i32 (i32.const 2460))
 (data (i32.const 2470) "SUB1\00")  ;; 5
 (global $str_sub1 i32 (i32.const 2470))
 (data (i32.const 2480) "<\00")  ;; 2
 (global $str_less_sign i32 (i32.const 2480))
 (data (i32.const 2490) "LESSP\00")  ;; 6
 (global $str_lessp i32 (i32.const 2490))
 (data (i32.const 2500) ">\00")  ;; 2
 (global $str_greater_sign i32 (i32.const 2500))
 (data (i32.const 2510) "GREATERP\00")  ;; 8
 (global $str_greaterp i32 (i32.const 2510))
 (data (i32.const 2520) "ZEROP\00")  ;; 6
 (global $str_zerop i32 (i32.const 2520))
 (data (i32.const 2530) "ONEP\00")  ;; 5
 (global $str_onep i32 (i32.const 2530))
 (data (i32.const 2540) "MINUSP\00")  ;; 7
 (global $str_minusp i32 (i32.const 2540))
 (data (i32.const 2550) "NUMBERP\00")  ;; 8
 (global $str_numberp i32 (i32.const 2550))

 ;;; Lisp Objects [0 - 1999 (0x7cf)]
 (global $sym_nil i32 (i32.const 0x000))
 (global $sym_pname i32 (i32.const 0x008))
 (global $sym_apval i32 (i32.const 0x010))
 (global $sym_f i32 (i32.const 0x018))
 (global $sym_t i32 (i32.const 0x020))
 (global $sym_tstar i32 (i32.const 0x028))
 (global $sym_dot i32 (i32.const 0x030))
 (global $sym_quote i32 (i32.const 0x038))
 (global $sym_plus i32 (i32.const 0x040))
 (global $sym_subr i32 (i32.const 0x048))
 (global $sym_fsubr i32 (i32.const 0x050))
 (global $sym_expr i32 (i32.const 0x058))
 (global $sym_fexpr i32 (i32.const 0x060))
 (global $sym_car i32 (i32.const 0x068))
 (global $sym_cdr i32 (i32.const 0x070))
 (global $sym_cons i32 (i32.const 0x078))
 (global $sym_atom i32 (i32.const 0x080))
 (global $sym_eq i32 (i32.const 0x088))
 (global $sym_equal i32 (i32.const 0x090))
 (global $sym_list i32 (i32.const 0x098))
 (global $sym_if i32 (i32.const 0x0a0))
 (global $sym_lambda i32 (i32.const 0x0a8))
 (global $sym_putprop i32 (i32.const 0x0b0))
 (global $sym_reclaim i32 (i32.const 0x0b8))
 (global $sym_plus_sign i32 (i32.const 0x0c0))
 (global $err_gc i32 (i32.const 0x0c8))
 (global $sym_prog i32 (i32.const 0x0d0))
 (global $sym_print i32 (i32.const 0x0d8))
 (global $sym_prin1 i32 (i32.const 0x0e0))
 (global $sym_terpri i32 (i32.const 0x0e8))
 (global $sym_go i32 (i32.const 0x0f0))
 (global $sym_return i32 (i32.const 0x0f8))
 (global $sym_set i32 (i32.const 0x0100))
 (global $sym_setq i32 (i32.const 0x0108))
 (global $sym_prog2 i32 (i32.const 0x0110))
 (global $sym_minus_sign i32 (i32.const 0x0118))
 (global $sym_minus i32 (i32.const 0x0120))
 (global $sym_difference i32 (i32.const 0x0128))
 (global $sym_star_sign i32 (i32.const 0x0130))
 (global $sym_times i32 (i32.const 0x0138))
 (global $sym_slash_sign i32 (i32.const 0x0140))
 (global $sym_divide i32 (i32.const 0x0148))
 (global $sym_quotient i32 (i32.const 0x0150))
 (global $sym_remainder i32 (i32.const 0x0158))
 (global $sym_oneplus i32 (i32.const 0x0160))
 (global $sym_add1 i32 (i32.const 0x0168))
 (global $sym_oneminus i32 (i32.const 0x0170))
 (global $sym_sub1 i32 (i32.const 0x0178))
 (global $sym_less_sign i32 (i32.const 0x0180))
 (global $sym_lessp i32 (i32.const 0x0188))
 (global $sym_greater_sign i32 (i32.const 0x0190))
 (global $sym_greaterp i32 (i32.const 0x0198))
 (global $sym_zerop i32 (i32.const 0x01a0))
 (global $sym_onep i32 (i32.const 0x01a8))
 (global $sym_minusp i32 (i32.const 0x01b0))
 (global $sym_numberp i32 (i32.const 0x01b8))
 (global $primitive_obj_end i32 (i32.const 0x1c0))

 ;;; Other Strings [5000 - 9999?]
 (data (i32.const 5000) "R4: EOF ON READ-IN\00")  ;; 19
 (global $str_err_eof i32 (i32.const 5000))
 (data (i32.const 5020) "R1: UNEXPECTED CHARACTER\00")  ;; 25
 (global $str_err_unexpected i32 (i32.const 5020))
 (data (i32.const 5050) "ERROR\00")  ;; 6
 (global $str_err_generic i32 (i32.const 5050))
 (data (i32.const 5060) "A8: UNBOUND VARIABLE\00")  ;; 21
 (global $str_err_unbound i32 (i32.const 5060))
 (data (i32.const 5090) "A2: NO FUNCTION DEFINITION\00")  ;; 27
 (global $str_err_nodef i32 (i32.const 5090))
 (data (i32.const 5120) "P1: PRINT NON-OBJECT\00")  ;; 21
 (global $str_err_print i32 (i32.const 5120))
 (data (i32.const 5150) "GC2: NOT ENOUGH WORDS\00")  ;; 22
 (global $str_err_gc i32 (i32.const 5150))
 (data (i32.const 5180) "GARBAGE COLLECTING...\00")  ;; 22
 (global $str_msg_gc1 i32 (i32.const 5180))
 (data (i32.const 5210) "MARKED: \00")  ;; 9
 (global $str_msg_gc2 i32 (i32.const 5210))
 (data (i32.const 5220) "RECLAIMED: \00")  ;; 12
 (global $str_msg_gc3 i32 (i32.const 5220))
 (data (i32.const 5240) "OBLIST: \00")  ;; 9
 (global $str_msg_gc4 i32 (i32.const 5240))
 (data (i32.const 5250) "A6: NO LABEL\00")  ;; 13
 (global $str_err_label i32 (i32.const 5250))
 (data (i32.const 5270) "I3: NOT NUMVAL\00")  ;; 15
 (global $str_err_num i32 (i32.const 5270))

 (func $push (param $val i32)
       (i32.store (global.get $sp) (local.get $val))
       (global.set $sp (i32.add (global.get $sp) (i32.const 4))))
 (func $pop (result i32)
      (global.set $sp (i32.sub (global.get $sp) (i32.const 4)))
      (i32.load (global.get $sp)))
 (func $drop (param i32))

 (func $int2fixnum (param $n i32) (result i32)
       (i32.add (i32.shl (local.get $n) (i32.const 2)) (i32.const 2)))
 (func $fixnum2int (param $n i32) (result i32)
       (i32.shr_s (local.get $n) (i32.const 2)))

 ;;; Returns whether obj is a fixnum
 (func $fixnump (param $obj i32) (result i32)
       (i32.eq (i32.and (local.get $obj) (i32.const 2))
               (i32.const 2)))

 ;;; Returns whether ojb points to a double word cell.
 (func $dwcellp (param $obj i32) (result i32)
       (i32.eqz (i32.and (local.get $obj) (i32.const 6))))

 ;;; Returns whether obj is an "other" pointer.
 (func $otherp (param $obj i32) (result i32)
       (i32.eq (i32.and (local.get $obj) (i32.const 6))
               (i32.const 4)))

 ;;; Returns whether obj is a pseudo pointer that has special meaning.
 (func $specialTagp (param $obj i32) (result i32)
       ;; Ignore GC bit
       (local.set $obj (i32.and (local.get $obj) (i32.const 0xfffffffe)))
       (if (i32.eq (local.get $obj) (global.get $tag_symbol))
           (return (i32.const 1)))
       (if (i32.eq (local.get $obj) (global.get $tag_error))
           (return (i32.const 1)))
       (i32.const 0))

 ;;; Returns whether obj points to a double word cell that contains symbol tag
 ;;; in CAR.
 (func $symbolp (param $obj i32) (result i32)
       (if (call $dwcellp (local.get $obj))
           (if (i32.eq (i32.and (call $car (local.get $obj))
                                (i32.const 0xfffffffe))
                       (global.get $tag_symbol))
               (return (i32.const 1))))
       (i32.const 0))

 ;;; Returns whether obj points to a double word cell that contains error tag
 ;;; in CAR.
 (func $errorp (param $obj i32) (result i32)
       (if (call $dwcellp (local.get $obj))
           (if (i32.eq (i32.and (call $car (local.get $obj))
                                (i32.const 0xfffffffe))
                       (global.get $tag_error))
               (return (i32.const 1))))
       (i32.const 0))

 ;;; Returns whether obj points to a double word cell that doesn't contain
 ;;; special tag in CAR.
 (func $consp (param $obj i32) (result i32)
       (if (call $dwcellp (local.get $obj))
           (if (i32.eqz (call $specialTagp (call $car (local.get $obj))))
               (return (i32.const 1))))
       (i32.const 0))

 (func $numberp (param $obj i32) (result i32)
       (call $fixnump (local.get $obj)))

 (func $car (param $cell i32) (result i32)
       (i32.load (local.get $cell)))
 (func $cdr (param $cell i32) (result i32)
       (i32.load (i32.add (local.get $cell) (i32.const 4))))
 (func $cadr (param $cell i32) (result i32)
       (call $car (call $cdr (local.get $cell))))
 (func $cddr (param $cell i32) (result i32)
       (call $cdr (call $cdr (local.get $cell))))
 (func $caddr (param $cell i32) (result i32)
       (call $car (call $cdr (call $cdr (local.get $cell)))))

 (func $safecar (param $obj i32) (result i32)
       (if (call $consp (local.get $obj))
           (return (call $car (local.get $obj))))
       (i32.const 0))
 (func $safecdr (param $obj i32) (result i32)
       (if (call $consp (local.get $obj))
           (return (call $cdr (local.get $obj))))
       (i32.const 0))

 (func $setcar (param $cell i32) (param $val i32)
       (i32.store (local.get $cell) (local.get $val)))
 (func $setcdr (param $cell i32) (param $val i32)
       (i32.store (i32.add (local.get $cell) (i32.const 4))
                  (local.get $val)))

 (global $linear_mode (mut i32) (i32.const 1))
 (func $rawcons (result i32)
       (local $ret i32)
       (local.set $ret (global.get $fp))
       (if (i32.ge_u (local.get $ret) (global.get $heap_end))
           (then
            (call $drop (call $garbageCollect))
            (if (i32.ge_u (local.get $ret) (global.get $heap_end))
                (then
                 (call $logstr (global.get $str_err_gc))
                 (return (global.get $err_gc))))))
       (if (global.get $linear_mode)
           (then
            (global.set $fp (i32.add (global.get $fp) (i32.const 8)))
            (global.set $fillp (global.get $fp)))
           (else
            (global.set $fp (call $cdr (global.get $fp)))
            (if (i32.eq (global.get $fp) (global.get $fillp))
                (global.set $linear_mode (i32.const 1)))))
       (local.get $ret))

 (func $cons (param $a i32) (param $d i32) (result i32)
      (local $cell i32)
      (local.set $cell (call $rawcons))
      (if (call $errorp (local.get $cell))
          (return (local.get $cell)))
      (call $setcar (local.get $cell) (local.get $a))
      (call $setcdr (local.get $cell) (local.get $d))
      (local.get $cell))

 ;;; Returns a fixnum representing a packed characters from a string.
 (func $makename1 (param $str i32) (result i32)
       (local $ret i32)
       ;; xxcccccc => cccccc02
       (local.set
        $ret
        (i32.add
         (i32.shl
          (i32.and (i32.load (local.get $str)) (i32.const 0x00ffffff))
          (i32.const 8))
         (i32.const 2)))
       ;; xxxx0002 => 00000002
       (if (i32.eqz (i32.and (local.get $ret) (i32.const 0x0000ff00)))
           (local.set $ret (i32.const 2)))
       ;; xx00cc02 => 0000cc02
       (if (i32.eqz (i32.and (local.get $ret) (i32.const 0x00ff0000)))
           (local.set $ret (i32.and (local.get $ret) (i32.const 0x0000ffff))))
       (local.get $ret))

 ;;; Returns the numnber of characers in a packed characters.
 (func $name1Size (param $n1 i32) (result i32)
      (local $ret i32)
      (if (i32.eqz (i32.and (local.get $n1) (i32.const 0x0000ff00)))
          (then (local.set $ret (i32.const 0)))
          (else
           (if (i32.eqz (i32.and (local.get $n1) (i32.const 0x00ff0000)))
               (then (local.set $ret (i32.const 1)))
               (else
                (if (i32.eqz (i32.and (local.get $n1) (i32.const 0xff000000)))
                    (local.set $ret (i32.const 2))
                    (local.set $ret (i32.const 3)))))))
      (local.get $ret))

 ;;; Returns a list of fixnums representing packed characters.
 (func $makename (param $str i32) (result i32)
       (local $ret i32)
       (local $size i32)
       (local $cell i32)
       (local $cur i32)
       (local $name1 i32)
       (local.set $ret (i32.const 0))
       ;; TODO: rewrite this using nreverse.
       (loop $loop
          (local.set $name1 (call $makename1 (local.get $str)))
          (local.set $size (call $name1Size (local.get $name1)))
          (if (i32.gt_s (local.get $size) (i32.const 0))
              (then
               (local.set
                $cell
                (call $cons (local.get $name1) (i32.const 0)))
               (if (i32.eqz (local.get $ret))
                   (then
                    (call $push (local.get $cell))  ;; For GC
                    (local.set $ret (local.get $cell)))
                   (else
                    (call $setcdr (local.get $cur) (local.get $cell))))
               (local.set $cur (local.get $cell))))
          (local.set $str (i32.add (local.get $str) (i32.const 3)))
          (br_if $loop (i32.eq (local.get $size) (i32.const 3))))
       (if (i32.ne (local.get $ret) (i32.const 0))
           (call $drop (call $pop)))  ;; For GC
       (local.get $ret))

 ;;; Outputs a fixnum representing a packed characters to `printp`.
 ;;; This function can output redundant '\00'
 (func $printName1 (param $n i32)
       (i32.store8
        (global.get $printp)
        (i32.and (i32.shr_u (local.get $n) (i32.const 8))
                 (i32.const 0x000000ff)))
       (i32.store8
        (i32.add (global.get $printp) (i32.const 1))
        (i32.and (i32.shr_u (local.get $n) (i32.const 16))
                 (i32.const 0x000000ff)))
       (i32.store8
        (i32.add (global.get $printp) (i32.const 2))
        (i32.and (i32.shr_u (local.get $n) (i32.const 24))
                 (i32.const 0x000000ff)))
       (i32.store8 (i32.add (global.get $printp) (i32.const 3))
                   (i32.const 0)))

 ;;; Outputs a list of packed characters to `printp`.
 (func $printName (param $cell i32)
       (local $name1 i32)
       (loop $loop
          (local.set $name1 (call $car (local.get $cell)))
          (call $printName1 (local.get $name1))
          (local.set $cell (call $cdr (local.get $cell)))
          (global.set
           $printp
           (i32.add (global.get $printp) (call $name1Size (local.get $name1))))
          (br_if $loop (i32.ne (local.get $cell) (i32.const 0)))))

 ;;; Outputs a symbol name to `printp`.
 ;;; `printp` should point to '\00'.
 (func $printSymbol (param $sym i32)
       (call $printName
             (call $get (local.get $sym) (global.get $sym_pname))))

 ;;; Writes a 1-byte character to the address pointed by `printp` and
 ;;; increments `printp`. Also concatenates '\00'.
 (func $printChar (param $c i32)
       (i32.store8 (global.get $printp) (local.get $c))
       (global.set $printp (i32.add (global.get $printp) (i32.const 1)))
       (i32.store8 (global.get $printp) (i32.const 0)))

 (func $printComment
       (call $printChar (i32.const 59))  ;; ';'
       (call $printChar (i32.const 32)))  ;; ' '

 (func $terpri
       (call $printChar (i32.const 10)))  ;; '\n'
 (func $terprif
       (call $terpri)
       (call $fflush))

 (func $printString (param $str i32)
       (local $c i32)
       (block $block
         (loop $loop
            (local.set $c (i32.load8_u (local.get $str)))
            ;; Note: this intentionally copies '\00'
            (i32.store8 (global.get $printp) (local.get $c))
            (br_if $block (i32.eqz (local.get $c)))
            (global.set $printp (i32.add (global.get $printp) (i32.const 1)))
            (local.set $str (i32.add (local.get $str) (i32.const 1)))
            (br $loop))))

 (func $printError (param $err i32)
       (call $printChar (i32.const 60))  ;; '<'
       (if (call $fixnump (call $cdr (local.get $err)))
           (call $printString (call $fixnum2int (call $cdr (local.get $err))))
           (call $printString (global.get $str_err_generic)))
       (call $printChar (i32.const 62)))  ;; '>'

 ;;; Output a string representation of a fixnum to `printp`.
 ;;; `printp` should point to '\00'.
 (func $printFixnum (param $n i32)
       (local $m i32)
       (local $size i32)
       (local.set $n (call $fixnum2int (local.get $n)))
       (if (i32.lt_s (local.get $n) (i32.const 0))
           (then
            (call $printChar (i32.const 45))  ;; '-'
            (local.set $n (i32.mul (local.get $n) (i32.const -1)))))
       (local.set $m (local.get $n))
       (local.set $size (i32.const 0))
       (loop $size_loop
          (local.set $size (i32.add (local.get $size) (i32.const 1)))
          (local.set $m (i32.div_u (local.get $m) (i32.const 10)))
          (br_if $size_loop (i32.gt_s (local.get $m) (i32.const 0))))
       (local.set $m (i32.const 1))
       (loop $fill_loop
          (i32.store8 (i32.add (global.get $printp)
                               (i32.sub (local.get $size) (local.get $m)))
                      (i32.add
                       (i32.const 48)  ;; '0'
                       (i32.rem_s (local.get $n) (i32.const 10))))
          (local.set $m (i32.add (local.get $m) (i32.const 1)))
          (local.set $n (i32.div_u (local.get $n) (i32.const 10)))
          (br_if $fill_loop (i32.gt_s (local.get $n) (i32.const 0))))
       (global.set $printp (i32.add (global.get $printp) (local.get $size)))
       (i32.store8 (global.get $printp) (i32.const 0)))

 (func $prop (param $obj i32) (param $key i32) (result i32)
       (local.set $obj (call $cdr (local.get $obj)))
       (loop $loop
          (if (i32.eq (call $car (local.get $obj)) (local.get $key))
              (return (call $cdr (local.get $obj))))
          (local.set $obj (call $cdr (call $cdr (local.get $obj))))
          (br_if $loop (i32.ne (local.get $obj) (i32.const 0))))
       (i32.const 0))

 (func $get (param $obj i32) (param $key i32) (result i32)
       (local $p i32)
       (if (i32.eqz (call $symbolp (local.get $obj)))
           (return (i32.const 0)))
       (local.set $p (call $prop (local.get $obj) (local.get $key)))
       (if (i32.eqz (local.get $p))
           (return (i32.const 0)))
       (call $car (local.get $p)))

 (func $putprop (param $obj i32) (param $val i32) (param $key i32)
       (local $p i32)
       (local.set $p (call $prop (local.get $obj) (local.get $key)))
       (if (i32.eqz (local.get $p))
           (then
            (local.set $p
                       (call $cons (i32.const 0) (call $cdr (local.get $obj))))
            (call $push (local.get $p))  ;; For GC
            (call $setcdr
                  (local.get $obj)
                  (call $cons (local.get $key) (local.get $p)))
            (call $drop (call $pop))))  ;; For GC
       (call $setcar (local.get $p) (local.get $val)))

 (func $nreverse (param $lst i32) (result i32)
       (local $ret i32)
       (local $tmp i32)
       (local.set $ret (i32.const 0))
       (block $block
         (loop $loop
            (br_if $block (i32.eqz (call $consp (local.get $lst))))
            (local.set $tmp (call $cdr (local.get $lst)))
            (call $setcdr (local.get $lst) (local.get $ret))
            (local.set $ret (local.get $lst))
            (local.set $lst (local.get $tmp))
            (br $loop)))
       (local.get $ret))

 (func $nconc (param $lst i32) (param $elm i32) (result i32)
       (local $ret i32)
       (local.set $ret (local.get $lst))
       (if (call $consp (local.get $lst))
           (loop $loop
              (if (call $consp (call $cdr (local.get $lst)))
                  (then
                   (local.set $lst (call $cdr (local.get $lst)))
                   (br $loop)))))
       (if (call $consp (local.get $lst))
           (call $setcdr (local.get $lst) (local.get $elm)))
       (local.get $ret))

 (func $assoc (param $key i32) (param $alist i32) (result i32)
       (block $block
         (loop $loop
            (br_if $block (i32.eqz (call $consp (local.get $alist))))
            (if (i32.eq (call $car (call $car (local.get $alist)))
                        (local.get $key))
                (return (call $car (local.get $alist))))
            (local.set $alist (call $cdr (local.get $alist)))
            (br $loop)))
       (i32.const 0))

 (func $length (param $obj i32) (result i32)
       (local $len i32)
       (local.set $len (i32.const 0))
       (loop $loop
          (if (i32.eqz (call $consp (local.get $obj)))
              (return (local.get $len)))
          (local.set $len (i32.add (local.get $len) (i32.const 1)))
          (local.set $obj (call $cdr (local.get $obj)))
          (br $loop))
       (i32.const 0))  ;; unreachable

 (func $member (param $obj i32) (param $lst i32) (result i32)
       (loop $loop
          (if (i32.eqz (call $consp (local.get $lst)))
              (return (i32.const 0)))
          (if (i32.eq (call $car (local.get $lst)) (local.get $obj))
              (return (local.get $lst)))
          (local.set $lst (call $cdr (local.get $lst)))
          (br $loop))
       (i32.const 0))

 (func $list2 (param $e1 i32) (param $e2 i32) (result i32)
       (local $tmp i32)
       (local.set $tmp (call $cons (local.get $e2) (i32.const 0)))
       (call $push (local.get $tmp))  ;; For GC (tmp)
       (local.set $tmp (call $cons (local.get $e1) (local.get $tmp)))
       (call $drop (call $pop))  ;; For GC ()
       (local.get $tmp))

 (func $simpleSymbolp (param $obj i32) (result i32)
       (if (i32.eqz (call $symbolp (local.get $obj)))
           (return (i32.const 0)))
       ;; Simple symbol should be (mark PNAME name)
       (if (i32.ne (call $length (call $cdr (local.get $obj))) (i32.const 2))
           (return (i32.const 0)))
       (i32.eq (call $cadr (local.get $obj)) (global.get $sym_pname)))

 (func $printList (param $obj i32)
       (local $first i32)
       (local.set $first (i32.const 1))
       (call $printChar (i32.const 40))  ;; LPar
       (block $block
         (loop $loop
            (br_if $block (i32.eqz (call $consp (local.get $obj))))
            (if (local.get $first)
                (local.set $first (i32.const 0))
                (call $printChar (i32.const 32)))  ;; ' '
            (call $printObj (call $car (local.get $obj)))
            (local.set $obj (call $cdr (local.get $obj)))
            (br $loop)))
       (if (i32.ne (local.get $obj) (i32.const 0))
           (then
            (call $printChar (i32.const 32))  ;; ' '
            (call $printChar (i32.const 46))  ;; '.'
            (call $printChar (i32.const 32))  ;; ' '
            (call $printObj (local.get $obj))))
       (call $printChar (i32.const 41))  ;; RPar
       (i32.store8 (global.get $printp) (i32.const 0)))

 (func $printObj (param $obj i32)
       (if (call $specialTagp (local.get $obj))
           (local.set $obj (call $makeStrError (global.get $str_err_print))))
       (if (call $errorp (local.get $obj))
           (then
            (call $printError (local.get $obj))
            (return)))
       (if (call $symbolp (local.get $obj))
           (then
            (call $printSymbol (local.get $obj))
            (return)))
       (if (call $fixnump (local.get $obj))
           (then
            (call $printFixnum (local.get $obj))
            (return)))
       (if (call $consp (local.get $obj))
           (then
            (call $printList (local.get $obj))
            (return)))
       )

 (func $pnameeq (param $cell i32) (param $str i32) (result i32)
       (local $key1 i32)
       (local $key2 i32)
       (local $ret i32)
       (local.set $ret (i32.const 1))
       (block $block
         (loop $loop
            (local.set $key1 (call $car (local.get $cell)))
            (local.set $key2 (call $makename1 (local.get $str)))
            ;; Return false if first 3 characters are different
            (if (i32.ne (local.get $key1) (local.get $key2))
                (then
                 (local.set $ret (i32.const 0))
                 (br $block)))
            ;; Returns true if first 3 characters contain '\00'
            (if (i32.eqz (i32.and (local.get $key1) (i32.const 0xff000000)))
                (br $block))
            (local.set $str (i32.add (local.get $str) (i32.const 3)))
            (local.set $cell (call $cdr (local.get $cell)))
            ;; Returns if pname is NIL
            (if (i32.eqz (local.get $cell))
                (then
                 (if (i32.ne (i32.and (i32.load (local.get $str))
                                      (i32.const 0x000000ff))
                             (i32.const 0))
                     (local.set $ret (i32.const 0)))
                 (br $block)))
            ;; Check next 3 characters
            (br $loop)))
       (local.get $ret))

 ;; Makes a new symbol from BOFFO
 (func $makeNewSym (result i32)
       (local $sym i32)
       (local $cell i32)
       (local.set $sym (call $cons (global.get $tag_symbol) (i32.const 0)))
       (call $push (local.get $sym))  ;; For GC
       (local.set $cell (call $makename (global.get $boffo)))
       (call $setcdr (local.get $sym) (local.get $cell))  ;; For GC
       (local.set $cell (call $cons (local.get $cell) (i32.const 0)))
       (call $setcdr (local.get $sym) (local.get $cell))  ;; For GC
       (local.set $cell (call $cons (global.get $sym_pname) (local.get $cell)))
       (call $setcdr (local.get $sym) (local.get $cell))
       (call $drop (call $pop))  ;; For GC
       (call $pushToOblist (local.get $sym))
       (local.get $sym))

 ;; Returns an existing symbol or makes a symbol from BOFFO.
 (func $makeSym (result i32)
       (local $cell i32)
       (local $sym i32)
       (local.set $cell (global.get $oblist))
       (block $block
         (loop $loop
            (local.set $sym (call $car (local.get $cell)))
            (if (call $pnameeq
                      (call $get (local.get $sym) (global.get $sym_pname))
                      (global.get $boffo))
                (br $block))
            (local.set $cell (call $cdr (local.get $cell)))
            (br_if $loop (i32.ne (local.get $cell) (i32.const 0)))))
       (if (i32.eqz (local.get $cell))
           (local.set $sym (call $makeNewSym)))
       (local.get $sym))

 (func $makeNum (param $n i32) (result i32)
       (call $int2fixnum (local.get $n)))

 ;;; Makes a number of symbol from BOFFO.
 (func $makeNumOrSym (result i32)
       (local $c i32)
       (local $sign i32)
       (local $is_num i32)
       (local $num i32)
       (local $ret i32)
       (global.set $boffop (global.get $boffo))
       (local.set $sign (i32.const 1))
       (local.set $is_num (i32.const 0))
       (local.set $num (i32.const 0))
       (local.set $c (i32.load8_u (global.get $boffop)))
       (if (i32.eq (local.get $c) (i32.const 45))
           (then
            (local.set $sign (i32.const -1))
            (global.set $boffop (i32.add (global.get $boffop) (i32.const 1)))
            (local.set $c (i32.load8_u (global.get $boffop)))))
       (block $block
         (loop $loop
            (br_if $block (i32.eqz (local.get $c)))
            (if (i32.and  ;; '0' <= c && c <= '9'
                 (i32.le_u (i32.const 48) (local.get $c))
                 (i32.le_u (local.get $c) (i32.const 57)))
                (then
                 (local.set $is_num (i32.const 1))
                 (local.set $num
                            (i32.add (i32.mul (local.get $num) (i32.const 10))
                                     (i32.sub (local.get $c) (i32.const 48)))))
                (else
                 (local.set $is_num (i32.const 0))
                 (br $block)))
            (global.set $boffop (i32.add (global.get $boffop) (i32.const 1)))
            (local.set $c (i32.load8_u (global.get $boffop)))
            (br $loop)))
       (global.set $boffop (global.get $boffo))
       (if (local.get $is_num)
           (local.set
            $ret
            (call $makeNum (i32.mul (local.get $num) (local.get $sign))))
           (local.set $ret (call $makeSym)))
       (local.get $ret))

 (func $makeStrError (param $str i32) (result i32)
       (call $cons
             (global.get $tag_error)
             (call $int2fixnum (local.get $str))))

 (func $embedStrError (param $obj i32) (param $str i32)
       (call $setcar (local.get $obj) (global.get $tag_error))
       (call $setcdr (local.get $obj) (call $int2fixnum (local.get $str))))

 (global $ce_go i32 (i32.const 1))
 (global $ce_return i32 (i32.const 2))
 ;; Returns (err n . args)
 (func $makeCatchableError (param $n i32) (param $args i32) (result i32)
       (local $ret i32)
       (local.set
        $ret (call $cons (call $int2fixnum (local.get $n)) (local.get $args)))
       (call $push (local.get $ret))  ;; For GC (ret)
       (local.set $ret (call $cons (global.get $tag_error) (local.get $ret)))
       (call $drop (call $pop))  ;; For GC ()
       (local.get $ret))
 (func $catchablep (param $obj i32) (param $n i32) (result i32)
       (if (call $errorp (local.get $obj))
           (if (call $consp (call $cdr (local.get $obj)))
               (return (i32.eq (call $cadr (local.get $obj))
                               (call $int2fixnum (local.get $n))))))
       (i32.const 0))
 (func $getCEValue (param $obj i32) (result i32)
       (call $cddr (local.get $obj)))

 ;;; Skips spaces in `readp`.
 (func $isSpace (param $c i32) (result i32)
       (local $ret i32)
       (local.set $ret (i32.const 0))
       (if (i32.eq (local.get $c) (i32.const 9))  ;; '\t'
           (local.set $ret (i32.const 1)))
       (if (i32.eq (local.get $c) (i32.const 10))  ;; '\n'
           (local.set $ret (i32.const 1)))
       (if (i32.eq (local.get $c) (i32.const 13))  ;; '\r'
           (local.set $ret (i32.const 1)))
       (if (i32.eq (local.get $c) (i32.const 32))  ;; ' '
           (local.set $ret (i32.const 1)))
       (local.get $ret))

 (func $isDelimiter (param $c i32) (result i32)
       (local $ret i32)
       (local.set $ret (i32.const 0))
       (if (i32.eq (local.get $c) (i32.const 39))  ;; Quote
           (local.set $ret (i32.const 1)))
       (if (i32.eq (local.get $c) (i32.const 40))  ;; LPar
           (local.set $ret (i32.const 1)))
       (if (i32.eq (local.get $c) (i32.const 41))  ;; RPar
           (local.set $ret (i32.const 1)))
       (if (call $isSpace (local.get $c))
           (local.set $ret (i32.const 1)))
       (local.get $ret))

 (func $skipSpaces
       (local $c i32)
       (loop $loop
          (local.set $c (i32.load8_u (global.get $readp)))
          (if (i32.eqz (local.get $c))
              (return))
          (if (call $isSpace (local.get $c))
              (then
               (global.set $readp (i32.add (global.get $readp) (i32.const 1)))
               (br $loop)))))

 (func $toUpper (param $c i32) (result i32)
       (if (i32.and (i32.le_u (i32.const 94) (local.get $c))
                    (i32.le_u (local.get $c) (i32.const 122)))
           (local.set $c (i32.sub (local.get $c) (i32.const 32))))
       (local.get $c))

 (func $readAtom (result i32)
       (local $c i32)
       (global.set $boffop (global.get $boffo))  ;; Reset BOFFO
       (block $block
          (loop $loop
             (local.set $c (i32.load8_u (global.get $readp)))
             (if (i32.eqz (local.get $c))
                 (br $block))
             (if (call $isDelimiter (local.get $c))
                 (br $block))
             (local.set $c (call $toUpper (local.get $c)))
             (i32.store8 (global.get $boffop) (local.get $c))
             (global.set $boffop (i32.add (global.get $boffop) (i32.const 1)))
             (global.set $readp (i32.add (global.get $readp) (i32.const 1)))
             (br $loop)))
       (i32.store8 (global.get $boffop) (i32.const 0))
       (call $makeNumOrSym))

 (func $readList (result i32)
       (local $c i32)
       (local $ret i32)
       (local $elm i32)
       (local.set $ret (i32.const 0))
       (local.set $elm (i32.const 0))
       (block $block
         (loop $loop
            (call $skipSpaces)
            (local.set $c (i32.load8_u (global.get $readp)))
            (if (i32.eqz (local.get $c))  ;; Empty
                (then
                 (local.set
                  $ret
                  (call $makeStrError (global.get $str_err_eof)))
                 (br $block)))
            (if (i32.eq (local.get $c) (i32.const 41))  ;; RPar
                (br $block))
            (call $push (local.get $ret))  ;; For GC (ret)
            (local.set $elm (call $read))
            (if (call $errorp (local.get $elm))  ;; Error on reading elm
                (then (local.set $ret (local.get $elm))
                      (call $drop (call $pop))  ;; For GC ()
                      (br $block)))
            ;; Special read for dotted list
            (if (i32.eq (local.get $elm) (global.get $sym_dot))
                (then
                 (call $skipSpaces)
                 (local.set $c (i32.load8_u (global.get $readp)))
                 (if (i32.eq (local.get $c) (i32.const 41))  ;; RPar after dot
                     (then
                      (call $drop (call $pop))  ;; For GC ()
                      (local.set
                       $ret
                       (call $makeStrError (global.get $str_err_unexpected)))
                      (br $block)))
                 (local.set $elm (call $read))
                 (call $drop (call $pop))  ;; For GC ()
                 (if (call $errorp (local.get $elm))  ;; Error on reading elm
                     (then (local.set $ret (local.get $elm))
                           (br $block)))
                 (call $skipSpaces)
                 (local.set $c (i32.load8_u (global.get $readp)))
                 (if (i32.ne (local.get $c) (i32.const 41))  ;; Not RPar
                     (then
                      (local.set
                       $ret
                       (call $makeStrError (global.get $str_err_unexpected)))
                      (br $block)))
                 (br $block)))  ;; valid dotted list
            ;; Proper list
            (call $push (local.get $elm))  ;; For GC (ret elm)
            (local.set $ret (call $cons (local.get $elm) (local.get $ret)))
            (local.set $elm (i32.const 0))
            (call $drop (call $pop))  ;; For GC (ret)
            (call $drop (call $pop))  ;; For GC ()
            (br $loop)))
       (if (call $errorp (local.get $ret))
           (return (local.get $ret)))
       (global.set $readp (i32.add (global.get $readp) (i32.const 1)))
       (local.set $ret (call $nreverse (local.get $ret)))
       (if (i32.ne (local.get $elm) (i32.const 0))  ;; dotted list
           (local.set $ret (call $nconc (local.get $ret) (local.get $elm))))
       (local.get $ret))

 ;;; Reads an expression from `readp`.
 (func $read (result i32)
       (local $c i32)
       (local $ret i32)
       (call $skipSpaces)
       (local.set $c (i32.load8_u (global.get $readp)))
       (block $block
         (if (i32.eqz (local.get $c))  ;; Empty
             (then
              (local.set $ret (call $makeStrError (global.get $str_err_eof)))
              (br $block)))
         (if (i32.eq (local.get $c) (i32.const 41))  ;; RPar
             (then (local.set
                    $ret
                    (call $makeStrError (global.get $str_err_unexpected)))
                   (br $block)))
         (if (i32.eq (local.get $c) (i32.const 40))  ;; LPar
             (then
              (global.set $readp (i32.add (global.get $readp) (i32.const 1)))
              (local.set $ret (call $readList))
              (br $block)))
         (if (i32.eq (local.get $c) (i32.const 39))  ;; Quote
             (then
              (global.set $readp (i32.add (global.get $readp) (i32.const 1)))
              (local.set $ret (call $read))
              (if (call $errorp (local.get $ret))
                  (br $block))
              (call $push (local.get $ret))  ;; For GC
              (local.set $ret (call $cons (local.get $ret) (i32.const 0)))
              (call $drop (call $pop)) (call $push (local.get $ret))  ;; For GC
              (local.set $ret (call $cons
                                    (global.get $sym_quote)
                                    (local.get $ret)))
              (call $drop (call $pop))  ;; For GC
              (br $block)))
         (local.set $ret (call $readAtom)))
       (local.get $ret))

 (func $pushToOblist (param $sym i32)
       (global.set $oblist (call $cons (local.get $sym) (global.get $oblist))))

 ;;; `lst` and `a` must be protected from GC
 (func $evlis (param $lst i32) (param $a i32) (result i32)
       (local $ret i32)
       (local $elm i32)
       (local.set $ret (i32.const 0))
       (block $block
         (loop $loop
            (br_if $block (i32.eqz (call $consp (local.get $lst))))
            (call $push (local.get $ret))  ;; For GC (ret)
            (local.set
             $elm
             (call $eval (call $car (local.get $lst)) (local.get $a)))
            (if (call $errorp (local.get $elm))
                (then
                 (call $drop (call $pop))  ;; For GC ()
                 (return (local.get $elm))))
            (call $push (local.get $elm))  ;; For GC (ret elm)
            (local.set $ret (call $cons (local.get $elm) (local.get $ret)))
            (call $drop (call $pop))  ;; For GC (ret)
            (call $drop (call $pop))  ;; For GC ()
            (local.set $lst (call $cdr (local.get $lst)))
            (br $loop)))
       (call $nreverse (local.get $ret)))

 ;;; Pushes 4 elements (regardless of errors).
 ;;; Returns NIL if all arguments are evaluated correctly.
 ;;; Returns an error object if argument evaluation fails.
 ;;; `lst` and `a` must be protected from GC
 (func $evpush (param $lst i32) (param $a i32) (result i32)
       (local $ret i32)
       (local $tmp i32)
       (local.set $ret (i32.const 0))
       ;; Push the first argument
       (if (i32.eqz (local.get $lst))
           (then (call $push (i32.const 0)))
           (else
            (local.set
             $tmp (call $eval (call $car (local.get $lst)) (local.get $a)))
            (call $push (local.get $tmp))
            (if (call $errorp (local.get $tmp))
                (local.set $ret (local.get $tmp)))
            (local.set $lst (call $cdr (local.get $lst)))))
       ;; Push the second argument
       (if (i32.eqz (local.get $lst))
           (then (call $push (i32.const 0)))
           (else
            (local.set
             $tmp (call $eval (call $car (local.get $lst)) (local.get $a)))
            (call $push (local.get $tmp))
            (if (call $errorp (local.get $tmp))
                (local.set $ret (local.get $tmp)))
            (local.set $lst (call $cdr (local.get $lst)))))
       ;; Push the third argument
       (if (i32.eqz (local.get $lst))
           (then (call $push (i32.const 0)))
           (else
            (local.set
             $tmp (call $eval (call $car (local.get $lst)) (local.get $a)))
            (call $push (local.get $tmp))
            (if (call $errorp (local.get $tmp))
                (local.set $ret (local.get $tmp)))
            (local.set $lst (call $cdr (local.get $lst)))))
       ;; Push the rest of arguments
       (if (i32.eqz (local.get $lst))
           (then (call $push (i32.const 0)))
           (else
            (local.set $tmp (call $evlis (local.get $lst) (local.get $a)))
            (if (call $errorp (local.get $tmp))
                (local.set $ret (local.get $tmp)))
            (call $push (local.get $tmp))))
       (local.get $ret))

 (func $evpop
       (global.set $sp (i32.sub (global.get $sp) (i32.const 16))))

 ;; All arguments must be protected from GC
 (func $pairlis (param $x i32) (param $y i32) (param $z i32) (result i32)
       (local $tmp i32)
       (block $block
         (loop $loop
            (br_if $block (i32.eqz (call $consp (local.get $x))))
            (call $push (local.get $z))  ;; For GC (z)
            (local.set $tmp (call $cons
                                  (call $car (local.get $x))
                                  (call $safecar (local.get $y))))
            (call $push (local.get $tmp))  ;; For GC (z tmp)
            (local.set $z (call $cons (local.get $tmp) (local.get $z)))
            (call $drop (call $pop))  ;; For GC (z)
            (call $drop (call $pop))  ;; For GC ()
            (local.set $x (call $cdr (local.get $x)))
            (local.set $y (call $safecdr (local.get $y)))
            (br $loop)))
       (local.get $z))

 (func
  $eval (param $e i32) (param $a i32) (result i32)
  (local $ret i32)
  (local $tmp i32)
  (local $fn_lookup i32)
  (local $fn i32)
  (local $args i32)
  (local.set $ret (i32.const 0))
  (call $log (i32.const 11111));;;;;
  (call $log (global.get $sp));;;;;
  (call $push (local.get $e))  ;; For GC (e)
  (call $push (local.get $a))  ;; For GC (e, a)
  (block $evalbk
    (loop $evallp
       ;; Evaluate an atom (except symbol)
       (call $log (i32.const 10000001));;;;;
       (if (i32.eqz (local.get $e))
           (then (local.set $ret (i32.const 0))
                 (br $evalbk)))
       (if (call $errorp (local.get $e))
           (then (local.set $ret (local.get $e))
                 (br $evalbk)))
       (if (call $numberp (local.get $e))
           (then (local.set $ret (local.get $e))
                 (br $evalbk)))
       ;; Evaluate a symbol
       (call $log (i32.const 10000002));;;;;
       (if (call $symbolp (local.get $e))
           (then
            ;; Get a value from APVAL
            (local.set $tmp
                       (call $get (local.get $e) (global.get $sym_apval)))
            (if (i32.ne (local.get $tmp) (i32.const 0))
                (then
                 (local.set $ret (call $car (local.get $tmp)))
                 (br $evalbk)))
            ;; Get a value from alist
            (local.set $tmp (call $assoc (local.get $e) (local.get $a)))
            (if (i32.ne (local.get $tmp) (i32.const 0))
                (then
                 (local.set $ret (call $cdr (local.get $tmp)))
                 (br $evalbk)))
            ;; The symbol has no value
            (local.set $ret (call $makeStrError (global.get $str_err_unbound)))
            (br $evalbk)))
       (call $log (i32.const 10000003));;;;;
       (if (i32.eqz (call $consp (local.get $e)))  ;; Unknown object
           (then (local.set
                  $ret
                  (call $makeStrError (global.get $str_err_generic)))
                 (br $evalbk)))
       (call $log (i32.const 10000004));;;;;
       ;; Evaluate a compound expression
       (local.set $fn (call $car (local.get $e)))
       (local.set $args (call $cdr (local.get $e)))
       (local.set $fn_lookup (i32.const 0))
       (loop $complp
          ;; Check if fn is FSUBR
          (local.set $tmp
                     (call $get (local.get $fn) (global.get $sym_fsubr)))
          (if (i32.ne (local.get $tmp) (i32.const 0))
              (then
               (local.set
                $ret
                (call_indirect
                 (type $fsubr_type)
                 (call $fixnum2int (local.get $tmp))))
               ;; Check whether the return value should be evaluated
               (if (i32.ne (call $pop) (i32.const 0))
                   (then  ;; need to evaluate return value
                    (i32.store (i32.sub (global.get $sp) (i32.const 8))
                               (local.get $ret))  ;; replace `e` in stack
                    (local.set $e (local.get $ret))
                    (br $evallp)))
               (br $evalbk)))
          (call $log (i32.const 10000005));;;;;
          ;; Check if fn is SUBR
          (local.set $tmp
                     (call $get (local.get $fn) (global.get $sym_subr)))
          (if (i32.ne (local.get $tmp) (i32.const 0))
              (then
               (local.set $ret (call $evpush (local.get $args) (local.get $a)))
               ;; Call the SUBR only if the arguments don't contain errors.
               (if (i32.eqz (local.get $ret))
                   (local.set
                    $ret
                    (call_indirect
                     (type $subr_type)
                     (call $fixnum2int (call $car (local.get $tmp))))))
               (call $evpop)
               (br $evalbk)))
          ;; Check if fn is SUBR
          (local.set $tmp
                     (call $get (local.get $fn) (global.get $sym_expr)))
          (if (i32.ne (local.get $tmp) (i32.const 0))
              (local.set $fn (local.get $tmp)))
          ;; Don't lookup fn from alist twice (to avoid infinite loop)
          (if (i32.and (call $symbolp (local.get $fn))
                       (i32.ne (local.get $fn_lookup) (i32.const 0)))
              (then (local.set
                          $ret
                          (call $makeStrError (global.get $str_err_nodef)))
                         (br $evalbk)))
          ;; Find fn from alist if fn is a symbol
          (if (call $symbolp (local.get $fn))
              (then
               (local.set $fn_lookup (i32.const 1))
               (local.set $tmp (call $assoc (local.get $fn) (local.get $a)))
               (if (i32.eqz (local.get $tmp))
                   (then (local.set
                          $ret
                          (call $makeStrError (global.get $str_err_nodef)))
                         (br $evalbk)))
               (local.set $fn (call $cdr (local.get $tmp)))
               (br $complp)))
          )  ;; complp
       ;; Note that $args is not protected from GC
       (call $log (i32.const 10000006));;;;;
       (local.set $args (call $evlis (local.get $args) (local.get $a)))
       (block $applybk
         (loop $applylp
            ;; fn shouldn't be an atom (we check whether fn is a symbol above)
            (if (i32.eqz (call $consp (local.get $fn)))
                (then (local.set
                       $ret
                       (call $makeStrError (global.get $str_err_nodef)))
                      (br $evalbk)))
            (call $log (i32.const 10000007));;;;;
            (if (i32.eq (call $car (local.get $fn)) (global.get $sym_lambda))
                (then
                 (call $push (local.get $args))  ;; For GC (e, a, args)
                 (local.set
                  $tmp
                  (call $pairlis
                        (call $cadr (local.get $fn)) (local.get $args)
                        (local.get $a)))
                 (call $drop (call $pop))  ;; For GC (e, a)
                 (local.set $e (call $caddr (local.get $fn)))
                 (local.set $a (local.get $tmp))
                 (i32.store (i32.sub (global.get $sp) (i32.const 8))
                            (local.get $e))  ;; replace `e` in stack
                 (i32.store (i32.sub (global.get $sp) (i32.const 4))
                            (local.get $a))  ;; replace `a` in stack
                 (br $evallp)))
            ;; Unknown function
            (local.set
             $ret
             ;; TODO: Return a specific error
             (call $makeStrError (global.get $str_err_generic)))
            ))  ;; applybk
       ))  ;; evalbk
  (call $drop (call $pop))  ;; For GC (e)
  (call $drop (call $pop))  ;; For GC ()
  (call $log (global.get $sp));;;;;
  (call $log (i32.const 22222));;;;;
  (call $log (local.get $ret));;;;
  (local.get $ret))

 ;;; GARBAGE COLLECTOR
 (global $num_mark (mut i32) (i32.const 0))
 (global $num_unmark (mut i32) (i32.const 0))
 (global $num_reclaim (mut i32) (i32.const 0))

 (func $insideHeap (param $obj i32) (result i32)
       (i32.and (i32.le_u (global.get $heap_start) (local.get $obj))
                (i32.lt_u (local.get $obj) (global.get $heap_end))))

 (func $marked (param $cell i32) (result i32)
       (i32.and (i32.load (local.get $cell))
                (global.get $mark_bit)))
 (func $markCell (param $cell i32)
       (i32.store (local.get $cell) (i32.or (i32.load (local.get $cell))
                                            (global.get $mark_bit))))
 (func $unmarkCell (param $cell i32)
       (i32.store (local.get $cell) (i32.and (i32.load (local.get $cell))
                                             (global.get $unmark_mask))))

 ;;; Returns the number of marked objects.
 ;;; `obj` is a Lisp pointer.
 (func $markObj (param $obj i32)
       (local $ca i32)
       (local $cd i32)
       (loop $loop
          ;; Ignore special tag e.g. symbol tag or error tag
          (if (call $specialTagp (local.get $obj))
              (return))
          ;; Ignore fixnum
          (if (call $fixnump (local.get $obj))
              (return))
          ;; So far "other" pointers don't exist
          (if (call $otherp (local.get $obj))
              (unreachable))
          ;; The obj must points to a double word cell
          (if (i32.eqz (call $dwcellp (local.get $obj)))
              (unreachable))
          ;; The obj must not point to beyond heap_end
          (if (i32.ge_u (local.get $obj) (global.get $heap_end))
              (unreachable))

          ;; Ignore objects which are marked
          (if (call $marked (local.get $obj))
              (return))
          ;; Fetch CAR/CDR before making
          (local.set $ca (call $car (local.get $obj)))
          (local.set $cd (call $cdr (local.get $obj)))
          ;; Mark the object and its children
          (if (call $insideHeap (local.get $obj))
              (then
               (global.set
                $num_mark (i32.add (global.get $num_mark) (i32.const 1)))
               (call $markCell (local.get $obj))))
          (call $markObj (local.get $ca))
          (local.set $obj (local.get $cd))
          (br $loop)))

 (func $markStack
       (local $p i32)
       (local.set $p (global.get $sp))
       (block $block
         (loop $loop
            (local.set $p (i32.sub (local.get $p) (i32.const 4)))
            (br_if $block (i32.lt_u (local.get $p) (global.get $stack_bottom)))
            (call $markObj (i32.load (local.get $p)))
            (br $loop))))

 (func $markPrimitiveObj
       (local $p i32)
       (local.set $p (i32.const 0))
       (loop $loop
          (if (i32.eq (local.get $p) (global.get $primitive_obj_end))
              (return))
          (call $markObj (local.get $p))
          (local.set $p (i32.add (local.get $p) (i32.const 8)))
          (br $loop)))

 (func $markOblist
       (local $p i32)
       (local $sym i32)
       (local.set $p (global.get $oblist))
       (loop $loop
          (if (i32.eqz (local.get $p))
              (return))
          (local.set $sym (call $car (local.get $p)))
          (if (i32.eqz (call $simpleSymbolp (call $car (local.get $p))))
              (call $markObj (call $car (local.get $p))))
          (local.set $p (call $cdr (local.get $p)))
          (br $loop)))

 (func $alivep (param $obj i32) (result i32)
       (i32.or (i32.lt_u (local.get $obj) (global.get $primitive_obj_end))
               (call $marked (local.get $obj))))

 (func $reconstructOblist
       (local $p i32)
       (local $next i32)
       (local $alive i32)
       (local.set $p (global.get $oblist))
       (global.set $oblist (i32.const 0))
       (loop $loop
          (if (i32.eqz (call $consp (local.get $p)))
              (then
               (global.set $oblist (call $nreverse (global.get $oblist)))
               (call $markObj (global.get $oblist))
               (return)))
          (local.set $next (call $cdr (local.get $p)))
          (local.set $alive (call $marked (local.get $p)))
          (if (i32.eqz (local.get $alive))
              ;; Note: don't touch CAR when p is marked
              (local.set $alive (call $alivep (call $car (local.get $p)))))
          (if (local.get $alive)
              (then
               (call $setcdr (local.get $p) (global.get $oblist))
               (global.set $oblist (local.get $p))))
          (local.set $p (local.get $next))
          (br $loop)))

 (func $sweepHeap
       (local $p i32)
       (local.set $p (global.get $heap_start))
       (global.set $fp (global.get $fillp))
       (loop $loop
          (if (i32.ge_u (local.get $p) (global.get $fillp))
              (then (global.set
                     $linear_mode
                     (i32.eq (global.get $fp) (global.get $fillp)))
                    (return)))
          (if (call $marked (local.get $p))
              (then
               (call $unmarkCell (local.get $p))
               (global.set
                $num_unmark (i32.add (global.get $num_unmark) (i32.const 1))))
              (else
               (call $setcar (local.get $p) (global.get $sym_f))  ;; For debug
               (call $setcdr (local.get $p) (global.get $fp))
               (global.set $fp (local.get $p))
               (global.set
                $num_reclaim
                (i32.add (global.get $num_reclaim) (i32.const 1)))))
          (local.set $p (i32.add (local.get $p) (i32.const 8)))
          (br $loop)))

 (func $garbageCollect (result i32)
       (call $printComment)
       (call $printString (global.get $str_msg_gc1))  ;; gcing
       (call $terprif)
       (call $printComment)
       (call $printString (global.get $str_msg_gc4))  ;; oblist
       (call $printFixnum
             (call $int2fixnum (call $length (global.get $oblist))))
       (call $terprif)

       (global.set $num_mark (i32.const 0))
       (global.set $num_unmark (i32.const 0))
       (global.set $num_reclaim (i32.const 0))

       (call $markOblist)
       (call $markPrimitiveObj)
       (call $markStack)
       (call $reconstructOblist)

       (call $printComment)
       (call $printString (global.get $str_msg_gc2))  ;; marked
       (call $printFixnum (call $int2fixnum (global.get $num_mark)))
       (call $terprif)

       (call $sweepHeap)

       (call $printComment)
       (call $printString (global.get $str_msg_gc3))  ;; reclaimed
       (call $printFixnum (call $int2fixnum (global.get $num_reclaim)))
       (call $terprif)
       (call $printComment)
       (call $printString (global.get $str_msg_gc4))  ;; oblist
       (call $printFixnum
             (call $int2fixnum (call $length (global.get $oblist))))
       (call $terprif)

       (i32.const 0))
 ;;; END GARBAGE COLLECTOR

 ;; Creates a minimum symbol.
 ;; This function doesn't care GC
 (func $initsym0 (param $sym i32) (param $str i32)
       (local $cell i32)
       (local.set $cell (call $makename (local.get $str)))
       (local.set $cell (call $cons (local.get $cell) (i32.const 0)))
       (local.set $cell (call $cons (global.get $sym_pname) (local.get $cell)))
       (call $setcdr (local.get $sym) (local.get $cell))
       (call $setcar (local.get $sym) (global.get $tag_symbol))
       (call $pushToOblist (local.get $sym)))
 ;; Creates a symbol with APVAL.
 ;; This function doesn't care GC
 (func $initsym1 (param $sym i32) (param $str i32) (param $val i32)
       (local $cell i32)
       (local.set $cell (call $makename (local.get $str)))
       (local.set $cell (call $cons (local.get $cell) (i32.const 0)))
       (local.set $cell (call $cons (global.get $sym_pname) (local.get $cell)))
       (local.set $cell (call $cons
                              (call $cons (local.get $val) (i32.const 0))
                              (local.get $cell)))
       (local.set $cell (call $cons (global.get $sym_apval) (local.get $cell)))
       (call $setcdr (local.get $sym) (local.get $cell))
       (call $setcar (local.get $sym) (global.get $tag_symbol))
       (call $pushToOblist (local.get $sym)))
 ;; Creates a symbol with a key-value pair.
 ;; This function doesn't care GC
 (func $initsymKv (param $sym i32) (param $str i32)
       (param $key i32) (param $val i32)
       (local $cell i32)
       (local.set $cell (call $makename (local.get $str)))
       (local.set $cell (call $cons (local.get $cell) (i32.const 0)))
       (local.set $cell (call $cons (global.get $sym_pname) (local.get $cell)))
       (local.set $cell (call $cons (local.get $val) (local.get $cell)))
       (local.set $cell (call $cons (local.get $key) (local.get $cell)))
       (call $setcdr (local.get $sym) (local.get $cell))
       (call $setcar (local.get $sym) (global.get $tag_symbol))
       (call $pushToOblist (local.get $sym)))
 ;; Creates a symbol with SUBR.
 ;; This function doesn't care GC
 (func $initsymSubr (param $sym i32) (param $str i32)
       (param $idx i32) (param $num_args i32)
       (call $initsymKv
             (local.get $sym) (local.get $str)
             (global.get $sym_subr)
             (call $cons
                   (call $int2fixnum (local.get $idx))
                   (call $cons
                         (call $int2fixnum (local.get $num_args))
                         (i32.const 0)))))

 (func $init
       (local $cell i32)
       (call $initsym0 (global.get $sym_pname) (global.get $str_pname))
       (call $initsym0 (global.get $sym_apval) (global.get $str_apval))
       (call $initsym0 (global.get $sym_dot) (global.get $str_dot))
       (call $initsym0 (global.get $sym_quote) (global.get $str_quote))
       (call $initsym0 (global.get $sym_subr) (global.get $str_subr))
       (call $initsym0 (global.get $sym_fsubr) (global.get $str_fsubr))
       (call $initsym0 (global.get $sym_expr) (global.get $str_expr))
       (call $initsym0 (global.get $sym_fexpr) (global.get $str_fexpr))
       (call $initsym0 (global.get $sym_lambda) (global.get $str_lambda))
       (call $initsym1
             (global.get $sym_nil) (global.get $str_nil) (i32.const 0))
       (call $initsym1
             (global.get $sym_f) (global.get $str_f) (i32.const 0))
       (call $initsym1
             (global.get $sym_t) (global.get $str_t) (global.get $sym_tstar))
       (call $initsym1
             (global.get $sym_tstar) (global.get $str_tstar)
             (global.get $sym_tstar))

       (call $initsymSubr (global.get $sym_car) (global.get $str_car)
             (global.get $idx_car) (i32.const 1))
       (call $initsymSubr (global.get $sym_cdr) (global.get $str_cdr)
             (global.get $idx_cdr) (i32.const 1))
       (call $initsymSubr (global.get $sym_cons) (global.get $str_cons)
             (global.get $idx_cons) (i32.const 2))
       (call $initsymSubr (global.get $sym_cons) (global.get $str_cons)
             (global.get $idx_cons) (i32.const 2))
       (call $initsymSubr (global.get $sym_atom) (global.get $str_atom)
             (global.get $idx_atom) (i32.const 1))
       (call $initsymSubr (global.get $sym_eq) (global.get $str_eq)
             (global.get $idx_eq) (i32.const 2))
       (call $initsymSubr (global.get $sym_equal) (global.get $str_equal)
             (global.get $idx_equal) (i32.const 2))
       (call $initsymSubr (global.get $sym_putprop) (global.get $str_putprop)
             (global.get $idx_putprop) (i32.const 3))
       (call $initsymSubr (global.get $sym_reclaim) (global.get $str_reclaim)
             (global.get $idx_reclaim) (i32.const 0))
       (call $initsymSubr (global.get $sym_print) (global.get $str_print)
             (global.get $idx_print) (i32.const 1))
       (call $initsymSubr (global.get $sym_prin1) (global.get $str_prin1)
             (global.get $idx_prin1) (i32.const 1))
       (call $initsymSubr (global.get $sym_terpri) (global.get $str_terpri)
             (global.get $idx_terpri) (i32.const 0))
       (call $initsymSubr (global.get $sym_return) (global.get $str_return)
             (global.get $idx_return) (i32.const 1))
       (call $initsymSubr (global.get $sym_set) (global.get $str_set)
             (global.get $idx_set) (i32.const 2))
       (call $initsymSubr (global.get $sym_prog2) (global.get $str_prog2)
             (global.get $idx_prog2) (i32.const 2))
       (call $initsymSubr (global.get $sym_minus) (global.get $str_minus)
             (global.get $idx_minus) (i32.const 1))
       (call $initsymSubr (global.get $sym_minus_sign)
             (global.get $str_minus_sign)
             (global.get $idx_difference) (i32.const 2))
       (call $initsymSubr (global.get $sym_difference)
             (global.get $str_difference)
             (global.get $idx_difference) (i32.const 2))
       (call $initsymSubr (global.get $sym_slash_sign)
             (global.get $str_slash_sign)
             (global.get $idx_quotient) (i32.const 2))
       (call $initsymSubr (global.get $sym_divide) (global.get $str_divide)
             (global.get $idx_divide) (i32.const 2))
       (call $initsymSubr (global.get $sym_quotient) (global.get $str_quotient)
             (global.get $idx_quotient) (i32.const 2))
       (call $initsymSubr (global.get $sym_remainder)
             (global.get $str_remainder)
             (global.get $idx_remainder) (i32.const 2))
       (call $initsymSubr (global.get $sym_oneplus) (global.get $str_oneplus)
             (global.get $idx_add1) (i32.const 1))
       (call $initsymSubr (global.get $sym_add1) (global.get $str_add1)
             (global.get $idx_add1) (i32.const 1))
       (call $initsymSubr (global.get $sym_oneminus) (global.get $str_oneminus)
             (global.get $idx_sub1) (i32.const 1))
       (call $initsymSubr (global.get $sym_sub1) (global.get $str_sub1)
             (global.get $idx_sub1) (i32.const 1))
       (call $initsymSubr (global.get $sym_less_sign)
             (global.get $str_less_sign)
             (global.get $idx_lessp) (i32.const 2))
       (call $initsymSubr (global.get $sym_lessp) (global.get $str_lessp)
             (global.get $idx_lessp) (i32.const 2))
       (call $initsymSubr (global.get $sym_greater_sign)
             (global.get $str_greater_sign)
             (global.get $idx_greaterp) (i32.const 2))
       (call $initsymSubr (global.get $sym_greaterp) (global.get $str_greaterp)
             (global.get $idx_greaterp) (i32.const 2))
       (call $initsymSubr (global.get $sym_zerop) (global.get $str_zerop)
             (global.get $idx_zerop) (i32.const 1))
       (call $initsymSubr (global.get $sym_onep) (global.get $str_onep)
             (global.get $idx_onep) (i32.const 1))
       (call $initsymSubr (global.get $sym_minusp) (global.get $str_minusp)
             (global.get $idx_minusp) (i32.const 1))
       (call $initsymSubr (global.get $sym_numberp) (global.get $str_numberp)
             (global.get $idx_numberp) (i32.const 1))

       (call $initsymKv
             (global.get $sym_list) (global.get $str_list)
             (global.get $sym_fsubr) (call $int2fixnum (global.get $idx_list)))
       (call $initsymKv
             (global.get $sym_if) (global.get $str_if)
             (global.get $sym_fsubr) (call $int2fixnum (global.get $idx_if)))
       (call $initsymKv
             (global.get $sym_quote) (global.get $str_quote)
             (global.get $sym_fsubr)
             (call $int2fixnum (global.get $idx_quote)))
       (call $initsymKv
             (global.get $sym_plus) (global.get $str_plus)
             (global.get $sym_fsubr) (call $int2fixnum (global.get $idx_plus)))
       (call $initsymKv
             (global.get $sym_plus_sign) (global.get $str_plus_sign)
             (global.get $sym_fsubr) (call $int2fixnum (global.get $idx_plus)))
       (call $initsymKv
             (global.get $sym_prog) (global.get $str_prog)
             (global.get $sym_fsubr) (call $int2fixnum (global.get $idx_prog)))
       (call $initsymKv
             (global.get $sym_go) (global.get $str_go)
             (global.get $sym_fsubr) (call $int2fixnum (global.get $idx_go)))
       (call $initsymKv
             (global.get $sym_setq) (global.get $str_setq)
             (global.get $sym_fsubr) (call $int2fixnum (global.get $idx_setq)))
       (call $initsymKv
             (global.get $sym_star_sign) (global.get $str_star_sign)
             (global.get $sym_fsubr)
             (call $int2fixnum (global.get $idx_times)))
       (call $initsymKv
             (global.get $sym_times) (global.get $str_times)
             (global.get $sym_fsubr)
             (call $int2fixnum (global.get $idx_times)))

       (call $embedStrError (global.get $err_gc) (global.get $str_err_gc))
       )

 ;;; SUBR/FSUBR
 ;;; SUBR stack: (..., a, arg1, arg2, arg3, restArgs)
 ;;; FSUBR stack: (..., e, a)  e is an expression like (QUOTE A)
 ;;; FSUBR stack after eval: (..., e, a, E)  E!=0: need to eval return value

 ;;; Returns the arguments from SUBR stack
 (func $getArg1 (result i32)
      (i32.load (i32.sub (global.get $sp) (i32.const 16))))
 (func $getArg2 (result i32)
      (i32.load (i32.sub (global.get $sp) (i32.const 12))))
 (func $getArg3 (result i32)
      (i32.load (i32.sub (global.get $sp) (i32.const 8))))
 (func $getArg4 (result i32)
      (i32.load (i32.sub (global.get $sp) (i32.const 4))))
 (func $getAArgInSubr (result i32)
      (i32.load (i32.sub (global.get $sp) (i32.const 20))))

 ;;; Returns the arguments from FSUBR stack
 (func $getEArg (result i32)
      (i32.load (i32.sub (global.get $sp) (i32.const 8))))
 (func $getAArg (result i32)
      (i32.load (i32.sub (global.get $sp) (i32.const 4))))

 (elem (i32.const 100) $subr_car)
 (global $idx_car i32 (i32.const 100))
 (elem (i32.const 101) $subr_cdr)
 (global $idx_cdr i32 (i32.const 101))
 (elem (i32.const 102) $subr_cons)
 (global $idx_cons i32 (i32.const 102))
 (elem (i32.const 103) $subr_atom)
 (global $idx_atom i32 (i32.const 103))
 (elem (i32.const 104) $subr_eq)
 (global $idx_eq i32 (i32.const 104))
 (elem (i32.const 105) $subr_equal)
 (global $idx_equal i32 (i32.const 105))
 (elem (i32.const 106) $fsubr_list)
 (global $idx_list i32 (i32.const 106))
 (elem (i32.const 107) $fsubr_if)
 (global $idx_if i32 (i32.const 107))
 (elem (i32.const 108) $fsubr_quote)
 (global $idx_quote i32 (i32.const 108))
 (elem (i32.const 109) $subr_putprop)
 (global $idx_putprop i32 (i32.const 109))
 (elem (i32.const 110) $subr_reclaim)
 (global $idx_reclaim i32 (i32.const 110))
 (elem (i32.const 111) $fsubr_plus)
 (global $idx_plus i32 (i32.const 111))
 (elem (i32.const 112) $fsubr_prog)
 (global $idx_prog i32 (i32.const 112))
 (elem (i32.const 113) $subr_print)
 (global $idx_print i32 (i32.const 113))
 (elem (i32.const 114) $subr_prin1)
 (global $idx_prin1 i32 (i32.const 114))
 (elem (i32.const 115) $subr_terpri)
 (global $idx_terpri i32 (i32.const 115))
 (elem (i32.const 116) $fsubr_go)
 (global $idx_go i32 (i32.const 116))
 (elem (i32.const 117) $subr_return)
 (global $idx_return i32 (i32.const 117))
 (elem (i32.const 118) $subr_set)
 (global $idx_set i32 (i32.const 118))
 (elem (i32.const 119) $fsubr_setq)
 (global $idx_setq i32 (i32.const 119))
 (elem (i32.const 120) $subr_prog2)
 (global $idx_prog2 i32 (i32.const 120))
 (elem (i32.const 121) $subr_minus)
 (global $idx_minus i32 (i32.const 121))
 (elem (i32.const 122) $subr_difference)
 (global $idx_difference i32 (i32.const 122))
 (elem (i32.const 123) $fsubr_times)
 (global $idx_times i32 (i32.const 123))
 (elem (i32.const 124) $subr_divide)
 (global $idx_divide i32 (i32.const 124))
 (elem (i32.const 125) $subr_quotient)
 (global $idx_quotient i32 (i32.const 125))
 (elem (i32.const 126) $subr_remainder)
 (global $idx_remainder i32 (i32.const 126))
 (elem (i32.const 127) $subr_add1)
 (global $idx_add1 i32 (i32.const 127))
 (elem (i32.const 128) $subr_sub1)
 (global $idx_sub1 i32 (i32.const 128))
 (elem (i32.const 129) $subr_lessp)
 (global $idx_lessp i32 (i32.const 129))
 (elem (i32.const 130) $subr_greaterp)
 (global $idx_greaterp i32 (i32.const 130))
 (elem (i32.const 131) $subr_zerop)
 (global $idx_zerop i32 (i32.const 131))
 (elem (i32.const 132) $subr_onep)
 (global $idx_onep i32 (i32.const 132))
 (elem (i32.const 133) $subr_minusp)
 (global $idx_minusp i32 (i32.const 133))
 (elem (i32.const 134) $subr_numberp)
 (global $idx_numberp i32 (i32.const 134))

 (func $subr_car (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (call $car (local.get $arg1)))
 (func $subr_cdr (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (call $cdr (local.get $arg1)))
 (func $subr_cons (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (call $cons (local.get $arg1) (local.get $arg2)))
 (func $subr_atom (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (if (i32.eqz (call $consp (local.get $arg1)))
           (return (global.get $sym_tstar)))
       (i32.const 0))
 (func $subr_eq (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.eq (local.get $arg1) (local.get $arg2))
           (return (global.get $sym_tstar)))
       (i32.const 0))
 (func $equal (param $x i32) (param $y i32) (result i32)
       (if (i32.eq (local.get $x) (local.get $y))
           (return (i32.const 1)))
       ;; TODO: other type checks
       (if (i32.and (call $consp (local.get $x))
                    (call $consp (local.get $y)))
           (return (i32.and (call $equal
                                  (call $car (local.get $x))
                                  (call $car (local.get $y)))
                            (call $equal
                                  (call $cdr (local.get $x))
                                  (call $cdr (local.get $y))))))
       (i32.const 0))
 (func $subr_equal (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (call $equal (local.get $arg1) (local.get $arg2))
           (return (global.get $sym_tstar)))
       (i32.const 0))
 (func $fsubr_list (result i32)
       (local $a i32)
       (local $args i32)
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (call $evlis (local.get $args) (local.get $a)))
 (func $fsubr_if (result i32)
       (local $a i32)
       (local $args i32)
       (local $ret i32)
       (local $tmp i32)
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       (local.set
        $tmp (call $eval (call $car (local.get $args)) (local.get $a)))
       (if (call $errorp (local.get $tmp))
           (then
            (call $push (i32.const 0))  ;; Don't need to eval return value
            (return (local.get $tmp))))
       (if (i32.eqz (local.get $tmp))
           (local.set $ret
                      (call $safecar
                            (call $safecdr (call $safecdr (local.get $args)))))
           (local.set $ret
                      (call $safecar (call $safecdr (local.get $args)))))
       (call $push (i32.const 1))  ;; *Need* to eval return value
       (local.get $ret))
 (func $fsubr_quote (result i32)
       (local $args i32)
       (local.set $args (call $cdr (call $getEArg)))
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (call $car (local.get $args)))

 (func $subr_putprop (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local $arg3 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (local.set $arg3 (call $getArg3))
       (call $putprop (local.get $arg1) (local.get $arg2) (local.get $arg3))
       (local.get $arg1))

 (func $fsubr_plus (result i32)
       (local $acc i32)
       (local $tmp i32)
       (local $ret i32)
       (local $a i32)
       (local $args i32)
       (local.set $acc (i32.const 0))
       (local.set $ret (i32.const 0))
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       (local.set $args (call $evlis (local.get $args) (local.get $a)))
       (block $block
         (if (call $errorp (local.get $args))
             (then (local.set $ret (local.get $args))
                   (br $block)))
         (loop $loop
            (br_if $block (i32.eqz (call $consp (local.get $args))))
            (local.set $tmp (call $car (local.get $args)))
            (if (call $fixnump (local.get $tmp))
                (then
                 (local.set $acc (i32.add (call $fixnum2int (local.get $tmp))
                                          (local.get $acc))))
                (else
                 (local.set
                  $ret (call $makeStrError (global.get $str_err_num)))
                 (br $block)))
            (local.set $args (call $cdr (local.get $args)))
            (br $loop)))
       (if (i32.eqz (local.get $ret))
           (local.set $ret (call $int2fixnum (local.get $acc))))
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (local.get $ret))

  (func $fsubr_times (result i32)
       (local $acc i32)
       (local $tmp i32)
       (local $ret i32)
       (local $a i32)
       (local $args i32)
       (local.set $acc (i32.const 1))
       (local.set $ret (i32.const 0))
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       (local.set $args (call $evlis (local.get $args) (local.get $a)))
       (block $block
         (if (call $errorp (local.get $args))
             (then (local.set $ret (local.get $args))
                   (br $block)))
         (loop $loop
            (br_if $block (i32.eqz (call $consp (local.get $args))))
            (local.set $tmp (call $car (local.get $args)))
            (if (call $fixnump (local.get $tmp))
                (then
                 (local.set $acc (i32.mul (call $fixnum2int (local.get $tmp))
                                          (local.get $acc))))
                (else
                 (local.set
                  $ret (call $makeStrError (global.get $str_err_num)))
                 (br $block)))
            (local.set $args (call $cdr (local.get $args)))
            (br $loop)))
       (if (i32.eqz (local.get $ret))
           (local.set $ret (call $int2fixnum (local.get $acc))))
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (local.get $ret))

 (func $subr_reclaim (result i32)
       (call $garbageCollect))

 (func $fsubr_prog (result i32)
       (local $a i32)
       (local $args i32)
       (local $exps i32)
       (local $exp i32)
       (local $ret i32)
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       (if (i32.ne (call $car (local.get $args)) (i32.const 0))
            (local.set
             $a
             (call $pairlis (call $car (local.get $args)) (i32.const 0)
                   (local.get $a))))
       (call $push (local.get $a))  ;; For GC (a)
       (local.set $exps (call $cdr (local.get $args)))
       (local.set $ret (i32.const 0))
       (block $block
         (loop $loop
            (br_if $block (i32.eqz (call $consp (local.get $exps))))
            (local.set $exp (call $car (local.get $exps)))
            (if (call $consp (local.get $exp))
                (then
                 (local.set $exp (call $eval (local.get $exp) (local.get $a)))
                 ;; Handle RETURN
                 (if (call $catchablep
                           (local.get $exp) (global.get $ce_return))
                     (then (local.set $ret (call $getCEValue (local.get $exp)))
                           (br $block)))
                 ;; Handle GO
                 (if (call $catchablep
                           (local.get $exp) (global.get $ce_go))
                     (then
                      ;; Search the label
                      (local.set
                       $exp (call $member
                                  (call $getCEValue (local.get $exp))
                                  (call $cdr (local.get $args))))
                      ;; Label not found
                      (if (i32.eqz (local.get $exp))
                          (then
                           (local.set
                            $ret
                            (call $makeStrError (global.get $str_err_label)))
                           (br $block)))
                      ;; Note: `exp` points to a list, so errorp returns 0
                      (local.set $exps (local.get $exp))))
                 (if (call $errorp (local.get $exp))
                     (then (local.set $ret (local.get $exp))
                           (br $block)))))
            (local.set $exps (call $cdr (local.get $exps)))
            (br $loop)))
       (call $drop (call $pop))  ;; For GC ()
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (local.get $ret))

 (func $subr_print (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (call $printObj (local.get $arg1))
       (call $terprif)
       (local.get $arg1))
 (func $subr_prin1 (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (call $printObj (local.get $arg1))
       (call $fflush)
       (local.get $arg1))
 (func $subr_terpri (result i32)
       (call $terprif)
       (i32.const 0))

 (func $fsubr_go (result i32)
       (local $args i32)
       (local.set $args (call $cdr (call $getEArg)))
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (call $makeCatchableError
             (global.get $ce_go) (call $car (local.get $args))))
 (func $subr_return (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (call $makeCatchableError (global.get $ce_return) (local.get $arg1)))

 (func $subr_set (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local $a i32)
       (local $p i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (local.set $a (call $getAArgInSubr))
       (local.set $p (call $assoc (local.get $arg1) (local.get $a)))
       (if (i32.eqz (local.get $p))
           ;; TODO: Return the specific error
           (return (call $makeStrError (global.get $str_err_generic))))
       (call $setcdr (local.get $p) (local.get $arg2))
       (local.get $arg2))
 (func $fsubr_setq (result i32)
       (local $args i32)
       (local $a i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local $p i32)
       (local.set $args (call $cdr (call $getEArg)))
       (local.set $a (call $getAArg))
       (local.set $arg1 (call $car (local.get $args)))
       (local.set $arg2 (call $cadr (local.get $args)))
       (local.set $arg2 (call $eval (local.get $arg2) (local.get $a)))
       (local.set $p (call $assoc (local.get $arg1) (local.get $a)))
       (if (i32.eqz (local.get $p))
            ;;; Replace the return value
            ;; TODO: Return the specific error
           (local.set
            $arg2 (call $makeStrError (global.get $str_err_generic)))
           (call $setcdr (local.get $p) (local.get $arg2)))
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (local.get $arg2))

  (func $subr_prog2 (result i32)
        (call $getArg2))

 (func $subr_minus (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $makeStrError (global.get $str_err_num))))
       (call $int2fixnum (i32.mul (call $fixnum2int (local.get $arg1))
                                  (i32.const -1))))
 (func $subr_difference (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.or (i32.eqz (call $fixnump (local.get $arg1)))
                   (i32.eqz (call $fixnump (local.get $arg2))))
           (return (call $makeStrError (global.get $str_err_num))))
       (call $int2fixnum (i32.sub (call $fixnum2int (local.get $arg1))
                                  (call $fixnum2int (local.get $arg2)))))
 (func $subr_divide (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.or (i32.eqz (call $fixnump (local.get $arg1)))
                   (i32.eqz (call $fixnump (local.get $arg2))))
           (return (call $makeStrError (global.get $str_err_num))))
       (call
        $list2
        (call $int2fixnum (i32.div_s (call $fixnum2int (local.get $arg1))
                                     (call $fixnum2int (local.get $arg2))))
        (call $int2fixnum (i32.rem_s (call $fixnum2int (local.get $arg1))
                                     (call $fixnum2int (local.get $arg2))))))
 (func $subr_quotient (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.or (i32.eqz (call $fixnump (local.get $arg1)))
                   (i32.eqz (call $fixnump (local.get $arg2))))
           (return (call $makeStrError (global.get $str_err_num))))
       (call $int2fixnum (i32.div_s (call $fixnum2int (local.get $arg1))
                                    (call $fixnum2int (local.get $arg2)))))
 (func $subr_remainder (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.or (i32.eqz (call $fixnump (local.get $arg1)))
                   (i32.eqz (call $fixnump (local.get $arg2))))
           (return (call $makeStrError (global.get $str_err_num))))
       (call $int2fixnum (i32.rem_s (call $fixnum2int (local.get $arg1))
                                    (call $fixnum2int (local.get $arg2)))))

 (func $subr_add1 (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $makeStrError (global.get $str_err_num))))
       (call $int2fixnum (i32.add (call $fixnum2int (local.get $arg1))
                                  (i32.const 1))))
 (func $subr_sub1 (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $makeStrError (global.get $str_err_num))))
       (call $int2fixnum (i32.sub (call $fixnum2int (local.get $arg1))
                                  (i32.const 1))))

 (func $subr_lessp (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.or (i32.eqz (call $fixnump (local.get $arg1)))
                   (i32.eqz (call $fixnump (local.get $arg2))))
           (return (call $makeStrError (global.get $str_err_num))))
       (if (i32.lt_s (call $fixnum2int (local.get $arg1))
                     (call $fixnum2int (local.get $arg2)))
           (return (global.get $sym_tstar)))
       (i32.const 0))
 (func $subr_greaterp (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.or (i32.eqz (call $fixnump (local.get $arg1)))
                   (i32.eqz (call $fixnump (local.get $arg2))))
           (return (call $makeStrError (global.get $str_err_num))))
       (if (i32.gt_s (call $fixnum2int (local.get $arg1))
                     (call $fixnum2int (local.get $arg2)))
           (return (global.get $sym_tstar)))
       (i32.const 0))

 (func $subr_zerop (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $makeStrError (global.get $str_err_num))))
       (if (i32.eqz (call $fixnum2int (local.get $arg1)))
           (return (global.get $sym_tstar)))
       (i32.const 0))
 (func $subr_onep (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $makeStrError (global.get $str_err_num))))
       (if (i32.eq (call $fixnum2int (local.get $arg1))
                                 (i32.const 1))
           (return (global.get $sym_tstar)))
       (i32.const 0))
 (func $subr_minusp (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $makeStrError (global.get $str_err_num))))
       (if (i32.lt_s (call $fixnum2int (local.get $arg1))
                                   (i32.const 0))
           (return (global.get $sym_tstar)))
       (i32.const 0))
 (func $subr_numberp (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (if (call $numberp (local.get $arg1))
           (return (global.get $sym_tstar)))
       (i32.const 0))
 ;;; END SUBR/FSUBR

 ;;; EXPR/FEXPR
 (global $str_expr_defs i32 (i32.const 196608))
 (data
  (i32.const 196608)  ;; 64KB * 3
  "(PUTPROP 'DEFINE '(LAMBDA (L) "
  "(IF L "
  "(CONS (PUTPROP (CAR (CAR L)) (CAR (CDR (CAR L))) 'EXPR) (DEFINE (CDR L))) "
  "L)) "
  "'EXPR) "
  "NIL "  ;; END OF EXPR
  "\00")

 (func $initexpr
       (local $ret i32)
       (global.set $readp (global.get $str_expr_defs))
       (loop $loop
          (global.set $printp (i32.const 40960))
          (local.set $ret (call $eval (call $read) (i32.const 0)))
          (call $printObj (local.get $ret))
          (call $logstr (i32.const 40960))
          (br_if $loop (i32.eqz (i32.or
                                 (i32.eq (local.get $ret) (i32.const 0))
                                 (call $errorp (local.get $ret)))))))
 ;;; END EXPR/FEXPR

 (func $fflush
       (call $outputString (i32.const 40960))
       (global.set $printp (i32.const 40960)))

 (func (export "init")
       (call $init)
       (call $initexpr)
)

 (func (export "readAndEval")
       (local $alist i32)
       (local.set $alist (i32.const 0))

       (global.set $printp (i32.const 40960))
       (global.set $readp (i32.const 51200))
       (call $printObj
             (call $eval (call $read) (local.get $alist)))
       (call $outputString (i32.const 40960)))

 (func (export "read")
       (global.set $printp (i32.const 40960))
       (global.set $readp (i32.const 51200))
       (call $printObj (call $read))
       (call $outputString (i32.const 40960)))

 )
