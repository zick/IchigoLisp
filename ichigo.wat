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
;;; <SYMBOL>
;;;
;;; Symbol is a double-word cell whose CAR contains the special value -4.
;;; Symbol's CDR represents a property list like (key1 value1 key2 value2 ...).
;;; So a symbol is a list like (-4 key1 value1 key2 value2 ...). All symbols
;;; has PNAME as a key, and the corresponding value is a list of fixnums.
;;; The list is called "name", and the fixnum is called "name1". The "name1"
;;; contains up to 3 characters. The symbol "HOGE" contains a name which
;;; consists of two name1-s: "HOG" and "E". So the symbol "HOGE" is a list like
;;; (-4 PNAME ("HOG" "E")).
;;;
;;;
;;; <HEAP AND STACK>
;;;
;;; Heap contains only double-word cells so far (maybe other objects will be
;;; introduced in the future). Double-word cells contain only Lisp pointers.
;;; So heap contains only Lisp pointers. Stack contains only Lisp pointers
;;; (rather than double-word cells). An integer must be converted into a fixnum
;;; when pushing it to stack. Double-word cells pointed from stack are
;;; protected from garbage collector.
;;;
;;;
;;; <MEMORY LAYOUT>
;;;
;;; The following layout will very likely change in the future.
;;; Q. Why is the page 1 empty?
;;; A. There used to be heap. Now we can use it for other purposes.
;;;
;;; +--------------+ 0 (0x0) [page 0]
;;; | Primitive    |
;;; | Lisp         |
;;; | objects      |
;;; | like NIL     |
;;; |              |
;;; +--------------+ 2000 (0x7d0)
;;; | Symbol       |
;;; | name         |
;;; | strings      |
;;; |              |
;;; +--------------+ 5000 (0x1388)
;;; | Other        |
;;; | strings      |
;;; | like         |
;;; | error        |
;;; | messages     |
;;; |              |
;;; +--------------+ 10240 (0x2800)
;;; |              |
;;; | BOFFO etc    |
;;; |              |
;;; +--------------+ 40960 (0xa000)
;;; |              |
;;; | User         |
;;; | input        |
;;; | from JS      |
;;; |              |
;;; +--------------+ 65536 (0x10000) [page 1]
;;; |              |
;;; | (empty)      |
;;; |              |
;;; +--------------+ 131072 (0x20000) [page 2]
;;; |              |
;;; | stack        |
;;; |              |
;;; +--------------+ 196608 (0x30000) [page 3]
;;; |              |
;;; | Lisp code    |
;;; | string       |
;;; |              |
;;; +--------------+ 262144 (0x40000) [page 4]
;;; |              |
;;; | heap         | 327680 (0x50000) [page 5]
;;; |              |


(module
 (func $log (import "console" "log") (param i32))
 (func $logstr (import "console" "logstr") (param i32))
 (func $outputString (import "io" "outputString") (param i32))
 (func $loadWasm (import "io" "loadWasm") (param i32) (param i32))
 (func $getTimeInMs (import "io" "getTimeInMs") (result i64))
 ;; WebAssembly page size is 64KB.
 ;; page 0: any
 ;; page 1: (empty)
 ;; page 2: stack
 ;; page 3: expr/fexpr
 ;; page 4-5: free list
 (import "js" "memory" (memory 6))
 (import "js" "table" (table 512 funcref))

 (type $subr_type (func (result i32)))
 (type $fsubr_type (func (result i32)))

 (global $mark_bit i32 (i32.const 1))
 (global $unmark_mask i32 (i32.const 0xfffffffe))

 (global $tag_symbol i32 (i32.const -4))
 (global $tag_error i32 (i32.const -12))

 ;;; Start address of the heap (inclusive)
 (global $heap_start (mut i32) (i32.const 262144))  ;; 64KB*4
 ;;; Points to the head of free list
 (global $fp (mut i32) (i32.const 262144))
 ;;; Fill pointer of heap
 (global $fillp (mut i32) (i32.const 0))
 ;;; End address of the heap (exclusive)
 (global $heap_end (mut i32) (i32.const 393216))  ;; 64KB*6
 ;;; Address of stack bottom (inclusive)
 (global $stack_bottom (mut i32) (i32.const 131072))
 ;;; Stack pointer
 (global $sp (mut i32) (i32.const 131072))

 (global $boffo i32 (i32.const 10240))
 (global $boffop (mut i32) (i32.const 10240))
 (global $uboffo i32 (i32.const 11264))  ;; boffo + 1024
 (global $uboffop (mut i32) (i32.const 11264))
 (global $read_start (mut i32) (i32.const 0))
 (global $readp (mut i32) (i32.const 0))
 (global $printp (mut i32) (i32.const 0))

 (global $bwrite_start (mut i32) (i32.const 229376))  ;; 64KB*3 + 32KB
 (global $bwritep (mut i32) (i32.const 229376))
 (global $next_subr (mut i32) (i32.const 300))

 (global $oblist (mut i32) (i32.const 0))
 (global $gensym_num (mut i32) (i32.const 0))

 (global $trace_level (mut i32) (i32.const 0))
 (global $traceset_env (mut i32) (i32.const 0))

 (global $st_level (mut i32) (i32.const 0))
 (global $st_max_level (mut i32) (i32.const 5))

 (global $cons_counting (mut i32) (i32.const 0))
 (global $cons_count (mut i32) (i32.const 0))
 (global $cons_limit (mut i32) (i32.const 0))
 (global $suppress_error (mut i32) (i32.const 0))
 (global $debug_level (mut i32) (i32.const 0))
 (global $suppress_gc_msg (mut i32) (i32.const 0))
 (global $gc_count (mut i32) (i32.const 0))

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
 (data (i32.const 2560) "COND\00")  ;; 5
 (global $str_cond i32 (i32.const 2560))
 (data (i32.const 2570) "FUNARG\00")  ;; 7
 (global $str_funarg i32 (i32.const 2570))
 (data (i32.const 2580) "FUNCTION\00")  ;; 9
 (global $str_function i32 (i32.const 2580))
 (data (i32.const 2590) "LABEL\00")  ;; 6
 (global $str_label i32 (i32.const 2590))
 (data (i32.const 2600) "NULL\00")  ;; 5
 (global $str_null i32 (i32.const 2600))
 (data (i32.const 2610) "RPLACA\00")  ;; 7
 (global $str_rplaca i32 (i32.const 2610))
 (data (i32.const 2620) "RPLACD\00")  ;; 7
 (global $str_rplacd i32 (i32.const 2620))
 (data (i32.const 2630) "TRACE\00")  ;; 6
 (global $str_trace i32 (i32.const 2630))
 (data (i32.const 2640) "GET\00")  ;; 4
 (global $str_get i32 (i32.const 2640))
 (data (i32.const 2650) "EVAL\00")  ;; 5
 (global $str_eval i32 (i32.const 2650))
 (data (i32.const 2660) "APPLY\00")  ;; 6
 (global $str_apply i32 (i32.const 2660))
 (data (i32.const 2670) "OBLIST\00")  ;; 7
 (global $str_oblist i32 (i32.const 2670))
 (data (i32.const 2680) "CHARCOUNT\00")  ;; 10
 (global $str_charcount i32 (i32.const 2680))
 (data (i32.const 2690) "CURCHAR\00")  ;; 10
 (global $str_curchar i32 (i32.const 2690))
 (data (i32.const 2700) "$EOF$\00")  ;; 6
 (global $str_eof i32 (i32.const 2700))
 (data (i32.const 2710) "$EOR$\00")  ;; 6
 (global $str_eor i32 (i32.const 2710))
 (data (i32.const 2720) "ADVANCE\00")  ;; 8
 (global $str_advance i32 (i32.const 2720))
 (data (i32.const 2730) "STARTREAD\00")  ;; 10
 (global $str_startread i32 (i32.const 2730))
 (data (i32.const 2740) "ENDREAD\00")  ;; 8
 (global $str_endread i32 (i32.const 2740))
 (data (i32.const 2750) "NCONC\00")  ;; 6
 (global $str_nconc i32 (i32.const 2750))
 (data (i32.const 2760) "AND\00")  ;; 4
 (global $str_and i32 (i32.const 2760))
 (data (i32.const 2770) "OR\00")  ;; 3
 (global $str_or i32 (i32.const 2770))
 (data (i32.const 2780) "LOGAND\00")  ;; 7
 (global $str_logand i32 (i32.const 2780))
 (data (i32.const 2790) "LOGOR\00")  ;; 6
 (global $str_logor i32 (i32.const 2790))
 (data (i32.const 2800) "LOGXOR\00")  ;; 7
 (global $str_logxor i32 (i32.const 2800))
 (data (i32.const 2810) "MAX\00")  ;; 4
 (global $str_max i32 (i32.const 2810))
 (data (i32.const 2820) "MIN\00")  ;; 4
 (global $str_min i32 (i32.const 2820))
 (data (i32.const 2830) "TRACESET\00")  ;; 9
 (global $str_traceset i32 (i32.const 2830))
 (data (i32.const 2840) "CLEARBUFF\00")  ;; 10
 (global $str_clearbuff i32 (i32.const 2840))
 (data (i32.const 2850) "PACK\00")  ;; 5
 (global $str_pack i32 (i32.const 2850))
 (data (i32.const 2860) "MKNAM\00")  ;; 6
 (global $str_mknam i32 (i32.const 2860))
 (data (i32.const 2870) "INTERN\00")  ;; 7
 (global $str_intern i32 (i32.const 2870))
 (data (i32.const 2880) "NUMOB\00")  ;; 6
 (global $str_numob i32 (i32.const 2880))
 (data (i32.const 2890) "UNPACK\00")  ;; 7
 (global $str_unpack i32 (i32.const 2890))
 (data (i32.const 2900) "LITER\00")  ;; 6
 (global $str_liter i32 (i32.const 2900))
 (data (i32.const 2910) "DIGIT\00")  ;; 6
 (global $str_digit i32 (i32.const 2910))
 (data (i32.const 2920) "OPCHAR\00")  ;; 7
 (global $str_opchar i32 (i32.const 2920))
 (data (i32.const 2930) "DASH\00")  ;; 5
 (global $str_dash i32 (i32.const 2930))
 (data (i32.const 2940) "APPEND\00")  ;; 7
 (global $str_append i32 (i32.const 2940))
 (data (i32.const 2950) "ATTRIB\00")  ;; 7
 (global $str_attrib i32 (i32.const 2950))
 (data (i32.const 2960) "COPY\00")  ;; 5
 (global $str_copy i32 (i32.const 2960))
 (data (i32.const 2970) "NOT\00")  ;; 4
 (global $str_not i32 (i32.const 2970))
 (data (i32.const 2980) "PROP\00")  ;; 5
 (global $str_prop i32 (i32.const 2980))
 (data (i32.const 2990) "REMPROP\00")  ;; 8
 (global $str_remprop i32 (i32.const 2990))
 (data (i32.const 3000) "PAIR\00")  ;; 5
 (global $str_pair i32 (i32.const 3000))
 (data (i32.const 3010) "SASSOC\00")  ;; 7
 (global $str_sassoc i32 (i32.const 3010))
 (data (i32.const 3020) "SUBST\00")  ;; 6
 (global $str_subst i32 (i32.const 3020))
 (data (i32.const 3030) "SUBLIS\00")  ;; 7
 (global $str_sublis i32 (i32.const 3030))
 (data (i32.const 3040) "REVERSE\00")  ;; 8
 (global $str_reverse i32 (i32.const 3040))
 (data (i32.const 3050) "MEMBER\00")  ;; 7
 (global $str_member i32 (i32.const 3050))
 (data (i32.const 3060) "LENGTH\00")  ;; 7
 (global $str_length i32 (i32.const 3060))
 (data (i32.const 3070) "EFFACE\00")  ;; 7
 (global $str_efface i32 (i32.const 3070))
 (data (i32.const 3080) "MAPLIST\00")  ;; 8
 (global $str_maplist i32 (i32.const 3080))
 (data (i32.const 3090) "MAPCON\00")  ;; 7
 (global $str_mapcon i32 (i32.const 3090))
 (data (i32.const 3100) "MAP\00")  ;; 4
 (global $str_map i32 (i32.const 3100))
 (data (i32.const 3110) "SEARCH\00")  ;; 7
 (global $str_search i32 (i32.const 3110))
 (data (i32.const 3120) "RECIP\00")  ;; 6
 (global $str_recip i32 (i32.const 3120))
 (data (i32.const 3130) "EXPT\00")  ;; 5
 (global $str_expt i32 (i32.const 3130))
 (data (i32.const 3140) "FIXP\00")  ;; 5
 (global $str_fixp i32 (i32.const 3140))
 (data (i32.const 3150) "FLOATP\00")  ;; 7
 (global $str_floatp i32 (i32.const 3150))
 (data (i32.const 3160) "LEFTSHIFT\00")  ;; 10
 (global $str_leftshift i32 (i32.const 3160))
 (data (i32.const 3170) "READ\00")  ;; 5
 (global $str_read i32 (i32.const 3170))
 (data (i32.const 3180) "PUNCH\00")  ;; 6
 (global $str_punch i32 (i32.const 3180))
 (data (i32.const 3190) "GENSYM\00")  ;; 7
 (global $str_gensym i32 (i32.const 3190))
 (data (i32.const 3200) "REMOB\00")  ;; 6
 (global $str_remob i32 (i32.const 3200))
 (data (i32.const 3210) "EVLIS\00")  ;; 6
 (global $str_evlis i32 (i32.const 3210))
 (data (i32.const 3220) "DUMP\00")  ;; 5
 (global $str_dump i32 (i32.const 3220))
 (data (i32.const 3230) "ERROR\00")  ;; 6
 (global $str_error i32 (i32.const 3230))
 (data (i32.const 3240) "COUNT\00")  ;; 6
 (global $str_count i32 (i32.const 3240))
 (data (i32.const 3250) "UNCOUNT\00")  ;; 8
 (global $str_uncount i32 (i32.const 3250))
 (data (i32.const 3260) "SPEAK\00")  ;; 6
 (global $str_speak i32 (i32.const 3260))
 (data (i32.const 3270) "ERRORSET\00")  ;; 9
 (global $str_errorset i32 (i32.const 3270))
 (data (i32.const 3280) "BWRITE\00")  ;; 7
 (global $str_bwrite i32 (i32.const 3280))
 (data (i32.const 3290) "BDUMP\00")  ;; 6
 (global $str_bdump i32 (i32.const 3290))
 (data (i32.const 3300) "LOAD-WASM\00")  ;; 10
 (global $str_loadwasm i32 (i32.const 3300))
 (data (i32.const 3310) "NEXT-SUBR\00")  ;; 10
 (global $str_nextsubr i32 (i32.const 3310))
 (data (i32.const 3320) "FENCODE\00")  ;; 8
 (global $str_fencode i32 (i32.const 3320))
 (data (i32.const 3330) "TIME\00")  ;; 5
 (global $str_time i32 (i32.const 3330))
 (data (i32.const 3340) "C::VCTAG\00")  ;; 9
 (global $str_vctag i32 (i32.const 3340))
 (data (i32.const 3350) "EVAL-ENTER-HOOK\00")  ;; 16 !!!
 (global $str_eval_enter_hook i32 (i32.const 3350))
 (data (i32.const 3370) "STOP\00")  ;; 5
 (global $str_stop i32 (i32.const 3370))
 (data (i32.const 3380) "BSTART\00")  ;; 7
 (global $str_bstart i32 (i32.const 3380))

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
 (global $sym_cond i32 (i32.const 0x01c0))
 (global $sym_funarg i32 (i32.const 0x01c8))
 (global $sym_function i32 (i32.const 0x01d0))
 (global $sym_label i32 (i32.const 0x01d8))
 (global $sym_null i32 (i32.const 0x01e0))
 (global $sym_rplaca i32 (i32.const 0x01e8))
 (global $sym_rplacd i32 (i32.const 0x01f0))
 (global $sym_trace i32 (i32.const 0x01f8))
 (global $sym_get i32 (i32.const 0x0200))
 (global $sym_eval i32 (i32.const 0x0208))
 (global $sym_apply i32 (i32.const 0x0210))
 (global $sym_oblist i32 (i32.const 0x0218))
 (global $sym_charcount i32 (i32.const 0x0220))
 (global $sym_curchar i32 (i32.const 0x0228))
 (global $oblist_cell i32 (i32.const 0x0230))  ;; must not mark this object
 (global $charcount_cell i32 (i32.const 0x0238))
 (global $curchar_cell i32 (i32.const 0x0240))
 (global $sym_eof i32 (i32.const 0x0248))
 (global $sym_eor i32 (i32.const 0x0250))
 (global $sym_advance i32 (i32.const 0x0258))
 (global $sym_startread i32 (i32.const 0x0260))
 (global $sym_endread i32 (i32.const 0x0268))
 (global $sym_nconc i32 (i32.const 0x0270))
 (global $sym_and i32 (i32.const 0x0278))
 (global $sym_or i32 (i32.const 0x0280))
 (global $sym_logand i32 (i32.const 0x0288))
 (global $sym_logor i32 (i32.const 0x0290))
 (global $sym_logxor i32 (i32.const 0x0298))
 (global $sym_max i32 (i32.const 0x02a0))
 (global $sym_min i32 (i32.const 0x02a8))
 (global $sym_traceset i32 (i32.const 0x02b0))
 (global $sym_clearbuff i32 (i32.const 0x02b8))
 (global $sym_pack i32 (i32.const 0x02c0))
 (global $sym_mknam i32 (i32.const 0x02c8))
 (global $sym_intern i32 (i32.const 0x02d0))
 (global $sym_numob i32 (i32.const 0x02d8))
 (global $sym_unpack i32 (i32.const 0x02e0))
 (global $sym_liter i32 (i32.const 0x02e8))
 (global $sym_digit i32 (i32.const 0x02f0))
 (global $sym_opchar i32 (i32.const 0x02f8))
 (global $sym_dash i32 (i32.const 0x0300))
 (global $sym_append i32 (i32.const 0x0308))
 (global $sym_attrib i32 (i32.const 0x0310))
 (global $sym_copy i32 (i32.const 0x0318))
 (global $sym_not i32 (i32.const 0x0320))
 (global $sym_prop i32 (i32.const 0x0328))
 (global $sym_remprop i32 (i32.const 0x0330))
 (global $sym_pair i32 (i32.const 0x0338))
 (global $sym_sassoc i32 (i32.const 0x0340))
 (global $sym_subst i32 (i32.const 0x0348))
 (global $sym_sublis i32 (i32.const 0x0350))
 (global $sym_reverse i32 (i32.const 0x0358))
 (global $sym_member i32 (i32.const 0x0360))
 (global $sym_length i32 (i32.const 0x0368))
 (global $sym_efface i32 (i32.const 0x0370))
 (global $sym_maplist i32 (i32.const 0x0378))
 (global $sym_mapcon i32 (i32.const 0x0380))
 (global $sym_map i32 (i32.const 0x0388))
 (global $sym_search i32 (i32.const 0x0390))
 (global $sym_recip i32 (i32.const 0x0398))
 (global $sym_expt i32 (i32.const 0x03a0))
 (global $sym_fixp i32 (i32.const 0x03a8))
 (global $sym_floatp i32 (i32.const 0x03b0))
 (global $sym_leftshift i32 (i32.const 0x03b8))
 (global $sym_read i32 (i32.const 0x03c0))
 (global $sym_punch i32 (i32.const 0x03c8))
 (global $sym_gensym i32 (i32.const 0x03d0))
 (global $sym_remob i32 (i32.const 0x03d8))
 (global $sym_evlis i32 (i32.const 0x03e0))
 (global $sym_dump i32 (i32.const 0x03e8))
 (global $sym_error i32 (i32.const 0x03f0))
 (global $sym_count i32 (i32.const 0x03f8))
 (global $sym_uncount i32 (i32.const 0x0400))
 (global $sym_speak i32 (i32.const 0x0f08))
 (global $sym_errorset i32 (i32.const 0x0410))
 (global $sym_bwrite i32 (i32.const 0x0418))
 (global $sym_bdump i32 (i32.const 0x0420))
 (global $sym_loadwasm i32 (i32.const 0x0428))
 (global $sym_nextsubr i32 (i32.const 0x0430))
 (global $sym_fencode i32 (i32.const 0x0438))
 (global $sym_time i32 (i32.const 0x0440))
 (global $sym_vctag i32 (i32.const 0x0448))
 (global $sym_eval_enter_hook i32 (i32.const 0x0450))
 (global $sym_stop i32 (i32.const 0x0458))
 (global $sym_bstart i32 (i32.const 0x0460))
 (global $primitive_obj_end i32 (i32.const 0x0468))

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
 (data (i32.const 5290) "ENTER\00")  ;; 6
 (global $str_msg_trace_enter i32 (i32.const 5290))
 (data (i32.const 5300) "EXIT\00")  ;; 5
 (global $str_msg_trace_exit i32 (i32.const 5300))
 (data (i32.const 5310) "ADDRESS  CAR      CDR\00")  ;; 22
 (global $str_msg_dump_header i32 (i32.const 5310))
 (data (i32.const 5340) "A1: APPLIED ERROR\00")  ;; 18
 (global $str_err_error i32 (i32.const 5340))
 (data (i32.const 5360) "F1: CONS COUNTER\00")  ;; 17
 (global $str_err_counter i32 (i32.const 5360))
 (data (i32.const 5380) "TIME (MS): \00")  ;; 12
 (global $str_msg_time_ms i32 (i32.const 5380))
 (data (i32.const 5400) "GC: \00")  ;; 5
 (global $str_msg_gc_count i32 (i32.const 5400))

 (func $ilog (param $val i32)
       (if (i32.ge_s (global.get $debug_level) (i32.const 1))
           (call $log (local.get $val))))
 (func $ilogstr (param $val i32)
       (if (i32.ge_s (global.get $debug_level) (i32.const 1))
           (call $logstr (local.get $val))))

 (elem (i32.const 0) $getsp)  ;; v2i
 (elem (i32.const 1) $push)  ;; i2v
 (elem (i32.const 2) $pop)  ;; v2i
 (elem (i32.const 3) $drop)  ;; i2v
 (elem (i32.const 4) $car)  ;; i2i
 (elem (i32.const 5) $cdr)  ;; i2i
 (elem (i32.const 6) $cons)  ;; ii2i
 (elem (i32.const 7) $peek)  ;; v2i
 (elem (i32.const 8) $debugpush)  ;; i2v
 (elem (i32.const 9) $debugpop)  ;; v2i

 (elem (i32.const 10) $getAArgFInSubr)  ;; i2i
 (elem (i32.const 11) $getArgF1)  ;; i2i
 (elem (i32.const 12) $getArgF2)  ;; i2i
 (elem (i32.const 13) $getArgF3)  ;; i2i
 (elem (i32.const 14) $getArgF4)  ;; i2i
 (elem (i32.const 15) $getArgFN)  ;; ii2i

 (elem (i32.const 20) $subrCall)  ;; ii2i
 (elem (i32.const 21) $funcCall)  ;; ii2i
 (elem (i32.const 22) $createAlistFromStack)  ;; ii2i
 (elem (i32.const 23) $fsubrCall)  ;; i2i
 (elem (i32.const 24) $createFunarg)  ;; ii2i
 (elem (i32.const 25) $getVarInAlist)  ;; ii2i
 (elem (i32.const 26) $createLabelFunarg)  ;; iii2i
 (elem (i32.const 27) $apvalSet)  ;; ii2i
 (elem (i32.const 28) $setVarInAlist)  ;; ii2i
 (elem (i32.const 29) $createSubrStackFromFsubrStack)  ;; i2v

 (elem (i32.const 30) $setAArgFInSubr)  ;; ii2i
 (elem (i32.const 31) $setArgF1)  ;; ii2v
 (elem (i32.const 32) $setArgF2)  ;; ii2v
 (elem (i32.const 33) $setArgF3)  ;; ii2v
 (elem (i32.const 34) $setArgF4)  ;; ii2v
 (elem (i32.const 35) $setArgFN)  ;; iii2v

 (elem (i32.const 40) $cleanupSubrStackFromFsubrStack)  ;; i2v

 (elem (i32.const 99) $log)  ;; i2v

 (func $getsp (result i32)
       (global.get $sp))
 (func $push (param $val i32)
       (i32.store (global.get $sp) (local.get $val))
       (global.set $sp (i32.add (global.get $sp) (i32.const 4))))
 (func $pop (result i32)
      (global.set $sp (i32.sub (global.get $sp) (i32.const 4)))
      (i32.load (global.get $sp)))
 (func $drop (param i32))
 (func $peek (result i32)
      (i32.load (i32.sub (global.get $sp) (i32.const 4))))
 (func $debugpush (param $val i32)
       (call $log (i32.const 666000001))
       (call $log (local.get $val))
       (i32.store (global.get $sp) (local.get $val))
       (global.set $sp (i32.add (global.get $sp) (i32.const 4))))
 (func $debugpop (result i32)
       (call $log (i32.const 666000002))
       (call $log (i32.load (i32.sub (global.get $sp) (i32.const 4))))
      (global.set $sp (i32.sub (global.get $sp) (i32.const 4)))
      (i32.load (global.get $sp)))

 (func $int2fixnum (param $n i32) (result i32)
       (i32.add (i32.shl (local.get $n) (i32.const 2)) (i32.const 2)))
 (func $fixnum2int (param $n i32) (result i32)
       (i32.shr_s (local.get $n) (i32.const 2)))

 ;;; Returns whether obj is a fixnum.
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
 (func $caar (param $cell i32) (result i32)
       (call $car (call $car (local.get $cell))))
 (func $cadr (param $cell i32) (result i32)
       (call $car (call $cdr (local.get $cell))))
 (func $cdar (param $cell i32) (result i32)
       (call $cdr (call $car (local.get $cell))))
 (func $cddr (param $cell i32) (result i32)
       (call $cdr (call $cdr (local.get $cell))))
 (func $caddr (param $cell i32) (result i32)
       (call $car (call $cdr (call $cdr (local.get $cell)))))
 (func $cdddr (param $cell i32) (result i32)
       (call $cdr (call $cdr (call $cdr (local.get $cell)))))

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
            (local.set $ret (global.get $fp))
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
       (if (global.get $cons_counting)
           (global.set
            $cons_count (i32.add (global.get $cons_count) (i32.const 1))))
       (local.get $ret))

 (func $cons (param $a i32) (param $d i32) (result i32)
       (local $cell i32)
       (call $push (local.get $a))  ;; For GC (a)
       (call $push (local.get $d))  ;; For GC (a d)
       (local.set $cell (call $rawcons))
       (if (call $errorp (local.get $cell))
           (then
            (call $drop (call $pop))  ;; For GC (a)
            (call $drop (call $pop))  ;; For GC ()
            (return (local.get $cell))))
       (call $setcar (local.get $cell) (local.get $a))
       (call $setcdr (local.get $cell) (local.get $d))
       (call $drop (call $pop))  ;; For GC (a)
       (call $drop (call $pop))  ;; For GC ()
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

 ;;; Returns a list of name1 that contains only 1 character.
 (func $unpackn1 (param $n1 i32) (result i32)
       (local $name i32)
       (local $sym i32)
       (local $ret i32)
       ;; If n1 contains 0 character, return NIL.
       (if (i32.eqz (i32.and (local.get $n1) (i32.const 0x0000ff00)))
           (return (i32.const 0)))
       (local.set $name (call
                         $cons
                         (i32.and (local.get $n1) (i32.const 0x0000ffff))
                         (i32.const 0)))
       (call $push (local.get $name))  ;; For GC (name)
       (local.set $sym (call $makeSymFromName (local.get $name)))
       (call $drop (call $pop))  ;; For GC ()
       (local.set $ret (call $cons (local.get $sym) (i32.const 0)))
       ;; If n1 contains 1 character, return a cons cell.
       (if (i32.eqz (i32.and (local.get $n1) (i32.const 0x00ff0000)))
           (return (local.get $ret)))
       (call $push (local.get $ret))  ;; For GC (ret)
       (local.set $name (call
                         $cons
                         (i32.add
                          (i32.and (i32.shr_u (local.get $n1) (i32.const 8))
                                   (i32.const 0x0000ff00))
                          (i32.const 2))
                         (i32.const 0)))
       (call $push (local.get $name))  ;; For GC (ret name)
       (local.set $sym (call $makeSymFromName (local.get $name)))
       (call $drop (call $pop))  ;; For GC (ret)
       (call $drop (call $pop))  ;; For GC ()
       (local.set $ret (call $cons (local.get $sym) (local.get $ret)))
       ;; If n1 contains 2 characters, return 2 cons cells.
       (if (i32.eqz (i32.and (local.get $n1) (i32.const 0xff000000)))
           (return (call $nreverse (local.get $ret))))
       ;; Otherwise, return 3 cons cells.
       (call $push (local.get $ret))  ;; For GC (ret)
       (local.set $name (call
                         $cons
                         (i32.add
                          (i32.and (i32.shr_u (local.get $n1) (i32.const 16))
                                   (i32.const 0x0000ff00))
                          (i32.const 2))
                         (i32.const 0)))
       (call $push (local.get $name))  ;; For GC (ret name)
       (local.set $sym (call $makeSymFromName (local.get $name)))
       (call $drop (call $pop))  ;; For GC (ret)
       (call $drop (call $pop))  ;; For GC ()
       (local.set $ret (call $cons (local.get $sym) (local.get $ret)))
       (call $nreverse (local.get $ret)))

 ;;; Returns a list of fixnums representing packed characters.
 (func $makename (param $str i32) (result i32)
       (local $ret i32)
       (local $size i32)
       (local $cell i32)
       (local $cur i32)
       (local $name1 i32)
       (local.set $ret (i32.const 0))
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
                    (call $push (local.get $cell))  ;; For GC (cell)
                    (local.set $ret (local.get $cell)))
                   (else
                    (call $setcdr (local.get $cur) (local.get $cell))))
               (local.set $cur (local.get $cell))))
          (local.set $str (i32.add (local.get $str) (i32.const 3)))
          (br_if $loop (i32.eq (local.get $size) (i32.const 3))))
       (if (i32.ne (local.get $ret) (i32.const 0))
           (call $drop (call $pop)))  ;; For GC ()
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

 (func $printSpace
       (call $printChar (i32.const 32)))  ;; ' '

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

 (func $printErrorContent (param $err i32)
       (if (call $fixnump (call $cdr (local.get $err)))
           (call $printString (call $fixnum2int (call $cdr (local.get $err))))
           (if (call $symbolp (call $cdr (local.get $err)))
               (call $printSymbol (call $cdr (local.get $err)))
               (call $printString (global.get $str_err_generic)))))

 (func $printError (param $err i32)
       (call $printChar (i32.const 60))  ;; '<'
       (call $printErrorContent (local.get $err))
       (call $printChar (i32.const 62)))  ;; '>'

 (func $printErrorPrefix
       (call $printChar (i32.const 42))  ;; '*'
       (call $printChar (i32.const 42))  ;; '*'
       (call $printChar (i32.const 42))  ;; '*'
       (call $printChar (i32.const 32)))  ;; ' '

 (func $printErrorMsg (param $err i32)
       (call $printErrorPrefix)
       (call $printErrorContent (local.get $err)))

 (func $perr1 (param $err i32) (param $obj i32) (result i32)
       (if (global.get $suppress_error)
           (return (local.get $err)))
       (if (i32.eq (call $cdr (local.get $err))
                   (call $int2fixnum (global.get $str_err_error)))
           (then
            (call $printErrorPrefix))
           (else
            (call $printErrorMsg (local.get $err))
            (call $printChar (i32.const 32))  ;; ' '
            (call $printChar (i32.const 45))  ;; '-'
            (call $printChar (i32.const 32))))  ;; ' '
       (call $printObj (local.get $obj))
       (call $terprif)
       (global.set $st_level (global.get $st_max_level))
       (local.get $err))

 (func $perr2 (param $err i32) (param $obj1 i32) (param $obj2 i32) (result i32)
       (if (global.get $suppress_error)
           (return (local.get $err)))
       (if (i32.eq (call $cdr (local.get $err))
                   (call $int2fixnum (global.get $str_err_error)))
           (then
            (call $printErrorPrefix))
           (else
            (call $printErrorMsg (local.get $err))
            (call $printChar (i32.const 32))  ;; ' '
            (call $printChar (i32.const 45))  ;; '-'
            (call $printChar (i32.const 32))))  ;; ' '
       (call $printObj (local.get $obj1))
       (call $printChar (i32.const 32))  ;; ' '
       (call $printObj (local.get $obj2))
       (call $terprif)
       (global.set $st_level (global.get $st_max_level))
       (local.get $err))

 (func $maybePrintStackTrace (param $e i32)
       (if (global.get $suppress_error)
           (return))
       (if (i32.eqz (global.get $st_level))
           (return))
       (call $printErrorPrefix)
       (call $printObj (local.get $e))
       (call $terprif)
       (global.set $st_level (i32.sub (global.get $st_level) (i32.const 1))))

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

 ;; TODO: Create general-purpose printInteger
 (func $printFixnum05 (param $n i32)
       (local $m i32)
       (local $size i32)
       (local.set $n (call $fixnum2int (local.get $n)))
       (local.set $size (i32.const 5))
       (local.set $m (i32.const 1))
       (loop $fill_loop
          (i32.store8 (i32.add (global.get $printp)
                               (i32.sub (local.get $size) (local.get $m)))
                      (i32.add
                       (i32.const 48)  ;; '0'
                       (i32.rem_u (local.get $n) (i32.const 10))))
          (local.set $m (i32.add (local.get $m) (i32.const 1)))
          (local.set $n (i32.div_u (local.get $n) (i32.const 10)))
          (br_if $fill_loop (i32.le_s (local.get $m) (local.get $size))))
       (global.set $printp (i32.add (global.get $printp) (local.get $size)))
       (i32.store8 (global.get $printp) (i32.const 0)))
 (func $int2char (param $n i32) (result i32)
       (if (i32.and
            (i32.le_u (i32.const 0) (local.get $n))
            (i32.le_u (local.get $n) (i32.const 9)))
           (return (i32.add (i32.const 48) (local.get $n))))  ;; '0'
       (if (i32.and
            (i32.le_u (i32.const 0xa) (local.get $n))
            (i32.le_u (local.get $n) (i32.const 0xf)))
           (return (i32.add (i32.const 55) (local.get $n))))  ;; 'A'-10
       (i32.const 42))  ;; '*'
 (func $printHex08 (param $n i32)
       (local $m i32)
       (local $size i32)
       (local.set $size (i32.const 8))
       (local.set $m (i32.const 1))
       (loop $fill_loop
          (i32.store8 (i32.add (global.get $printp)
                               (i32.sub (local.get $size) (local.get $m)))
                      (call $int2char
                            (i32.rem_u (local.get $n) (i32.const 16))))
          (local.set $m (i32.add (local.get $m) (i32.const 1)))
          (local.set $n (i32.div_u (local.get $n) (i32.const 16)))
          (br_if $fill_loop (i32.le_s (local.get $m) (local.get $size))))
       (global.set $printp (i32.add (global.get $printp) (local.get $size)))
       (i32.store8 (global.get $printp) (i32.const 0)))
 (func $printByteAsChar (param $n i32)
       (if (i32.and (i32.le_u (i32.const 0x20) (local.get $n))  ;; ' '
                    (i32.le_u (local.get $n) (i32.const 0x7e)))  ;; '~'
           (call $printChar (local.get $n))
           (call $printChar (i32.const 46))))  ;; '.'
 (func $printWordAsChars (param $n i32)
       (call $printByteAsChar (i32.and (local.get $n) (i32.const 0xff)))
       (call $printByteAsChar (i32.and (i32.shr_u (local.get $n) (i32.const 8))
                                       (i32.const 0xff)))
       (call $printByteAsChar
             (i32.and (i32.shr_u (local.get $n) (i32.const 16))
                      (i32.const 0xff)))
       (call $printByteAsChar
             (i32.and (i32.shr_u (local.get $n) (i32.const 24))
                      (i32.const 0xff))))

 (func $prop (param $obj i32) (param $key i32) (result i32)
       (local.set $obj (call $cdr (local.get $obj)))
       (loop $loop
          (if (i32.eq (call $car (local.get $obj)) (local.get $key))
              (return (call $cdr (local.get $obj))))
          (local.set $obj (call $cdr (local.get $obj)))
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
            (call $setcdr
                  (local.get $obj)
                  (call $cons (local.get $key) (local.get $p)))))
       (call $setcar (local.get $p) (local.get $val)))

 (func $remprop (param $obj i32) (param $key i32)
       (loop $block
          (loop $loop
             (if (i32.eqz (local.get $obj)) (return))
             (if (i32.eqz (call $cdr (local.get $obj))) (return))
             (if (i32.eq (call $cadr (local.get $obj)) (local.get $key))
                 (call $setcdr
                       (local.get $obj) (call $cdddr (local.get $obj))))
             (local.set $obj (call $cdr (local.get $obj)))
             (br $loop))))

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

 ;;; Note that $nconc can modify a symbol when $lst is a symbol. It even
 ;;; happens even when $lst is NIL.
 (func $nconc (param $lst i32) (param $elm i32) (result i32)
       (local $ret i32)
       (local.set $ret (local.get $lst))
       (if (call $dwcellp (local.get $lst))
           (loop $loop
              (if (call $consp (call $cdr (local.get $lst)))
                  (then
                   (local.set $lst (call $cdr (local.get $lst)))
                   (br $loop)))))
       (if (call $consp (local.get $lst))
           (call $setcdr (local.get $lst) (local.get $elm)))
       (local.get $ret))

 (func $conc (param $lst i32) (result i32)
       (local $ret i32)
       (if (call $errorp (local.get $lst))
           (return (local.get $lst)))
       (if (i32.eqz (local.get $lst))
           (return (i32.const 0)))
       (if (i32.eqz (call $cdr (local.get $lst)))
           (return (call $car (local.get $lst))))
       (local.set $ret (call $car (local.get $lst)))
       (local.set $lst (call $cdr (local.get $lst)))
       (loop $loop
          (if (i32.eqz (local.get $lst))
              (return (local.get $ret)))
          (if (i32.eqz (local.get $ret))
              (local.set $ret (call $car (local.get $lst)))
              (local.set
               $ret
               (call $nconc (local.get $ret) (call $car (local.get $lst)))))
          (local.set $lst (call $cdr (local.get $lst)))
          (br $loop))
       (i32.const 0))

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
       (call $push (local.get $e1))  ;; For GC (e1)
       (call $push (local.get $e2))  ;; For GC (e1 e2)
       (local.set $tmp (call $cons (local.get $e2) (i32.const 0)))
       (local.set $tmp (call $cons (local.get $e1) (local.get $tmp)))
       (call $drop (call $pop))  ;; For GC (e1)
       (call $drop (call $pop))  ;; For GC ()
       (local.get $tmp))

 (func $list3 (param $e1 i32) (param $e2 i32) (param $e3 i32) (result i32)
       (local $tmp i32)
       (call $push (local.get $e1))  ;; For GC (e1)
       (local.set $tmp (call $list2 (local.get $e2) (local.get $e3)))
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

 (func $strcpy (param $dst i32) (param $src i32)
       (local $c i32)
       (loop $loop
          (local.set $c (i32.load8_u (local.get $src)))
          (i32.store8 (local.get $dst) (local.get $c))
          (if (i32.eqz (local.get $c))
              (return))
          (local.set $src (i32.add (local.get $src) (i32.const 1)))
          (local.set $dst (i32.add (local.get $dst) (i32.const 1)))
          (br $loop)))

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

 ;;; Makes a new symbol from BOFFO
 (func $makeNewSym (result i32)
       (local $sym i32)
       (local $cell i32)
       (local.set $sym (call $cons (global.get $tag_symbol) (i32.const 0)))
       (call $push (local.get $sym))  ;; For GC (sym)
       (local.set $cell (call $makename (global.get $boffo)))
       (call $setcdr (local.get $sym) (local.get $cell))  ;; For GC
       (local.set $cell (call $cons (local.get $cell) (i32.const 0)))
       (call $setcdr (local.get $sym) (local.get $cell))  ;; For GC
       (local.set $cell (call $cons (global.get $sym_pname) (local.get $cell)))
       (call $setcdr (local.get $sym) (local.get $cell))
       (call $drop (call $pop))  ;; For GC ()
       (call $pushToOblist (local.get $sym))
       (local.get $sym))

 ;;; Returns an existing symbol or makes a symbol from BOFFO.
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

 ;;; Returns a symbol from name.
 (func $makeSymFromName (param $name i32) (result i32)
       (local $cell i32)
       (local $sym i32)
       (local.set $cell (global.get $oblist))
       (block $block
         (loop $loop
            (local.set $sym (call $car (local.get $cell)))
            (if (call $equal
                      (call $get (local.get $sym) (global.get $sym_pname))
                      (local.get $name))
                (br $block))
            (local.set $cell (call $cdr (local.get $cell)))
            (br_if $loop (i32.ne (local.get $cell) (i32.const 0)))))
       (if (i32.eqz (local.get $cell))
           (then
            (local.set
             $sym (call $cons (global.get $tag_symbol) (i32.const 0)))
            (call $push (local.get $sym))  ;; For GC (sym)
            (local.set $cell (call $cons (local.get $name) (i32.const 0)))
            (call $setcdr (local.get $sym) (local.get $cell))  ;; For GC
            (local.set
             $cell (call $cons (global.get $sym_pname) (local.get $cell)))
            (call $setcdr (local.get $sym) (local.get $cell))
            (call $drop (call $pop))  ;; For GC ()
            (call $pushToOblist (local.get $sym))))
       (local.get $sym))

 (func $makeNum (param $n i32) (result i32)
       (call $int2fixnum (local.get $n)))

 (func $bfseek (param $n i32)
       (global.set $boffop (i32.add (global.get $boffop) (local.get $n))))
 (func $peekBoffoN (param $n i32) (result i32)
       (i32.load8_u (i32.add (global.get $boffop) (local.get $n))))
 (func $peekBoffo (result i32)
       (call $peekBoffoN (i32.const 0)))
 (func $readBoffo (result i32)
       (local $c i32)
       (local.set $c (call $peekBoffo))
       (if (i32.ne (local.get $c) (i32.const 0))
           (call $bfseek (i32.const 1)))
       (local.get $c))

 ;;; Makes a number of symbol from BOFFO.
 (func $makeNumOrSym (result i32)
       (local $c i32)
       (local $sign i32)
       (local $base i32)
       (local $is_num i32)
       (local $num i32)
       (local $ret i32)
       (global.set $boffop (global.get $boffo))
       (local.set $sign (i32.const 1))
       (local.set $base (i32.const 10))
       (local.set $is_num (i32.const 0))
       (local.set $num (i32.const 0))
       (local.set $c (call $peekBoffo))
       (if (i32.eq (local.get $c) (i32.const 45))  ;; '-'
           (then
            (local.set $sign (i32.const -1))
            (call $bfseek (i32.const 1))
            (local.set $c (call $peekBoffo))))
       (if (i32.or (i32.eq (local.get $c) (i32.const 48))  ;; '0'
                   (i32.eq (local.get $c) (i32.const 35)))  ;; '#'
           (if (i32.eq (call $peekBoffoN (i32.const 1))
                       (i32.const 88))  ;; 'X'
               (then
                (local.set $base (i32.const 16))
                (call $bfseek (i32.const 2))
                (local.set $c (call $peekBoffo)))))
       (block $block
         (loop $loop
            (br_if $block (i32.eqz (local.get $c)))
            (if (i32.and  ;; '0' <= c && c <= '9'
                 (i32.le_u (i32.const 48) (local.get $c))
                 (i32.le_u (local.get $c) (i32.const 57)))
                (then
                 (local.set $is_num (i32.const 1))
                 (local.set
                  $num
                  (i32.add (i32.mul (local.get $num) (local.get $base))
                           (i32.sub (local.get $c) (i32.const 48)))))
                (else
                 (if (i32.and
                      (i32.eq (local.get $base) (i32.const 16))
                      (i32.and  ;; 'A' <= c && c <= 'F'
                       (i32.le_u (i32.const 65) (local.get $c))
                       (i32.le_u (local.get $c) (i32.const 70))))
                     (then
                      (local.set $is_num (i32.const 1))
                      (local.set
                       $num
                       (i32.add (i32.mul (local.get $num) (local.get $base))
                                (i32.sub (local.get $c) (i32.const 55)))))
                     (else
                      (local.set $is_num (i32.const 0))
                      (br $block)))))
            (call $bfseek (i32.const 1))
            (local.set $c (call $peekBoffo))
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
 (global $ce_apply i32 (i32.const 3))

 ;; Returns (err n . args)
 (func $makeCatchableError (param $n i32) (param $args i32) (result i32)
       (local $ret i32)
       (local.set
        $ret (call $cons (call $int2fixnum (local.get $n)) (local.get $args)))
       (local.set $ret (call $cons (global.get $tag_error) (local.get $ret)))
       (local.get $ret))
 (func $catchablep (param $obj i32) (param $n i32) (result i32)
       (if (call $errorp (local.get $obj))
           (if (call $consp (call $cdr (local.get $obj)))
               (return (i32.eq (call $cadr (local.get $obj))
                               (call $int2fixnum (local.get $n))))))
       (i32.const 0))
 (func $getCEValue (param $obj i32) (result i32)
       (call $cddr (local.get $obj)))

 ;;; Sets `readp` to start reading a string.
 (func $rdset (param $n i32)
       (global.set $read_start (local.get $n))
       (global.set $readp (local.get $n)))
 ;;; Increments `readp` by `n`.
 (func $rdseek (param $n i32)
       (global.set $readp (i32.add (global.get $readp) (local.get $n))))
 ;;; Returns the N th character from `readp`.
 (func $peekCharN (param $n i32) (result i32)
       (i32.load8_u (i32.add (global.get $readp) (local.get $n))))
 ;;; Returns the first character from `readp`.
 (func $peekChar (result i32)
       (call $peekCharN (i32.const 0)))
 ;;; Returns the first character from `readp` and increment `readp`.
 ;;; If `readp` points to '\00', `readp` doesn't change.
 (func $readChar (result i32)
       (local $c i32)
       (local.set $c (call $peekChar))
       (if (i32.ne (local.get $c) (i32.const 0))
           (call $rdseek (i32.const 1)))
       (local.get $c))

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

 ;;; Skips spaces in `readp`.
 (func $skipSpaces
       (local $c i32)
       (loop $loop
          (local.set $c (call $peekChar))
          (if (i32.eqz (local.get $c))
              (return))
          (if (call $isSpace (local.get $c))
              (then
               (call $rdseek (i32.const 1))
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
             (local.set $c (call $peekChar))
             (if (i32.eqz (local.get $c))
                 (br $block))
             ;; If the first character is '$'
             (if (i32.and (i32.eq (local.get $c) (i32.const 36))
                          (i32.eq (global.get $boffop)
                                  (global.get $boffo)))
                 ;; and the second character is also '$'
                 (if (i32.eq (call $peekCharN (i32.const 1))
                             (i32.const 36))
                     (return (call $readRawSymbol))))
             ;; Read until delimiters
             (if (call $isDelimiter (local.get $c))
                 (br $block))
             (local.set $c (call $toUpper (local.get $c)))
             (i32.store8 (global.get $boffop) (local.get $c))
             (global.set $boffop (i32.add (global.get $boffop) (i32.const 1)))
             (call $rdseek (i32.const 1))
             (br $loop)))
       (i32.store8 (global.get $boffop) (i32.const 0))
       (call $makeNumOrSym))

 ;;; `readp` must point to the first '$'
 (func $readRawSymbol (result i32)
       (local $c i32)
       (local $s i32)
       (call $rdseek (i32.const 2))  ;; Skip $$
       (local.set $s (call $readChar))
       (if (i32.eqz (local.get $s))
           (return (call $makeStrError (global.get $str_err_eof))))
       (block $block
          (loop $loop
             (local.set $c (call $readChar))
             (if (i32.eqz (local.get $c))
                 (return (call $makeStrError (global.get $str_err_eof))))
             (if (i32.eq (local.get $c) (local.get $s))
                 (br $block))
             (i32.store8 (global.get $boffop) (local.get $c))
             (global.set $boffop (i32.add (global.get $boffop) (i32.const 1)))
             (br $loop)))
       (if (i32.eq (global.get $boffo) (global.get $boffop))
           ;; TODO: Support the "empty" symbol.
           (return (call $makeStrError (global.get $str_err_eof))))
       (i32.store8 (global.get $boffop) (i32.const 0))
       (call $makeSym))

 (func $readList (result i32)
       (local $c i32)
       (local $ret i32)
       (local $elm i32)
       (local.set $ret (i32.const 0))
       (local.set $elm (i32.const 0))
       (block $block
         (loop $loop
            (call $skipSpaces)
            (local.set $c (call $peekChar))
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
                 (local.set $c (call $peekChar))
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
                 (local.set $c (call $peekChar))
                 (if (i32.ne (local.get $c) (i32.const 41))  ;; Not RPar
                     (then
                      (local.set
                       $ret
                       (call $makeStrError (global.get $str_err_unexpected)))
                      (br $block)))
                 (br $block)))  ;; valid dotted list
            ;; Proper list
            (call $drop (call $pop))  ;; For GC ()
            (local.set $ret (call $cons (local.get $elm) (local.get $ret)))
            (local.set $elm (i32.const 0))
            (br $loop)))
       (if (call $errorp (local.get $ret))
           (return (local.get $ret)))
       (call $rdseek (i32.const 1))
       (local.set $ret (call $nreverse (local.get $ret)))
       (if (i32.ne (local.get $elm) (i32.const 0))  ;; dotted list
           (local.set $ret (call $nconc (local.get $ret) (local.get $elm))))
       (local.get $ret))

 ;;; Reads an expression from `readp`.
 (func $read (result i32)
       (local $c i32)
       (local $ret i32)
       (call $skipSpaces)
       (local.set $c (call $peekChar))
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
              (call $rdseek (i32.const 1))
              (local.set $ret (call $readList))
              (br $block)))
         (if (i32.eq (local.get $c) (i32.const 39))  ;; Quote
             (then
              (call $rdseek (i32.const 1))
              (local.set $ret (call $read))
              (if (call $errorp (local.get $ret))
                  (br $block))
              (local.set $ret (call $cons (local.get $ret) (i32.const 0)))
              (local.set $ret (call $cons
                                    (global.get $sym_quote)
                                    (local.get $ret)))
              (br $block)))
         (local.set $ret (call $readAtom)))
       (local.get $ret))

 (func $pushToOblist (param $sym i32)
       (global.set $oblist (call $cons (local.get $sym) (global.get $oblist)))
       (call $setcar (global.get $oblist_cell) (global.get $oblist)))

 (func $removeFromOblist (param $sym i32) (result i32)
       (local $p i32)
       (if (i32.eq (call $car (global.get $oblist)) (local.get $sym))
           (then
            (global.set $oblist (call $cdr (global.get $oblist)))
            (call $setcar (global.get $oblist_cell) (global.get $oblist))
            (return (local.get $sym))))
       (local.set $p (global.get $oblist))
       (loop $loop
          (if (i32.eqz (call $cdr (local.get $p)))
              (return (i32.const 0)))
          (if (i32.eq (call $cadr (local.get $p)) (local.get $sym))
              (then
               (call $setcdr (local.get $p) (call $cddr (local.get $p)))
               (return (local.get $sym))))
          (local.set $p (call $cdr (local.get $p)))
          (br $loop))
       (i32.const 0))

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
            (call $drop (call $pop))  ;; For GC ()
            (if (call $errorp (local.get $elm))
                (return (local.get $elm)))
            (local.set $ret (call $cons (local.get $elm) (local.get $ret)))
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

;;; Pushes 4 elements without evaluation
 (func $argspush (param $lst i32)
       (call $push (call $safecar (local.get $lst)))  ;; 1st
       (local.set $lst (call $safecdr (local.get $lst)))
       (call $push (call $safecar (local.get $lst)))  ;; 2nd
       (local.set $lst (call $safecdr (local.get $lst)))
       (call $push (call $safecar (local.get $lst)))  ;; 3rd
       (call $push (call $safecdr (local.get $lst))))  ;; rest

 (func $evpop
       (global.set $sp (i32.sub (global.get $sp) (i32.const 16))))

 ;;; For compiler
 ;;; Compiler stack: (..., a, arg1, arg2, arg3, ..., argN)  [N=narg]
 (func $adjustSubrCallStack (param $narg i32)
       (local $arg4 i32)
       (if (i32.lt_u (local.get $narg) (i32.const 4))
           (loop $pushlp
              (if (i32.eq (local.get $narg) (i32.const 4))
                  (return))
              (call $push (i32.const 0))
              (local.set $narg (i32.add (local.get $narg) (i32.const 1)))
              (br $pushlp)))
       (local.set $arg4 (i32.const 0))
       (call $push (local.get $arg4))
       (loop $poplp
          (if (i32.eq (local.get $narg) (i32.const 3))
              (return))
          (local.set $arg4 (call $pop))
          (local.set $arg4 (call $cons (local.get $arg4) (call $pop)))
          (call $push (local.get $arg4))
          (local.set $narg (i32.sub (local.get $narg) (i32.const 1)))
          (br $poplp)))
 (func $createAlistFromStack (param $fmp i32) (param $farg i32) (result i32)
       (local $aarg i32)
       (local $ret i32)
       (local.set $aarg (call $getArgFRest (local.get $fmp)))
       (local.set $aarg (call $cons (call $getArgF3 (local.get $fmp))
                              (local.get $aarg)))
       (local.set $aarg (call $cons (call $getArgF2 (local.get $fmp))
                              (local.get $aarg)))
       (local.set $aarg (call $cons (call $getArgF1 (local.get $fmp))
                              (local.get $aarg)))
       (call $push (local.get $aarg))  ;; For GC (aarg)
       (call $push (local.get $farg))  ;; For GC (aarg farg)
       (local.set
        $ret
        (call $pairlisWithVC (local.get $farg) (local.get $aarg)
              (call $getAArgFInSubr (local.get $fmp))))
       (call $drop (call $pop))  ;; For GC (aarg)
       (call $drop (call $pop))  ;; For GC ()
       (local.get $ret))
 ;;; Returns NIL if all arguments are not errors.
 ;;; If errors are found, removes all arguments and alist from stack, and
 ;;; returns the found error.
 (func $checkFuncCallStack (param $narg i32) (result i32)
       (local $ret i32)
       (local $nelm i32)
       (local.set $nelm (i32.add (local.get $narg) (i32.const 1)))
       (loop $loop
          (if (i32.eqz (local.get $narg))
              (return (i32.const 0)))
          (local.set
           $ret
           (i32.load (i32.sub (global.get $sp)
                              (i32.mul (local.get $narg) (i32.const 4)))))
          (if (i32.ne (call $errorp (local.get $ret)) (i32.const 0))
              (then
               (global.set
                $sp (i32.sub (global.get $sp)
                             (i32.mul (local.get $nelm) (i32.const 4))))
               (return (local.get $ret))))
          (local.set $narg (i32.sub (local.get $narg) (i32.const 1)))
          (br $loop))
       (i32.const 0))
 (func $subrCall (param $idx i32) (param $narg i32) (result i32)
       (local $ret i32)
       (local.set $ret (call $checkFuncCallStack (local.get $narg)))
       (if (i32.ne (local.get $ret) (i32.const 0))
           (return (local.get $ret)))
       (call $adjustSubrCallStack (local.get $narg))
       (local.set
        $ret
        (call_indirect
         (type $subr_type)
         (local.get $idx)))  ;; This is not a fixnum.
       (call $evpop)
       (call $drop (call $pop))  ;; Pop alist
       (local.get $ret))
 (func $exprCall (param $fn i32) (param $narg i32) (result i32)
       (local $aarg i32)
       (local $alist i32)
       (local.set $aarg (call $checkFuncCallStack (local.get $narg)))
       (if (i32.ne (local.get $aarg) (i32.const 0))
           (return (local.get $aarg)))
       (local.set $aarg (i32.const 0))
       (block $block
         (loop $loop
            (if (i32.eqz (local.get $narg))
                (br $block))
            (local.set $aarg (call $cons (call $pop) (local.get $aarg)))
            (local.set $narg (i32.sub (local.get $narg) (i32.const 1)))
            (br $loop)))
       (local.set $alist (call $pop))
       (call
        $eval
        (call $car (call $cddr (local.get $fn)))
        ;; TODO: make sure $fn is protected from GC
        (call
         $pairlis
         (call $cadr (local.get $fn))
         (local.get $aarg)
         (local.get $alist))))
 (func $funcCall (param $fn i32) (param $narg i32) (result i32)
       (local $a i32)
       (local $tmp i32)
       (local $fn_lookup i32)
       (local.set $fn_lookup (i32.const 0))
       (loop $loop
          ;; Check if it's EXPR
          (local.set $tmp (call $get (local.get $fn) (global.get $sym_expr)))
          (if (i32.ne (local.get $tmp) (i32.const 0))
              (return (call $exprCall (local.get $tmp) (local.get $narg))))
          ;; Check if it's SUBR
          (local.set $tmp (call $get (local.get $fn) (global.get $sym_subr)))
          (if (i32.ne (local.get $tmp) (i32.const 0))
              (return (call $subrCall
                            (call $fixnum2int (call $car (local.get $tmp)))
                            (local.get $narg))))
          ;; Check if it's (LAMBDA ...)
          (if (i32.eq (call $safecar (local.get $fn)) (global.get $sym_lambda))
              (return (call $exprCall (local.get $fn) (local.get $narg))))
          ;; Check if it's (SUBR IDX ...)
          (if (i32.eq (call $safecar (local.get $fn)) (global.get $sym_subr))
              (return (call $subrCall
                            (call $fixnum2int (call $cadr (local.get $fn)))
                            (local.get $narg))))
          ;; Check if it's (FUNARG ...)
          (if (i32.eq (call $safecar (local.get $fn)) (global.get $sym_funarg))
              (then
               ;; Replace $a in stack.
               (i32.store
                (i32.sub
                 (global.get $sp)
                 (i32.mul (i32.add (local.get $narg) (i32.const 1))
                          (i32.const 4)))
                (call $car (call $cddr (local.get $fn))))
               (local.set $fn (call $cadr (local.get $fn)))
               (br $loop)))
          ;; Look up $fn from alist
          (if (i32.and (call $symbolp (local.get $fn))
                       (i32.eqz (local.get $fn_lookup)))
              (then
               (local.set $fn_lookup (i32.const 1))
               (local.set
                $a
                (i32.load
                 (i32.sub
                  (global.get $sp)
                  (i32.mul (i32.add (local.get $narg) (i32.const 1))
                           (i32.const 4)))))
               (local.set $tmp (call $assoc (local.get $fn) (local.get $a)))
               (if (i32.ne (local.get $tmp) (i32.const 0))
                   (then
                    (local.set $fn (call $cdr (local.get $tmp)))
                    (br $loop))))))
       ;; Error: $fn is not a function
       ;; Remove arguments and alist from stack
       (global.set
        $sp (i32.sub (global.get $sp)
                     (i32.mul (i32.add (local.get $narg) (i32.const 1))
                              (i32.const 4))))
       (call $perr1
             (call $makeStrError (global.get $str_err_nodef))
             (local.get $fn)))
 ;;; FSUBR Stack: (..., e, a)
 (func $fsubrCall (param $idx i32) (result i32)
       (local $ret i32)
       (local.set
        $ret
        (call_indirect
         (type $fsubr_type)
         (local.get $idx)))  ;; This is not a fixnum.
       ;; Check whether the return value should be evaluated
       (if (i32.ne (call $pop) (i32.const 0))
           (local.set $ret (call $eval (call $getEArg) (call $getAArg))))
       (call $drop (call $pop))  ;; For GC (e)
       (call $drop (call $pop))  ;; For GC ()
       (local.get $ret))

 (func $createFunarg (param $a i32) (param $fn i32) (result i32)
       (call $list3 (global.get $sym_funarg) (local.get $fn) (local.get $a)))

 (func $createLabelFunarg (param $a i32) (param $fn i32) (param $nm i32)
       (result i32)
       (local $tmp i32)
       (call $push (local.get $a))  ;; For GC (a)
       (local.set $tmp (call $cons (local.get $nm) (local.get $fn)))
       (local.set $tmp (call $cons (local.get $tmp) (local.get $a)))
       (call $drop (call $pop))  ;; For GC ()
       (call $list3 (global.get $sym_funarg) (local.get $fn) (local.get $tmp)))

 (func $getVarInAlist (param $var i32) (param $alist i32) (result i32)
       (local $tmp i32)
       (local.set $tmp (call $assoc (local.get $var) (local.get $alist)))
       (if (i32.ne (local.get $tmp) (i32.const 0))
           (return (call $cdr (local.get $tmp))))
       (call $perr1
             (call $makeStrError (global.get $str_err_unbound))
             (local.get $var)))

 (func $setVarInAlist (param $var i32) (param $val i32) (param $alist i32)
       (result i32)
       (local $tmp i32)
       (local.set $tmp (call $assoc (local.get $var) (local.get $alist)))
       (if (i32.ne (local.get $tmp) (i32.const 0))
           (then
            (call $setcdr (local.get $tmp) (local.get $val))
            (return (local.get $val))))
       (call $perr1
             (call $makeStrError (global.get $str_err_unbound))
             (local.get $var)))

 (func $apvalSet (param $obj i32) (param $val i32) (result i32)
       (call $push (local.get $obj))  ;; For GC (obj)
       (local.set $val (call $cons (local.get $val) (i32.const 0)))
       (call $drop (call $pop))  ;; For GC ()
       (call $putprop
             (local.get $obj) (local.get $val) (global.get $sym_apval))
       (local.get $val))

 (func $createSubrStackFromFsubrStack (param $fmp i32)
       (call $push (call $getAArgF (local.get $fmp)))  ;; arg a
       (call $push (call $cdr (call $getEArgF (local.get $fmp))))  ;; arg 1
       (call $push (call $getAArgF (local.get $fmp)))  ;; arg 2
       (call $push (i32.const 0))  ;; arg 3
       (call $push (i32.const 0)))  ;; arg 4

 (func $cleanupSubrStackFromFsubrStack (param $fmp i32)
       (if (i32.ne (local.get $fmp) (global.get $sp))
           (then
            (call $log (i32.const 555000001))
            (call $log (global.get $sp))
            (call $log (local.get $fmp))
            (unreachable)))
       (global.set $sp (i32.sub (global.get $sp) (i32.const 20))))

 ;;; All arguments must be protected from GC
 (func $pairlis (param $x i32) (param $y i32) (param $z i32) (result i32)
       (local $tmp i32)
       (block $block
         (loop $loop
            (br_if $block (i32.eqz (call $consp (local.get $x))))
            (call $push (local.get $z))  ;; For GC (z)
            (local.set $tmp (call $cons
                                  (call $car (local.get $x))
                                  (call $safecar (local.get $y))))
            (call $drop (call $pop))  ;; For GC ()
            (local.set $z (call $cons (local.get $tmp) (local.get $z)))
            (local.set $x (call $cdr (local.get $x)))
            (local.set $y (call $safecdr (local.get $y)))
            (br $loop)))
       (local.get $z))

 ;;; All arguments must be protected from GC
 ;;; This function should be called from compiled functions.
 ;;; This function must not called from compiler itself because the code using
 ;;; `c::vctag` will be broken.
 (func $pairlisWithVC (param $x i32) (param $y i32) (param $z i32) (result i32)
       (local $tmp i32)
       (block $block
         (loop $loop
            (br_if $block (i32.eqz (call $consp (local.get $x))))
            (call $push (local.get $z))  ;; For GC (z)
            (if (i32.and
                 (call $consp (call $safecar (local.get $y)))
                 (i32.eq (call $safecar (call $safecar (local.get $y)))
                         (global.get $sym_vctag)))
                (local.set $tmp (call $cdar (local.get $y)))
                (local.set $tmp (call $cons
                                      (call $car (local.get $x))
                                      (call $safecar (local.get $y)))))
            (call $drop (call $pop))  ;; For GC ()
            (local.set $z (call $cons (local.get $tmp) (local.get $z)))
            (local.set $x (call $cdr (local.get $x)))
            (local.set $y (call $safecdr (local.get $y)))
            (br $loop)))
       (local.get $z))

 (func
  $eval (param $e i32) (param $a i32) (result i32)
  (local $ret i32)
  (local $tmp i32)
  (local $fn_lookup i32)
  (local $tracing i32)  ;; contains a symbol when tracing
  (local $applying i32)  ;; whether a SUBR APPLY is called
  (local $fn i32)
  (local $args i32)
  (local.set $ret (i32.const 0))
  (local.set $tracing (i32.const 0))
  (call $ilog (i32.const 11111))
  (call $ilog (global.get $sp))
  (call $push (local.get $e))  ;; For GC (e)
  (call $push (local.get $a))  ;; For GC (e a)
  (block $evalbk
    (loop $evallp
       (if (i32.ge_s (global.get $debug_level) (i32.const 2))
           (then
            (call $printObj (local.get $e))
            (call $terprif)))
       ;; Check cons_count. Ideally this should be checked everywhere cons is
       ;; called but it's too much. So check it only here as a workaround.
       (if (i32.and
            (global.get $cons_counting)
            (i32.gt_u (global.get $cons_count) (global.get $cons_limit)))
           (then
            (global.set $cons_counting (i32.const 0))
            (local.set
             $ret (call $perr1
                        (call $makeStrError (global.get $str_err_counter))
                        (call $int2fixnum (global.get $cons_count))))
            (br $evalbk)))
       ;; Evaluate an atom (except symbol)
       (if (i32.eqz (local.get $e))
           (then (local.set $ret (i32.const 0))
                 (br $evalbk)))
       (local.set $applying (i32.const 0))
       (if (call $catchablep (local.get $e) (global.get $ce_apply))
           (then
            (local.set $e (call $getCEValue (local.get $e)))
            (i32.store (i32.sub (global.get $sp) (i32.const 8))
                       (local.get $e))  ;; replace `e` in stack
            (local.set $applying (i32.const 1))))
       (if (call $errorp (local.get $e))
           (then (local.set $ret (local.get $e))
                 (br $evalbk)))
       (if (call $numberp (local.get $e))
           (then (local.set $ret (local.get $e))
                 (br $evalbk)))
       ;; Evaluate a symbol
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
            (local.set
             $ret (call $perr1
                        (call $makeStrError (global.get $str_err_unbound))
                        (local.get $e)))
            (br $evalbk)))
       (if (i32.eqz (call $consp (local.get $e)))  ;; Unknown object
           (then (local.set
                  $ret
                  (call $perr1
                        (call $makeStrError (global.get $str_err_generic))
                        (local.get $e)))
                 (br $evalbk)))
       ;; Evaluate a compound expression
       (local.set $fn (call $car (local.get $e)))
       (local.set $args (call $cdr (local.get $e)))
       (local.set $fn_lookup (i32.const 0))
       (loop $complp
          ;; Check if fn is FEXPR
          (local.set $tmp
                     (call $get (local.get $fn) (global.get $sym_fexpr)))
          (if (i32.ne (local.get $tmp) (i32.const 0))
              (then
               (local.set $args (call $list2 (local.get $args) (local.get $a)))
               ;; HACK: replace `a` in stack with (args a) for GC.
               ;; It's a bit scary but safe because FSUBR (which uses `a` in
               ;; stack) isn't directly called in this case.
               (i32.store (i32.sub (global.get $sp) (i32.const 4))
                          (local.get $args))  ;; replace `a` in stack
               ;; Disable argument evaluation.
               (local.set $applying (i32.const 1))
               ;; The new fn should be (LAMBDA ...).
               (local.set $fn (local.get $tmp))))
          ;; Check if fn is EXPR
          (local.set $tmp
                     (call $get (local.get $fn) (global.get $sym_expr)))
          (if (i32.ne (local.get $tmp) (i32.const 0))
              (then
               (if (call $get (local.get $fn) (global.get $sym_trace))
                    (local.set $tracing (local.get $fn)))
               (if (call $get (local.get $fn) (global.get $sym_traceset))
                    (global.set $traceset_env (global.get $sym_tstar)))
               (local.set $fn (local.get $tmp))))
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
          ;; Check if fn is SUBR
          (local.set $tmp
                     (call $get (local.get $fn) (global.get $sym_subr)))
          ;; Special handling for EVAL
          (if (i32.eq (call $car (local.get $tmp))
                      (call $int2fixnum (global.get $idx_eval)))
              (then
               (if (i32.eqz (local.get $applying))
                   (local.set
                    $e (call $evlis (local.get $args) (local.get $a))))
               (local.set $a (call $safecar (call $cdr (local.get $e))))
               (local.set $e (call $car (local.get $e)))
               (i32.store (i32.sub (global.get $sp) (i32.const 4))
                          (local.get $a))  ;; replace `a` in stack
               (i32.store (i32.sub (global.get $sp) (i32.const 8))
                          (local.get $e))  ;; replace `e` in stack
               (br $evallp)))
          ;; Special handling for APPLY
          (if (i32.eq (call $car (local.get $tmp))
                      (call $int2fixnum (global.get $idx_apply)))
              (then
               (if (i32.eqz (local.get $applying))
                   (then
                    (local.set
                     $e (call $evlis (local.get $args) (local.get $a)))
                    (if (call $errorp (local.get $e))
                        (then (local.set $ret (local.get $e))
                              (br $evalbk)))
                    (local.set $a (call $safecar (call $cddr (local.get $e))))
                    (i32.store (i32.sub (global.get $sp) (i32.const 4))
                               (local.get $a))  ;; replace `a` in stack
                    ;; Set `e` like (fn . args) from (fn args env)
                    (call $setcdr (local.get $e) (call $cadr (local.get $e)))
                    (i32.store (i32.sub (global.get $sp) (i32.const 8))
                               (local.get $e))  ;; replace `e` in stack
                    ;; Set `applying` not to evaluate args again
                    (local.set $applying (i32.const 1))
                    (local.set $fn (call $car (local.get $e)))
                    (local.set $args (call $cdr (local.get $e))))
                   (else
                    (local.set $fn (call $car (local.get $args)))
                    (local.set $args (call $cadr (local.get $args)))))
               (br $complp)))
          ;; Normal SUBR
          (if (i32.ne (local.get $tmp) (i32.const 0))
              (then
               (if (i32.eqz (local.get $applying))
                   (local.set
                    $ret (call $evpush (local.get $args) (local.get $a)))
                   (call $argspush (local.get $args)))
               ;; Call the SUBR only if the arguments don't contain errors.
               (if (i32.eqz (local.get $ret))
                   (local.set
                    $ret
                    (call_indirect
                     (type $subr_type)
                     (call $fixnum2int (call $car (local.get $tmp))))))
               (call $evpop)
               (br $evalbk)))
          ;; Don't lookup fn from alist twice (to avoid infinite loop)
          (if (i32.and (call $symbolp (local.get $fn))
                       (i32.ne (local.get $fn_lookup) (i32.const 0)))
              (then (local.set
                     $ret
                     (call $perr1
                           (call $makeStrError (global.get $str_err_nodef))
                           (local.get $fn)))
                         (br $evalbk)))
          ;; Find fn from alist if fn is a symbol
          (if (call $symbolp (local.get $fn))
              (then
               (local.set $fn_lookup (i32.const 1))
               (local.set $tmp (call $assoc (local.get $fn) (local.get $a)))
               (if (i32.eqz (local.get $tmp))
                   (then
                    (local.set
                     $ret
                     (call $perr1
                           (call $makeStrError (global.get $str_err_nodef))
                           (local.get $fn)))
                    (br $evalbk)))
               (local.set $fn (call $cdr (local.get $tmp)))
               (br $complp)))
          )  ;; complp
       ;; Note that $args is not protected from GC
       (if (i32.eqz (local.get $applying))
           (local.set $args (call $evlis (local.get $args) (local.get $a))))
       (if (call $errorp (local.get $args))
           (then
            (local.set $ret (local.get $args))
            (br $evalbk)))
       (if (i32.ne (local.get $tracing) (i32.const 0))
           (then
            (global.set
             $trace_level (i32.add (global.get $trace_level) (i32.const 1)))
            (call $printComment)
            (call $printObj (call $int2fixnum (global.get $trace_level)))
            (call $printSpace)
            (call $printString (global.get $str_msg_trace_enter))
            (call $printSpace)
            (call $printObj (local.get $tracing))
            (call $printSpace)
            (call $printObj (local.get $args))
            (call $terprif)))
       ;; Note that $fn is not protected from GC when it's generated by
       ;; FUNCTION or LABEL.
       (block $applybk
         (loop $applylp
            ;; fn shouldn't be an atom (we check whether fn is a symbol above)
            (if (i32.eqz (call $consp (local.get $fn)))
                (then (local.set
                       $ret
                       (call $perr1
                             (call $makeStrError (global.get $str_err_nodef))
                             (local.get $fn)))
                      (br $evalbk)))
            (if (i32.eq (call $car (local.get $fn)) (global.get $sym_lambda))
                (then
                 (call $push (local.get $args))  ;; For GC (e a args)
                 (call $push (local.get $fn))  ;; For GC (e a args fn)
                 (local.set
                  $tmp
                  (call $pairlis
                        (call $cadr (local.get $fn)) (local.get $args)
                        (local.get $a)))
                 (call $drop (call $pop))  ;; For GC (e a args)
                 (call $drop (call $pop))  ;; For GC (e a)
                 (local.set $e (call $caddr (local.get $fn)))
                 (local.set $a (local.get $tmp))
                 (i32.store (i32.sub (global.get $sp) (i32.const 8))
                            (local.get $e))  ;; replace `e` in stack
                 (i32.store (i32.sub (global.get $sp) (i32.const 4))
                            (local.get $a))  ;; replace `a` in stack
                 (if (i32.ne (local.get $tracing) (i32.const 0))
                     (then
                      (local.set
                       $ret (call $eval (local.get $e) (local.get $a)))
                      (call $printComment)
                      (call $printObj
                            (call $int2fixnum (global.get $trace_level)))
                      (call $printSpace)
                      (call $printString (global.get $str_msg_trace_exit))
                      (call $printSpace)
                      (call $printObj (local.get $tracing))
                      (call $printChar (i32.const 61))  ;; '='
                      (call $printObj (local.get $ret))
                      (call $terprif)
                      (global.set
                       $trace_level
                       (i32.sub (global.get $trace_level) (i32.const 1)))
                      (br $evalbk)))
                 (br $evallp)))
            (if (i32.eq (call $car (local.get $fn)) (global.get $sym_funarg))
                (then
                 ;; Replace `a` with the closure env
                 (local.set $a (call $caddr (local.get $fn)))
                 (i32.store (i32.sub (global.get $sp) (i32.const 4))
                            (local.get $a))  ;; replace `a` in stack
                 ;; The new fn should be (LAMBDA ...)
                 (local.set $fn (call $cadr (local.get $fn)))
                 (br $applylp)))
            ;; Check if $fn is (SUBR IDX ...)
            (if (i32.eq (call $car (local.get $fn)) (global.get $sym_subr))
                (then
                 (call $argspush (local.get $args))
                 (local.set
                  $ret
                  (call_indirect
                   (type $subr_type)
                   (call $fixnum2int (call $cadr (local.get $fn)))))
                 (call $evpop)
                 (br $evalbk)))
            ;; FUNCTION, LABEL, or a function that returns a function
            (call $push (local.get $args))  ;; For GC (e a args)
            (local.set $tmp (call $eval (local.get $fn) (local.get $a)))
            (call $drop (call $pop))  ;; For GC (e a)
            (if (call $errorp (local.get $tmp))
                (then (local.set $ret (local.get $tmp))
                      (br $evalbk)))
            (local.set $fn (local.get $tmp))
            (br $applylp)
            ))  ;; applybk
       ))  ;; evalbk
  (call $drop (call $pop))  ;; For GC (e)
  (call $drop (call $pop))  ;; For GC ()
  (call $ilog (global.get $sp))
  (call $ilog (i32.const 22222))
  (call $ilog (local.get $ret))
  (if (call $errorp (local.get $ret))
      (call $maybePrintStackTrace (local.get $e)))
  (local.get $ret))

 (func $apply (param $fn i32) (param $args i32) (param $a i32) (result i32)
       (call $eval
             (call $makeCatchableError
                   (global.get $ce_apply)
                   (call $cons (local.get $fn) (local.get $args)))
             (local.get $a)))

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
              (then
               (call $log (i32.const 777001))
               (unreachable)))
          ;; The obj must points to a double word cell
          (if (i32.eqz (call $dwcellp (local.get $obj)))
              (then
               (call $log (i32.const 777002))
               (unreachable)))
          ;; The obj must not point to beyond heap_end
          (if (i32.ge_u (local.get $obj) (global.get $heap_end))
              (then
               (call $log (i32.const 777003))
               (call $log (local.get $obj))
               (unreachable)))

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
       ;; Set oblist_cell NIL first not to mark entire oblist.
       (call $setcar (global.get $oblist_cell) (i32.const 0))
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
               (call $setcar (global.get $oblist_cell) (global.get $oblist))
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
       (global.set $gc_count (i32.add (global.get $gc_count) (i32.const 1)))
       (if (i32.eqz (global.get $suppress_gc_msg))
           (then
            (call $printComment)
            (call $printString (global.get $str_msg_gc1))  ;; gcing
            (call $terprif)
            (call $printComment)
            (call $printString (global.get $str_msg_gc4))  ;; oblist
            (call $printFixnum
                  (call $int2fixnum (call $length (global.get $oblist))))
            (call $terprif)))

       (global.set $num_mark (i32.const 0))
       (global.set $num_unmark (i32.const 0))
       (global.set $num_reclaim (i32.const 0))

       (call $markOblist)
       (call $markPrimitiveObj)
       (call $markStack)
       (call $reconstructOblist)

       (if (i32.eqz (global.get $suppress_gc_msg))
           (then
            (call $printComment)
            (call $printString (global.get $str_msg_gc2))  ;; marked
            (call $printFixnum (call $int2fixnum (global.get $num_mark)))
            (call $terprif)))

       (call $sweepHeap)

       (if (i32.eqz (global.get $suppress_gc_msg))
           (then
            (call $printComment)
            (call $printString (global.get $str_msg_gc3))  ;; reclaimed
            (call $printFixnum (call $int2fixnum (global.get $num_reclaim)))
            (call $terprif)
            (call $printComment)
            (call $printString (global.get $str_msg_gc4))  ;; oblist
            (call $printFixnum
                  (call $int2fixnum (call $length (global.get $oblist))))
            (call $terprif)))

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
       (call $initsymKv
             (local.get $sym) (local.get $str)
             (global.get $sym_apval)
             (call $cons (local.get $val) (i32.const 0))))
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
       (call $setcar (global.get $oblist_cell) (i32.const 0))
       (call $setcdr (global.get $oblist_cell) (i32.const 0))
       (call $setcar (global.get $curchar_cell) (i32.const 0))
       (call $setcdr (global.get $curchar_cell) (i32.const 0))
       (call $setcar (global.get $charcount_cell) (i32.const 0))
       (call $setcdr (global.get $charcount_cell) (i32.const 0))

       (call $initsym0 (global.get $sym_pname) (global.get $str_pname))
       (call $initsym0 (global.get $sym_apval) (global.get $str_apval))
       (call $initsym0 (global.get $sym_dot) (global.get $str_dot))
       (call $initsym0 (global.get $sym_subr) (global.get $str_subr))
       (call $initsym0 (global.get $sym_fsubr) (global.get $str_fsubr))
       (call $initsym0 (global.get $sym_expr) (global.get $str_expr))
       (call $initsym0 (global.get $sym_fexpr) (global.get $str_fexpr))
       (call $initsym0 (global.get $sym_lambda) (global.get $str_lambda))
       (call $initsym0 (global.get $sym_funarg) (global.get $str_funarg))
       (call $initsym0 (global.get $sym_trace) (global.get $str_trace))
       (call $initsym0 (global.get $sym_eof) (global.get $str_eof))
       (call $initsym0 (global.get $sym_eor) (global.get $str_eor))
       (call $initsym0 (global.get $sym_traceset) (global.get $str_traceset))
       (call $initsym0 (global.get $sym_vctag) (global.get $str_vctag))
       (call $initsym0 (global.get $sym_eval_enter_hook)
             (global.get $str_eval_enter_hook))
       (call $initsym0 (global.get $sym_stop) (global.get $str_stop))

       (call $initsym1
             (global.get $sym_nil) (global.get $str_nil) (i32.const 0))
       (call $initsym1
             (global.get $sym_f) (global.get $str_f) (i32.const 0))
       (call $initsym1
             (global.get $sym_t) (global.get $str_t) (global.get $sym_tstar))
       (call $initsym1
             (global.get $sym_tstar) (global.get $str_tstar)
             (global.get $sym_tstar))

       ;;; SUBR
       (call $initsymSubr (global.get $sym_car) (global.get $str_car)
             (global.get $idx_car) (i32.const 1))
       (call $initsymSubr (global.get $sym_cdr) (global.get $str_cdr)
             (global.get $idx_cdr) (i32.const 1))
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
       (call $initsymSubr (global.get $sym_null) (global.get $str_null)
             (global.get $idx_null) (i32.const 1))
       (call $initsymSubr (global.get $sym_rplaca) (global.get $str_rplaca)
             (global.get $idx_rplaca) (i32.const 2))
       (call $initsymSubr (global.get $sym_rplacd) (global.get $str_rplacd)
             (global.get $idx_rplacd) (i32.const 2))
       (call $initsymSubr (global.get $sym_get) (global.get $str_get)
             (global.get $idx_get) (i32.const 2))
       (call $initsymSubr (global.get $sym_eval) (global.get $str_eval)
             (global.get $idx_eval) (i32.const 2))
       (call $initsymSubr (global.get $sym_apply) (global.get $str_apply)
             (global.get $idx_apply) (i32.const 3))
       (call $initsymSubr (global.get $sym_advance) (global.get $str_advance)
             (global.get $idx_advance) (i32.const 0))
       (call $initsymSubr (global.get $sym_startread)
             (global.get $str_startread)
             (global.get $idx_startread) (i32.const 0))
       (call $initsymSubr (global.get $sym_endread) (global.get $str_endread)
             (global.get $idx_endread) (i32.const 0))
       (call $initsymSubr (global.get $sym_nconc) (global.get $str_nconc)
             (global.get $idx_nconc) (i32.const 2))
       (call $initsymSubr (global.get $sym_clearbuff)
             (global.get $str_clearbuff)
             (global.get $idx_clearbuff) (i32.const 0))
       (call $initsymSubr (global.get $sym_pack) (global.get $str_pack)
             (global.get $idx_pack) (i32.const 1))
       (call $initsymSubr (global.get $sym_mknam) (global.get $str_mknam)
             (global.get $idx_mknam) (i32.const 0))
       (call $initsymSubr (global.get $sym_intern) (global.get $str_intern)
             (global.get $idx_intern) (i32.const 1))
       (call $initsymSubr (global.get $sym_numob) (global.get $str_numob)
             (global.get $idx_numob) (i32.const 0))
       (call $initsymSubr (global.get $sym_unpack) (global.get $str_unpack)
             (global.get $idx_unpack) (i32.const 1))
       (call $initsymSubr (global.get $sym_liter) (global.get $str_liter)
             (global.get $idx_liter) (i32.const 1))
       (call $initsymSubr (global.get $sym_digit) (global.get $str_digit)
             (global.get $idx_digit) (i32.const 1))
       (call $initsymSubr (global.get $sym_opchar) (global.get $str_opchar)
             (global.get $idx_opchar) (i32.const 1))
       (call $initsymSubr (global.get $sym_dash) (global.get $str_dash)
             (global.get $idx_dash) (i32.const 1))
       (call $initsymSubr (global.get $sym_attrib) (global.get $str_attrib)
             (global.get $idx_attrib) (i32.const 2))
       (call $initsymSubr (global.get $sym_append) (global.get $str_append)
             (global.get $idx_append) (i32.const 2))
       (call $initsymSubr (global.get $sym_copy) (global.get $str_copy)
             (global.get $idx_copy) (i32.const 1))
       (call $initsymSubr (global.get $sym_not) (global.get $str_not)
             (global.get $idx_not) (i32.const 1))
       (call $initsymSubr (global.get $sym_prop) (global.get $str_prop)
             (global.get $idx_prop) (i32.const 3))
       (call $initsymSubr (global.get $sym_remprop) (global.get $str_remprop)
             (global.get $idx_remprop) (i32.const 2))
       (call $initsymSubr (global.get $sym_pair) (global.get $str_pair)
             (global.get $idx_pair) (i32.const 2))
       (call $initsymSubr (global.get $sym_sassoc) (global.get $str_sassoc)
             (global.get $idx_sassoc) (i32.const 3))
       (call $initsymSubr (global.get $sym_subst) (global.get $str_subst)
             (global.get $idx_subst) (i32.const 3))
       (call $initsymSubr (global.get $sym_sublis) (global.get $str_sublis)
             (global.get $idx_sublis) (i32.const 2))
       (call $initsymSubr (global.get $sym_reverse) (global.get $str_reverse)
             (global.get $idx_reverse) (i32.const 1))
       (call $initsymSubr (global.get $sym_member) (global.get $str_member)
             (global.get $idx_member) (i32.const 2))
       (call $initsymSubr (global.get $sym_length) (global.get $str_length)
             (global.get $idx_length) (i32.const 1))
       (call $initsymSubr (global.get $sym_efface) (global.get $str_efface)
             (global.get $idx_efface) (i32.const 2))
       (call $initsymSubr (global.get $sym_maplist) (global.get $str_maplist)
             (global.get $idx_maplist) (i32.const 2))
       (call $initsymSubr (global.get $sym_mapcon) (global.get $str_mapcon)
             (global.get $idx_mapcon) (i32.const 2))
       (call $initsymSubr (global.get $sym_map) (global.get $str_map)
             (global.get $idx_map) (i32.const 2))
       (call $initsymSubr (global.get $sym_search) (global.get $str_search)
             (global.get $idx_search) (i32.const 4))
       (call $initsymSubr (global.get $sym_recip) (global.get $str_recip)
             (global.get $idx_recip) (i32.const 1))
       (call $initsymSubr (global.get $sym_expt) (global.get $str_expt)
             (global.get $idx_expt) (i32.const 2))
       (call $initsymSubr (global.get $sym_fixp) (global.get $str_fixp)
             (global.get $idx_fixp) (i32.const 1))
       (call $initsymSubr (global.get $sym_floatp) (global.get $str_floatp)
             (global.get $idx_floatp) (i32.const 1))
       (call $initsymSubr (global.get $sym_leftshift)
             (global.get $str_leftshift)
             (global.get $idx_leftshift) (i32.const 2))
       (call $initsymSubr (global.get $sym_read) (global.get $str_read)
             (global.get $idx_read) (i32.const 0))
       (call $initsymSubr (global.get $sym_punch) (global.get $str_punch)
             (global.get $idx_punch) (i32.const 1))
       (call $initsymSubr (global.get $sym_gensym) (global.get $str_gensym)
             (global.get $idx_gensym) (i32.const 0))
       (call $initsymSubr (global.get $sym_remob) (global.get $str_remob)
             (global.get $idx_remob) (i32.const 1))
       (call $initsymSubr (global.get $sym_evlis) (global.get $str_evlis)
             (global.get $idx_evlis) (i32.const 2))
       (call $initsymSubr (global.get $sym_dump) (global.get $str_dump)
             (global.get $idx_dump) (i32.const 4))
       (call $initsymSubr (global.get $sym_error) (global.get $str_error)
             (global.get $idx_error) (i32.const 1))
       (call $initsymSubr (global.get $sym_count) (global.get $str_count)
             (global.get $idx_count) (i32.const 1))
       (call $initsymSubr (global.get $sym_uncount) (global.get $str_uncount)
             (global.get $idx_uncount) (i32.const 1))
       (call $initsymSubr (global.get $sym_speak) (global.get $str_speak)
             (global.get $idx_speak) (i32.const 1))
       (call $initsymSubr (global.get $sym_errorset) (global.get $str_errorset)
             (global.get $idx_errorset) (i32.const 4))
       (call $initsymSubr (global.get $sym_bwrite) (global.get $str_bwrite)
             (global.get $idx_bwrite) (i32.const 1))
       (call $initsymSubr (global.get $sym_bdump) (global.get $str_bdump)
             (global.get $idx_bdump) (i32.const 0))
       (call $initsymSubr (global.get $sym_loadwasm)
             (global.get $str_loadwasm)
             (global.get $idx_loadwasm) (i32.const 0))
       (call $initsymSubr (global.get $sym_nextsubr)
             (global.get $str_nextsubr)
             (global.get $idx_nextsubr) (i32.const 0))
       (call $initsymSubr (global.get $sym_fencode) (global.get $str_fencode)
             (global.get $idx_fencode) (i32.const 1))
       (call $initsymSubr (global.get $sym_bstart) (global.get $str_bstart)
             (global.get $idx_bstart) (i32.const 0))

       ;;; FSUBR
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
       (call $initsymKv
             (global.get $sym_cond) (global.get $str_cond)
             (global.get $sym_fsubr)
             (call $int2fixnum (global.get $idx_cond)))
       (call $initsymKv
             (global.get $sym_function) (global.get $str_function)
             (global.get $sym_fsubr)
             (call $int2fixnum (global.get $idx_function)))
       (call $initsymKv
             (global.get $sym_label) (global.get $str_label)
             (global.get $sym_fsubr)
             (call $int2fixnum (global.get $idx_label)))
       (call $initsymKv
             (global.get $sym_and) (global.get $str_and)
             (global.get $sym_fsubr)
             (call $int2fixnum (global.get $idx_and)))
       (call $initsymKv
             (global.get $sym_or) (global.get $str_or)
             (global.get $sym_fsubr)
             (call $int2fixnum (global.get $idx_or)))
       (call $initsymKv
             (global.get $sym_logand) (global.get $str_logand)
             (global.get $sym_fsubr)
             (call $int2fixnum (global.get $idx_logand)))
       (call $initsymKv
             (global.get $sym_logor) (global.get $str_logor)
             (global.get $sym_fsubr)
             (call $int2fixnum (global.get $idx_logor)))
       (call $initsymKv
             (global.get $sym_logxor) (global.get $str_logxor)
             (global.get $sym_fsubr)
             (call $int2fixnum (global.get $idx_logxor)))
       (call $initsymKv
             (global.get $sym_max) (global.get $str_max)
             (global.get $sym_fsubr)
             (call $int2fixnum (global.get $idx_max)))
       (call $initsymKv
             (global.get $sym_min) (global.get $str_min)
             (global.get $sym_fsubr)
             (call $int2fixnum (global.get $idx_min)))
       (call $initsymKv
             (global.get $sym_time) (global.get $str_time)
             (global.get $sym_fsubr)
             (call $int2fixnum (global.get $idx_time)))

       ;; APVAL
       (call $initsymKv
             (global.get $sym_oblist) (global.get $str_oblist)
             (global.get $sym_apval) (global.get $oblist_cell))
       (call $initsymKv
             (global.get $sym_curchar) (global.get $str_curchar)
             (global.get $sym_apval) (global.get $curchar_cell))
       (call $initsymKv
             (global.get $sym_charcount) (global.get $str_charcount)
             (global.get $sym_apval) (global.get $charcount_cell))

       ;; Errors
       (call $embedStrError (global.get $err_gc) (global.get $str_err_gc))
       )

 ;;; SUBR/FSUBR
 ;;; SUBR stack: (..., a, arg1, arg2, arg3, restArgs)
 ;;; FSUBR stack: (..., e, a)  e is an expression like (QUOTE A)
 ;;; FSUBR stack after eval: (..., e, a, E)  E!=0: need to eval return value

 ;;; Returns the arguments from SUBR stack using frame pointer
 ;;; The frame pointer points just above arguments.
 (func $getArgF1 (param $fmp i32) (result i32)
       (i32.load (i32.sub (local.get $fmp) (i32.const 16))))
 (func $getArgF2 (param $fmp i32) (result i32)
       (i32.load (i32.sub (local.get $fmp) (i32.const 12))))
 (func $getArgF3 (param $fmp i32) (result i32)
       (i32.load (i32.sub (local.get $fmp) (i32.const 8))))
 (func $getArgFRest (param $fmp i32) (result i32)
       (i32.load (i32.sub (local.get $fmp) (i32.const 4))))
 (func $getArgF4 (param $fmp i32) (result i32)
       (call $safecar (call $getArgFRest (local.get $fmp))))
 (func $getArgFN (param $fmp i32) (param $n i32) (result i32)  ;; $n is 0-based
       (local $p i32)
       (if (i32.eq (local.get $n) (i32.const 0))
           (return (call $getArgF1 (local.get $fmp))))
       (if (i32.eq (local.get $n) (i32.const 1))
           (return (call $getArgF2 (local.get $fmp))))
       (if (i32.eq (local.get $n) (i32.const 2))
           (return (call $getArgF3 (local.get $fmp))))
       (local.set $n (i32.sub (local.get $n) (i32.const 3)))
       (local.set $p (call $getArgFRest (local.get $fmp)))
       (block $block
         (loop $loop
            (br_if $block (i32.eqz (local.get $n)))
            (local.set $p (call $safecdr (local.get $p)))
            (local.set $n (i32.sub (local.get $n) (i32.const 1)))
            (br $loop)))
       (call $safecar (local.get $p)))
 (func $getAArgFInSubr (param $fmp i32) (result i32)
      (i32.load (i32.sub (local.get $fmp) (i32.const 20))))

 ;;; Returns the arguments from SUBR stack
 (func $getArg1 (result i32)
       (call $getArgF1 (global.get $sp)))
 (func $getArg2 (result i32)
       (call $getArgF2 (global.get $sp)))
 (func $getArg3 (result i32)
       (call $getArgF3 (global.get $sp)))
 (func $getArgRest (result i32)
       (call $getArgFRest (global.get $sp)))
 (func $getArg4 (result i32)
       (call $getArgF4 (global.get $sp)))
 (func $getAArgInSubr (result i32)
       (call $getAArgFInSubr (global.get $sp)))

 (func $getEArgF (param $fmp i32) (result i32)
      (i32.load (i32.sub (local.get $fmp) (i32.const 8))))
 (func $getAArgF (param $fmp i32) (result i32)
      (i32.load (i32.sub (local.get $fmp) (i32.const 4))))

 ;;; Returns the arguments from FSUBR stack
 (func $getEArg (result i32)
       (call $getEArgF (global.get $sp)))
 (func $getAArg (result i32)
       (call $getAArgF (global.get $sp)))

 (func $setArgF1 (param $fmp i32) (param $val i32)
       (i32.store (i32.sub (local.get $fmp) (i32.const 16)) (local.get $val)))
 (func $setArgF2 (param $fmp i32) (param $val i32)
       (i32.store (i32.sub (local.get $fmp) (i32.const 12)) (local.get $val)))
 (func $setArgF3 (param $fmp i32) (param $val i32)
       (i32.store (i32.sub (local.get $fmp) (i32.const 8)) (local.get $val)))
 (func $setArgFRest (param $fmp i32) (param $val i32)
       (i32.store (i32.sub (local.get $fmp) (i32.const 4)) (local.get $val)))
 (func $setArgF4 (param $fmp i32) (param $val i32)
       (call $setArgFN (local.get $fmp) (i32.const 3) (local.get $val)))
 (func $makeNList (param $n i32) (result i32)
       (local $ret i32)
       (local.set $ret (i32.const 0))
       (loop $loop
          (if (i32.eqz (local.get $n))
              (return (local.get $ret)))
          (local.set $ret (call $cons (i32.const 0) (local.get $ret)))
          (local.set $n (i32.sub (local.get $n) (i32.const 1)))
          (br $loop))
       (i32.const 0))
 (func $maybeExpandList (param $lst i32) (param $n i32) (result i32)
       (local $len i32)
       (local $tmp i32)
       (local.set $len (call $length (local.get $lst)))
       (if (i32.ge_s (local.get $len) (local.get $n))
           (return (local.get $lst)))
       (if (i32.eqz (local.get $len))
           (return (call $makeNList (local.get $n))))
       (call $push (local.get $lst))  ;; For GC (lst)
       (local.set
        $tmp (call $makeNList (i32.sub (local.get $n) (local.get $len))))
       (call $drop (call $pop))  ;; For GC (lst)
       (call $nconc (local.get $lst) (local.get $tmp)))
 ;;; $n is 0-based
 (func $setArgFN (param $fmp i32) (param $n i32) (param $val i32)
       (local $p i32)
       (if (i32.eq (local.get $n) (i32.const 0))
           (return (call $setArgF1 (local.get $fmp) (local.get $val))))
       (if (i32.eq (local.get $n) (i32.const 1))
           (return (call $setArgF2 (local.get $fmp) (local.get $val))))
       (if (i32.eq (local.get $n) (i32.const 2))
           (return (call $setArgF3 (local.get $fmp) (local.get $val))))
       (local.set $n (i32.sub (local.get $n) (i32.const 2)))  ;; n >= 1
       (local.set $p (call $getArgFRest (local.get $fmp)))
       (local.set $p (call $maybeExpandList (local.get $p) (local.get $n)))
       (call $setArgFRest (local.get $fmp) (local.get $p))
       (local.set $n (i32.sub (local.get $n) (i32.const 1)))  ;; n >= 0
       (block $block
         (loop $loop
            (br_if $block (i32.eqz (local.get $n)))
            (local.set $p (call $cdr (local.get $p)))
            (local.set $n (i32.sub (local.get $n) (i32.const 1)))
            (br $loop)))
       (call $setcar (local.get $p) (local.get $val)))
 (func $setAArgFInSubr (param $fmp i32) (param $val i32)
      (i32.store (i32.sub (local.get $fmp) (i32.const 20)) (local.get $val)))

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
 (elem (i32.const 135) $fsubr_cond)
 (global $idx_cond i32 (i32.const 135))
 (elem (i32.const 136) $fsubr_function)
 (global $idx_function i32 (i32.const 136))
 (elem (i32.const 137) $fsubr_label)
 (global $idx_label i32 (i32.const 137))
 (elem (i32.const 138) $subr_null)
 (global $idx_null i32 (i32.const 138))
 (elem (i32.const 139) $subr_rplaca)
 (global $idx_rplaca i32 (i32.const 139))
 (elem (i32.const 140) $subr_rplacd)
 (global $idx_rplacd i32 (i32.const 140))
 (elem (i32.const 141) $subr_get)
 (global $idx_get i32 (i32.const 141))
 (elem (i32.const 142) $subr_eval)
 (global $idx_eval i32 (i32.const 142))
 (elem (i32.const 143) $subr_apply)
 (global $idx_apply i32 (i32.const 143))
 (elem (i32.const 144) $subr_advance)
 (global $idx_advance i32 (i32.const 144))
 (elem (i32.const 145) $subr_startread)
 (global $idx_startread i32 (i32.const 145))
 (elem (i32.const 146) $subr_endread)
 (global $idx_endread i32 (i32.const 146))
 (elem (i32.const 147) $subr_nconc)
 (global $idx_nconc i32 (i32.const 147))
 (elem (i32.const 148) $fsubr_and)
 (global $idx_and i32 (i32.const 148))
 (elem (i32.const 149) $fsubr_or)
 (global $idx_or i32 (i32.const 149))
 (elem (i32.const 150) $fsubr_logand)
 (global $idx_logand i32 (i32.const 150))
 (elem (i32.const 151) $fsubr_logor)
 (global $idx_logor i32 (i32.const 151))
 (elem (i32.const 152) $fsubr_logxor)
 (global $idx_logxor i32 (i32.const 152))
 (elem (i32.const 153) $fsubr_max)
 (global $idx_max i32 (i32.const 153))
 (elem (i32.const 154) $fsubr_min)
 (global $idx_min i32 (i32.const 154))
 (elem (i32.const 155) $subr_clearbuff)
 (global $idx_clearbuff i32 (i32.const 155))
 (elem (i32.const 156) $subr_pack)
 (global $idx_pack i32 (i32.const 156))
 (elem (i32.const 157) $subr_mknam)
 (global $idx_mknam i32 (i32.const 157))
 (elem (i32.const 158) $subr_intern)
 (global $idx_intern i32 (i32.const 158))
 (elem (i32.const 159) $subr_numob)
 (global $idx_numob i32 (i32.const 159))
 (elem (i32.const 160) $subr_unpack)
 (global $idx_unpack i32 (i32.const 160))
 (elem (i32.const 161) $subr_liter)
 (global $idx_liter i32 (i32.const 161))
 (elem (i32.const 162) $subr_digit)
 (global $idx_digit i32 (i32.const 162))
 (elem (i32.const 163) $subr_opchar)
 (global $idx_opchar i32 (i32.const 163))
 (elem (i32.const 164) $subr_dash)
 (global $idx_dash i32 (i32.const 164))
 (elem (i32.const 165) $subr_append)
 (global $idx_append i32 (i32.const 165))
 (elem (i32.const 166) $subr_attrib)
 (global $idx_attrib i32 (i32.const 166))
 (elem (i32.const 167) $subr_copy)
 (global $idx_copy i32 (i32.const 167))
 (elem (i32.const 168) $subr_not)
 (global $idx_not i32 (i32.const 168))
 (elem (i32.const 169) $subr_prop)
 (global $idx_prop i32 (i32.const 169))
 (elem (i32.const 170) $subr_remprop)
 (global $idx_remprop i32 (i32.const 170))
 (elem (i32.const 171) $subr_pair)
 (global $idx_pair i32 (i32.const 171))
 (elem (i32.const 172) $subr_sassoc)
 (global $idx_sassoc i32 (i32.const 172))
 (elem (i32.const 173) $subr_subst)
 (global $idx_subst i32 (i32.const 173))
 (elem (i32.const 174) $subr_sublis)
 (global $idx_sublis i32 (i32.const 174))
 (elem (i32.const 175) $subr_reverse)
 (global $idx_reverse i32 (i32.const 175))
 (elem (i32.const 176) $subr_member)
 (global $idx_member i32 (i32.const 176))
 (elem (i32.const 177) $subr_length)
 (global $idx_length i32 (i32.const 177))
 (elem (i32.const 178) $subr_efface)
 (global $idx_efface i32 (i32.const 178))
 (elem (i32.const 179) $subr_maplist)
 (global $idx_maplist i32 (i32.const 179))
 (elem (i32.const 180) $subr_mapcon)
 (global $idx_mapcon i32 (i32.const 180))
 (elem (i32.const 181) $subr_map)
 (global $idx_map i32 (i32.const 181))
 (elem (i32.const 182) $subr_search)
 (global $idx_search i32 (i32.const 182))
 (elem (i32.const 183) $subr_recip)
 (global $idx_recip i32 (i32.const 183))
 (elem (i32.const 184) $subr_expt)
 (global $idx_expt i32 (i32.const 184))
 (elem (i32.const 185) $subr_fixp)
 (global $idx_fixp i32 (i32.const 185))
 (elem (i32.const 186) $subr_floatp)
 (global $idx_floatp i32 (i32.const 186))
 (elem (i32.const 187) $subr_leftshift)
 (global $idx_leftshift i32 (i32.const 187))
 (elem (i32.const 188) $subr_read)
 (global $idx_read i32 (i32.const 188))
 (elem (i32.const 189) $subr_punch)
 (global $idx_punch i32 (i32.const 189))
 (elem (i32.const 190) $subr_gensym)
 (global $idx_gensym i32 (i32.const 190))
 (elem (i32.const 191) $subr_remob)
 (global $idx_remob i32 (i32.const 191))
 (elem (i32.const 192) $subr_evlis)
 (global $idx_evlis i32 (i32.const 192))
 (elem (i32.const 193) $subr_dump)
 (global $idx_dump i32 (i32.const 193))
 (elem (i32.const 194) $subr_error)
 (global $idx_error i32 (i32.const 194))
 (elem (i32.const 195) $subr_count)
 (global $idx_count i32 (i32.const 195))
 (elem (i32.const 196) $subr_uncount)
 (global $idx_uncount i32 (i32.const 196))
 (elem (i32.const 197) $subr_speak)
 (global $idx_speak i32 (i32.const 197))
 (elem (i32.const 198) $subr_errorset)
 (global $idx_errorset i32 (i32.const 198))
 (elem (i32.const 199) $subr_bwrite)
 (global $idx_bwrite i32 (i32.const 199))
 (elem (i32.const 200) $subr_bdump)
 (global $idx_bdump i32 (i32.const 200))
 (elem (i32.const 201) $subr_loadwasm)
 (global $idx_loadwasm i32 (i32.const 201))
 (elem (i32.const 202) $subr_nextsubr)
 (global $idx_nextsubr i32 (i32.const 202))
 (elem (i32.const 203) $subr_fencode)
 (global $idx_fencode i32 (i32.const 203))
 (elem (i32.const 204) $subr_logand2)
 (global $idx_logand2 i32 (i32.const 204))
 (elem (i32.const 205) $subr_logor2)
 (global $idx_logor2 i32 (i32.const 205))
 (elem (i32.const 206) $subr_logxor2)
 (global $idx_logxor2 i32 (i32.const 206))
 (elem (i32.const 207) $subr_max2)
 (global $idx_max2 i32 (i32.const 207))
 (elem (i32.const 208) $subr_min2)
 (global $idx_min2 i32 (i32.const 208))
 (elem (i32.const 209) $subr_plus2)
 (global $idx_plus2 i32 (i32.const 209))
 (elem (i32.const 210) $subr_times2)
 (global $idx_times2 i32 (i32.const 210))
 (elem (i32.const 211) $fsubr_time)
 (global $idx_time i32 (i32.const 211))
 (elem (i32.const 212) $subr_bstart)
 (global $idx_bstart i32 (i32.const 212))

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
                  $ret (call $perr1
                             (call $makeStrError (global.get $str_err_num))
                             (global.get $sym_plus)))
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
                  $ret (call $perr1
                             (call $makeStrError (global.get $str_err_num))
                             (global.get $sym_times)))
                 (br $block)))
            (local.set $args (call $cdr (local.get $args)))
            (br $loop)))
       (if (i32.eqz (local.get $ret))
           (local.set $ret (call $int2fixnum (local.get $acc))))
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (local.get $ret))

    (func $subr_plus2 (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $perr1 (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1))))
       (if (i32.eqz (call $fixnump (local.get $arg2)))
           (return (call $perr1 (call $makeStrError (global.get $str_err_num))
                         (local.get $arg2))))
       (call $int2fixnum
             (i32.add (call $fixnum2int (local.get $arg1))
                      (call $fixnum2int (local.get $arg2)))))
    (func $subr_times2 (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $perr1 (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1))))
       (if (i32.eqz (call $fixnump (local.get $arg2)))
           (return (call $perr1 (call $makeStrError (global.get $str_err_num))
                         (local.get $arg2))))
       (call $int2fixnum
             (i32.mul (call $fixnum2int (local.get $arg1))
                      (call $fixnum2int (local.get $arg2)))))

 (func $subr_reclaim (result i32)
       (call $garbageCollect))

 (func $fsubr_prog (result i32)
       (local $a i32)
       (local $args i32)
       (local $exps i32)
       (local $exp i32)
       (local $ret i32)
       (local $lbl i32)
       (local $traceset_on i32)
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       (if (i32.ne (call $car (local.get $args)) (i32.const 0))
            (local.set
             $a
             (call $pairlis (call $car (local.get $args)) (i32.const 0)
                   (local.get $a))))
       (local.set $traceset_on (i32.const 0))
       (if (i32.eq (global.get $traceset_env) (global.get $sym_tstar))
           (then
            (local.set $traceset_on (i32.const 1))
            (global.set $traceset_env (local.get $a))))
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
                      (local.set $lbl (call $getCEValue (local.get $exp)))
                      (local.set
                       $exp (call $member
                                  (local.get $lbl)
                                  (call $cdr (local.get $args))))
                      ;; Label not found
                      (if (i32.eqz (local.get $exp))
                          (then
                           (local.set
                            $ret
                            (call $perr1
                                  (call $makeStrError
                                        (global.get $str_err_label))
                                  (local.get $lbl)))
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
       (if (local.get $traceset_on)
           (global.set $traceset_env (i32.const 0)))
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
           (return (call $perr1
                         (call $makeStrError (global.get $str_err_generic))
                         (global.get $sym_set))))
       (if (i32.eq (local.get $a) (global.get $traceset_env))
           (then
            (call $printComment)
            (call $printObj (local.get $arg1))
            (call $printSpace)
            (call $printChar (i32.const 61))  ;; '='
            (call $printSpace)
            (call $printObj (local.get $arg2))
            (call $terprif)))
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
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (if (call $errorp (local.get $arg2))
           (return (local.get $arg2)))
       (local.set $p (call $assoc (local.get $arg1) (local.get $a)))
       (if (i32.eqz (local.get $p))
           (then
            ;;; Replace the return value
            ;; TODO: Return the specific error
            (local.set
             $arg2 (call $perr1
                         (call $makeStrError (global.get $str_err_generic))
                         (global.get $sym_setq))))
           (else
            (call $setcdr (local.get $p) (local.get $arg2))
            (if (i32.eq (local.get $a) (global.get $traceset_env))
                (then
                 (call $printComment)
                 (call $printObj (local.get $arg1))
                 (call $printSpace)
                 (call $printChar (i32.const 61))  ;; '='
                 (call $printSpace)
                 (call $printObj (local.get $arg2))
                 (call $terprif)))))
       (local.get $arg2))

  (func $subr_prog2 (result i32)
        (call $getArg2))

 (func $subr_minus (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $perr1
                         (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1))))
       (call $int2fixnum (i32.mul (call $fixnum2int (local.get $arg1))
                                  (i32.const -1))))
 (func $subr_difference (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.or (i32.eqz (call $fixnump (local.get $arg1)))
                   (i32.eqz (call $fixnump (local.get $arg2))))
           (return (call $perr2
                         (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1) (local.get $arg2))))
       (call $int2fixnum (i32.sub (call $fixnum2int (local.get $arg1))
                                  (call $fixnum2int (local.get $arg2)))))
 (func $subr_divide (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.or (i32.eqz (call $fixnump (local.get $arg1)))
                   (i32.eqz (call $fixnump (local.get $arg2))))
           (return (call $perr2
                         (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1) (local.get $arg2))))
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
           (return (call $perr2
                         (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1) (local.get $arg2))))
       (call $int2fixnum (i32.div_s (call $fixnum2int (local.get $arg1))
                                    (call $fixnum2int (local.get $arg2)))))
 (func $subr_remainder (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.or (i32.eqz (call $fixnump (local.get $arg1)))
                   (i32.eqz (call $fixnump (local.get $arg2))))
           (return (call $perr2
                         (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1) (local.get $arg2))))
       (call $int2fixnum (i32.rem_s (call $fixnum2int (local.get $arg1))
                                    (call $fixnum2int (local.get $arg2)))))

 (func $subr_add1 (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $perr1
                         (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1))))
       (call $int2fixnum (i32.add (call $fixnum2int (local.get $arg1))
                                  (i32.const 1))))
 (func $subr_sub1 (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $perr1
                         (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1))))
       (call $int2fixnum (i32.sub (call $fixnum2int (local.get $arg1))
                                  (i32.const 1))))

 (func $subr_lessp (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.or (i32.eqz (call $fixnump (local.get $arg1)))
                   (i32.eqz (call $fixnump (local.get $arg2))))
           (return (call $perr2
                         (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1) (local.get $arg2))))
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
           (return (call $perr2
                         (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1) (local.get $arg2))))
       (if (i32.gt_s (call $fixnum2int (local.get $arg1))
                     (call $fixnum2int (local.get $arg2)))
           (return (global.get $sym_tstar)))
       (i32.const 0))

 (func $subr_zerop (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $perr1
                         (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1))))
       (if (i32.eqz (call $fixnum2int (local.get $arg1)))
           (return (global.get $sym_tstar)))
       (i32.const 0))
 (func $subr_onep (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $perr1
                         (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1))))
       (if (i32.eq (call $fixnum2int (local.get $arg1))
                                 (i32.const 1))
           (return (global.get $sym_tstar)))
       (i32.const 0))
 (func $subr_minusp (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $perr1
                         (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1))))
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

 (func $fsubr_cond (result i32)
       (local $a i32)
       (local $args i32)
       (local $ret i32)
       (local $tmp i32)
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       (local.set $ret (i32.const 0))
       (block $block
         (loop $loop
            (br_if $block (i32.eqz (call $consp (local.get $args))))
            (local.set
             $tmp
             (call $eval (call $safecar (call $safecar (local.get $args)))
                   (local.get $a)))
            (if (call $errorp (local.get $tmp))
                (then
                 (local.set $ret (local.get $tmp))
                 (br $block)))
            (if (i32.ne (local.get $tmp) (i32.const 0))
                (then
                 (local.set
                  $ret
                  (call $safecar
                        (call $safecdr (call $safecar (local.get $args)))))
                 (br $block)))
            (local.set $args (call $cdr (local.get $args)))
            (br $loop)))
       (call $push (i32.const 1))  ;; *Need* to eval return value
       (local.get $ret))

 (func $fsubr_function (result i32)
       (local $a i32)
       (local $args i32)
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (call $list3 (global.get $sym_funarg) (call $car (local.get $args))
             (local.get $a)))

 (func $fsubr_label (result i32)
       (local $a i32)
       (local $args i32)
       (local $tmp i32)
       (local $ret i32)
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       ;; Push (name . fun) pair to `a`
       (local.set $tmp (call $cons
                             (call $car (local.get $args))
                             (call $cadr (local.get $args))))
       (local.set $tmp (call $cons (local.get $tmp) (local.get $a)))
       ;; Create (FUNARG fun ((name . fun) . a))
       (local.set
        $ret
        (call $list3 (global.get $sym_funarg) (call $cadr (local.get $args))
              (local.get $tmp)))
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (local.get $ret))

 (func $subr_null (result i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (if (i32.eqz (local.get $arg1))
           (return (global.get $sym_tstar)))
       (i32.const 0))

 (func $subr_rplaca (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.eqz (call $dwcellp (local.get $arg1)))
           (return (call $perr2
                         (call $makeStrError (global.get $str_err_generic))
                         (global.get $sym_rplaca)
                         (local.get $arg1))))
       (call $setcar (local.get $arg1) (local.get $arg2))
       (local.get $arg2))
 (func $subr_rplacd (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.eqz (call $dwcellp (local.get $arg1)))
           (return (call $perr2
                         (call $makeStrError (global.get $str_err_generic))
                         (global.get $sym_rplacd)
                         (local.get $arg1))))
       (call $setcdr (local.get $arg1) (local.get $arg2))
       (local.get $arg2))

 (func $subr_get (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (call $get (local.get $arg1) (local.get $arg2)))

 ;;; EVAL and APPLY are called from only compiled code.
 (func $subr_eval (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (call $eval (local.get $arg1) (local.get $arg2)))
 (func $subr_apply (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local $arg3 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (local.set $arg3 (call $getArg3))
       (call $apply (local.get $arg1) (local.get $arg2) (local.get $arg3)))

 (func $subr_advance (result i32)
       (local $c i32)
       (local $ret i32)
       (local.set $ret (i32.const 0))
       (local.set $c (call $readChar))
       (if (i32.eqz (local.get $c))
           (local.set $ret (global.get $sym_eof)))
       (if (i32.or (i32.eq (local.get $c) (i32.const 10))  ;; '\n'
                   (i32.eq (local.get $c) (i32.const 13)))  ;; '\r'
           (local.set $ret (global.get $sym_eor)))
       (if (i32.eqz (local.get $ret))
           (then
            ;; Store "c\00" to boffo, and make a symbol.
            (i32.store8 (global.get $boffo) (local.get $c))
            (i32.store8 (i32.add (global.get $boffo) (i32.const 1))
                        (i32.const 0))
            (local.set $ret (call $makeSym))))
       (call $setcar (global.get $curchar_cell) (local.get $ret))
       (call $setcar
             (global.get $charcount_cell)
             (call $int2fixnum
                   (i32.sub (global.get $readp) (global.get $read_start))))
       (local.get $ret))
 (func $subr_startread (result i32)
       ;; TODO: Implement the logic
       (call $subr_advance))
 (func $subr_endread (result i32)
       ;; TODO: Implement the logic
       (call $setcar (global.get $curchar_cell) (global.get $sym_eof))
       (global.get $sym_eof))

 (func $fsubr_and (result i32)
       (local $a i32)
       (local $args i32)
       (local $val i32)
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (if (i32.eqz (local.get $args))
           (return (global.get $sym_tstar)))
       (loop $loop
          (if (i32.eqz (call $cdr (local.get $args)))
              (then
               (call $drop (call $pop))  ;; Drop 0
               (call $push (i32.const 1))  ;; *Need* to eval return value
               (return (call $car (local.get $args)))))
          (local.set
           $val (call $eval (call $car (local.get $args)) (local.get $a)))
          (if (call $errorp (local.get $val))
              (return (local.get $val)))
          (if (i32.eqz (local.get $val))
              (return (i32.const 0)))
          (local.set $args (call $cdr (local.get $args)))
          (br $loop))
       (global.get $sym_tstar))
  (func $fsubr_or (result i32)
       (local $a i32)
       (local $args i32)
       (local $val i32)
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (if (i32.eqz (local.get $args))
           (return (i32.const 0)))
       (loop $loop
          (if (i32.eqz (call $cdr (local.get $args)))
              (then
               (call $drop (call $pop))  ;; Drop 0
               (call $push (i32.const 1))  ;; *Need* to eval return value
               (return (call $car (local.get $args)))))
          (local.set
           $val (call $eval (call $car (local.get $args)) (local.get $a)))
          (if (call $errorp (local.get $val))
              (return (local.get $val)))
          (if (i32.ne (local.get $val) (i32.const 0))
              (return (local.get $val)))
          (local.set $args (call $cdr (local.get $args)))
          (br $loop))
       (i32.const 0))

  (func $fsubr_logand (result i32)
       (local $a i32)
       (local $args i32)
       (local $val i32)
       (local $acc i32)
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       (local.set $acc (i32.const -1))
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (loop $loop
          (if (i32.eqz (local.get $args))
              (return (call $int2fixnum (local.get $acc))))
          (local.set
           $val (call $eval (call $car (local.get $args)) (local.get $a)))
          (if (call $errorp (local.get $val))
              (return (local.get $val)))
          (if (i32.eqz (call $fixnump (local.get $val)))
              (return (call $perr1
                            (call $makeStrError (global.get $str_err_num))
                            (local.get $val))))
          (local.set
           $acc (i32.and (call $fixnum2int (local.get $val))
                         (local.get $acc)))
          (local.set $args (call $cdr (local.get $args)))
          (br $loop))
       (i32.const -1))
  (func $fsubr_logor (result i32)
       (local $a i32)
       (local $args i32)
       (local $val i32)
       (local $acc i32)
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       (local.set $acc (i32.const 0))
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (loop $loop
          (if (i32.eqz (local.get $args))
              (return (call $int2fixnum (local.get $acc))))
          (local.set
           $val (call $eval (call $car (local.get $args)) (local.get $a)))
          (if (call $errorp (local.get $val))
              (return (local.get $val)))
          (if (i32.eqz (call $fixnump (local.get $val)))
              (return (call $perr1
                            (call $makeStrError (global.get $str_err_num))
                            (local.get $val))))
          (local.set
           $acc (i32.or (call $fixnum2int (local.get $val))
                        (local.get $acc)))
          (local.set $args (call $cdr (local.get $args)))
          (br $loop))
       (i32.const 0))
  (func $fsubr_logxor (result i32)
       (local $a i32)
       (local $args i32)
       (local $val i32)
       (local $acc i32)
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       (local.set $acc (i32.const 0))
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (loop $loop
          (if (i32.eqz (local.get $args))
              (return (call $int2fixnum (local.get $acc))))
          (local.set
           $val (call $eval (call $car (local.get $args)) (local.get $a)))
          (if (call $errorp (local.get $val))
              (return (local.get $val)))
          (if (i32.eqz (call $fixnump (local.get $val)))
              (return (call $perr1
                            (call $makeStrError (global.get $str_err_num))
                            (local.get $val))))
          (local.set
           $acc (i32.xor (call $fixnum2int (local.get $val))
                         (local.get $acc)))
          (local.set $args (call $cdr (local.get $args)))
          (br $loop))
       (i32.const 0))
  (func $subr_logand2 (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $perr1 (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1))))
       (if (i32.eqz (call $fixnump (local.get $arg2)))
           (return (call $perr1 (call $makeStrError (global.get $str_err_num))
                         (local.get $arg2))))
       (call $int2fixnum
             (i32.and (call $fixnum2int (local.get $arg1))
                      (call $fixnum2int (local.get $arg2)))))
  (func $subr_logor2 (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $perr1 (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1))))
       (if (i32.eqz (call $fixnump (local.get $arg2)))
           (return (call $perr1 (call $makeStrError (global.get $str_err_num))
                         (local.get $arg2))))
       (call $int2fixnum
             (i32.or (call $fixnum2int (local.get $arg1))
                     (call $fixnum2int (local.get $arg2)))))
  (func $subr_logxor2 (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $perr1 (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1))))
       (if (i32.eqz (call $fixnump (local.get $arg2)))
           (return (call $perr1 (call $makeStrError (global.get $str_err_num))
                         (local.get $arg2))))
       (call $int2fixnum
             (i32.xor (call $fixnum2int (local.get $arg1))
                      (call $fixnum2int (local.get $arg2)))))

  (func $fsubr_max (result i32)
       (local $a i32)
       (local $args i32)
       (local $val i32)
       (local $acc i32)
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       (local.set $acc (i32.const 0xe0000000))
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (if (i32.eqz (local.get $args))
           ;; TODO: Return the specific error
           (return (call $perr1
                         (call $makeStrError (global.get $str_err_generic))
                         (global.get $sym_max))))
       (loop $loop
          (if (i32.eqz (local.get $args))
              (return (call $int2fixnum (local.get $acc))))
          (local.set
           $val (call $eval (call $car (local.get $args)) (local.get $a)))
          (if (call $errorp (local.get $val))
              (return (local.get $val)))
          (if (i32.eqz (call $fixnump (local.get $val)))
              (return (call $perr1
                            (call $makeStrError (global.get $str_err_num))
                            (local.get $val))))
          (local.set $val (call $fixnum2int (local.get $val)))
          (if (i32.gt_s (local.get $val) (local.get $acc))
              (local.set $acc (local.get $val)))
          (local.set $args (call $cdr (local.get $args)))
          (br $loop))
       (i32.const 0))
  (func $fsubr_min (result i32)
       (local $a i32)
       (local $args i32)
       (local $val i32)
       (local $acc i32)
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       (local.set $acc (i32.const 0x1fffffff))
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (if (i32.eqz (local.get $args))
           ;; TODO: Return the specific error
           (return (call $perr1
                         (call $makeStrError (global.get $str_err_generic))
                         (global.get $sym_min))))
       (loop $loop
          (if (i32.eqz (local.get $args))
              (return (call $int2fixnum (local.get $acc))))
          (local.set
           $val (call $eval (call $car (local.get $args)) (local.get $a)))
          (if (call $errorp (local.get $val))
              (return (local.get $val)))
          (if (i32.eqz (call $fixnump (local.get $val)))
              (return (call $perr1
                            (call $makeStrError (global.get $str_err_num))
                            (local.get $val))))
          (local.set $val (call $fixnum2int (local.get $val)))
          (if (i32.lt_s (local.get $val) (local.get $acc))
              (local.set $acc (local.get $val)))
          (local.set $args (call $cdr (local.get $args)))
          (br $loop))
       (i32.const 0))
  (func $subr_max2 (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $perr1 (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1))))
       (if (i32.eqz (call $fixnump (local.get $arg2)))
           (return (call $perr1 (call $makeStrError (global.get $str_err_num))
                         (local.get $arg2))))
       (if (i32.lt_s (call $fixnum2int (local.get $arg1))
                     (call $fixnum2int (local.get $arg2)))
           (return (local.get $arg2)))
       (local.get $arg1))
  (func $subr_min2 (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (if (i32.eqz (call $fixnump (local.get $arg1)))
           (return (call $perr1 (call $makeStrError (global.get $str_err_num))
                         (local.get $arg1))))
       (if (i32.eqz (call $fixnump (local.get $arg2)))
           (return (call $perr1 (call $makeStrError (global.get $str_err_num))
                         (local.get $arg2))))
       (if (i32.lt_s (call $fixnum2int (local.get $arg1))
                     (call $fixnum2int (local.get $arg2)))
           (return (local.get $arg1)))
       (local.get $arg2))

  (func $subr_nconc (result i32)
       (local $arg1 i32)
       (local $arg2 i32)
       (local $ret i32)
       (local.set $arg1 (call $getArg1))
       (local.set $arg2 (call $getArg2))
       (local.set $ret (local.get $arg1))
       (if (i32.eqz (call $consp (local.get $arg1)))
           (return (local.get $arg2)))
       (block $block
         (loop $loop
            (br_if $block
                   (i32.eqz (call $consp (call $cdr (local.get $arg1)))))
            (local.set $arg1 (call $cdr (local.get $arg1)))
            (br $loop)))
       (call $setcdr (local.get $arg1) (local.get $arg2))
       (local.get $ret))

  (func $subr_clearbuff (result i32)
        (global.set $uboffop (global.get $uboffo))
        (i32.const 0))
  (func $subr_pack (result i32)
        (local $arg1 i32)
        (local $tmp i32)
        (local.set $arg1 (call $getArg1))
        (if (i32.and (call $fixnump (local.get $arg1))
                     (i32.ge_s (local.get $arg1) (i32.const 0)))
            (then
             ;; Convert a number to a digit character.
             (local.set $tmp (call $fixnum2int (local.get $arg1)))
             (local.set $tmp (i32.add
                              (i32.const 48)  ;; '0'
                              (i32.rem_s (local.get $tmp) (i32.const 10)))))
            (else
             (local.set
              $tmp (call $get (local.get $arg1) (global.get $sym_pname)))
             (if (i32.eqz (local.get $tmp))
                 ;; TODO: Return the specific error
                 (return (call
                          $perr1
                          (call $makeStrError (global.get $str_err_generic))
                          (local.get $arg1))))
             ;; Get the first character.
             (local.set $tmp (call $car (local.get $tmp)))
             (local.set
              $tmp (i32.and (i32.shr_u (local.get $tmp) (i32.const 8))
                            (i32.const 0x000000ff)))))
        ;; Copy to uboffo.
        (i32.store8 (global.get $uboffop) (local.get $tmp))
        (global.set $uboffop (i32.add (global.get $uboffop) (i32.const 1)))
        (i32.store8 (global.get $uboffop) (i32.const 0))
        (i32.const 0))
  (func $subr_mknam (result i32)
        (local $ret i32)
        (local.set $ret (call $makename (global.get $uboffo)))
        (global.set $uboffop (global.get $uboffo))
        (local.get $ret))
  (func $subr_intern (result i32)
        (local $cell i32)
        (local $sym i32)
        (local $arg1 i32)
        (local.set $arg1 (call $getArg1))  ;; name like (name1 name1 ...)
        (local.set $cell (global.get $oblist))
        (block $block
          (loop $loop
             (local.set $sym (call $car (local.get $cell)))
             (if (call $equal
                       (call $get (local.get $sym) (global.get $sym_pname))
                       (local.get $arg1))
                 (br $block))
             (local.set $cell (call $cdr (local.get $cell)))
             (br_if $loop (i32.ne (local.get $cell) (i32.const 0)))))
        (if (i32.eqz (local.get $cell))
            (then
             (local.set
              $sym (call $cons (global.get $tag_symbol) (i32.const 0)))
             (call $push (local.get $sym))  ;; For GC (sym)
             (local.set $cell (call $cons (local.get $arg1) (i32.const 0)))
             (call $setcdr (local.get $sym) (local.get $cell))  ;; For GC
             (local.set
              $cell (call $cons (global.get $sym_pname) (local.get $cell)))
             (call $setcdr (local.get $sym) (local.get $cell))
             (call $drop (call $pop))  ;; For GC ()
             (call $pushToOblist (local.get $sym))))
        (local.get $sym))
  (func $subr_numob (result i32)
          (local $c i32)
        (local $sign i32)
        (local $num i32)
        (local.set $sign (i32.const 1))
        (local.set $num (i32.const 0))
        (global.set $uboffop (global.get $uboffo))
        (local.set $c (i32.load8_u (global.get $uboffop)))
        (if (i32.eq (local.get $c) (i32.const 45))  ;; '-'
            (then
             (local.set $sign (i32.const -1))
             (global.set
              $uboffop (i32.add (global.get $uboffop) (i32.const 1)))
             (local.set $c (i32.load8_u (global.get $uboffop)))))
        (block $block
          (loop $loop
             (br_if $block (i32.eqz (local.get $c)))
             (if (i32.and  ;; '0' <= c && c <= '9'
                  (i32.le_u (i32.const 48) (local.get $c))
                  (i32.le_u (local.get $c) (i32.const 57)))
                 (local.set $num
                            (i32.add (i32.mul (local.get $num) (i32.const 10))
                                     (i32.sub (local.get $c) (i32.const 48))))
                 (br $block))
            (global.set $uboffop (i32.add (global.get $uboffop) (i32.const 1)))
            (local.set $c (i32.load8_u (global.get $uboffop)))
            (br $loop)))
        (global.set $uboffop (global.get $uboffo))
        (call $int2fixnum (i32.mul (local.get $num) (local.get $sign))))
  (func $subr_unpack (result i32)
        (local $arg1 i32)
        (local $lst i32)
        (local $pn i32)
        (local $nm i32)
        (local $ret i32)
        (local.set $arg1 (call $getArg1))  ;; name1 or symbol
        (if (call $fixnump (local.get $arg1))
            (return (call $unpackn1 (local.get $arg1))))
        (local.set
         $pn (call $get (local.get $arg1) (global.get $sym_pname)))
        (if (i32.eqz (local.get $pn))
            ;; TODO: Return the specific error
            (return (call $perr1
                          (call $makeStrError (global.get $str_err_generic))
                          (local.get $arg1))))
        (local.set $ret (i32.const 0))
        (block $block
          (loop $loop
             (br_if $block (i32.eqz (local.get $pn)))
             (call $push (local.get $ret))  ;; For GC (ret)
             (local.set $nm (call $unpackn1 (call $car (local.get $pn))))
             (call $drop (call $pop))  ;; For GC ()
             (local.set $ret (call $cons (local.get $nm) (local.get $ret)))
             (local.set $pn (call $cdr (local.get $pn)))
             (br $loop)))
        (call $conc (call $nreverse (local.get $ret))))

   (func $subr_liter (result i32)
       (local $tmp i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (local.set
        $tmp (call $get (local.get $arg1) (global.get $sym_pname)))
       (if (i32.eqz (local.get $tmp))
           ;; TODO: Return the specific error
           (return (call $perr1
                         (call $makeStrError (global.get $str_err_generic))
                         (local.get $arg1))))
       (local.set $tmp (call $car (local.get $tmp)))
       (if (i32.or
            (i32.and
             (i32.le_u (i32.const 0x00004102)  ;; 'A' + fixnum tag
                       (local.get $tmp))
             (i32.le_u (local.get $tmp)
                       (i32.const 0x00005a02)))  ;; 'Z' + fixnum tag
            (i32.and
             (i32.le_u (i32.const 0x00006102)  ;; 'a' + fixnum tag
                       (local.get $tmp))
             (i32.le_u (local.get $tmp)
                       (i32.const 0x00007a02))))  ;; 'z' + fixnum tag
           (return (global.get $sym_tstar)))
       (i32.const 0))
   (func $subr_digit (result i32)
       (local $tmp i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (local.set
        $tmp (call $get (local.get $arg1) (global.get $sym_pname)))
       (if (i32.eqz (local.get $tmp))
           ;; TODO: Return the specific error
           (return (call $perr1
                         (call $makeStrError (global.get $str_err_generic))
                         (local.get $arg1))))
       (local.set $tmp (call $car (local.get $tmp)))
       (if (i32.and
             (i32.le_u (i32.const 0x00003002)  ;; '0' + fixnum tag
                       (local.get $tmp))
             (i32.le_u (local.get $tmp)
                       (i32.const 0x00003902)))  ;; '9' + fixnum tag
           (return (global.get $sym_tstar)))
       (i32.const 0))
   (func $subr_opchar (result i32)
       (local $tmp i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (local.set
        $tmp (call $get (local.get $arg1) (global.get $sym_pname)))
       (if (i32.eqz (local.get $tmp))
           ;; TODO: Return the specific error
           (return (call $perr1
                         (call $makeStrError (global.get $str_err_generic))
                         (local.get $arg1))))
       (local.set $tmp (call $car (local.get $tmp)))
       (if (i32.eq (local.get $tmp) (i32.const 0x00002b02))  ;; '+'
           (return (global.get $sym_tstar)))
       (if (i32.eq (local.get $tmp) (i32.const 0x00002d02))  ;; '-'
           (return (global.get $sym_tstar)))
       (if (i32.eq (local.get $tmp) (i32.const 0x00002a02))  ;; '*'
           (return (global.get $sym_tstar)))
       (if (i32.eq (local.get $tmp) (i32.const 0x00002f02))  ;; '/'
           (return (global.get $sym_tstar)))
       (if (i32.eq (local.get $tmp) (i32.const 0x00003d02))  ;; '='
           (return (global.get $sym_tstar)))
       (i32.const 0))
   (func $subr_dash (result i32)
       (local $tmp i32)
       (local $arg1 i32)
       (local.set $arg1 (call $getArg1))
       (local.set
        $tmp (call $get (local.get $arg1) (global.get $sym_pname)))
       (if (i32.eqz (local.get $tmp))
           ;; TODO: Return the specific error
           (return (call $perr1
                         (call $makeStrError (global.get $str_err_generic))
                         (local.get $arg1))))
       (local.set $tmp (call $car (local.get $tmp)))
       (if (i32.eq (local.get $tmp) (i32.const 0x00002d02))  ;; '-'
           (return (global.get $sym_tstar)))
       (i32.const 0))

   (func $subr_append (result i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local $ret i32)
         (local $cur i32)
         (local $tmp i32)
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         (if (i32.eqz (local.get $arg1))
             (return (local.get $arg2)))
         (local.set
          $ret (call $cons (call $car (local.get $arg1)) (i32.const 0)))
         (call $push (local.get $ret))  ;; For GC (ret)
         (local.set $arg1 (call $cdr (local.get $arg1)))
         (local.set $cur (local.get $ret))
         (block $block
           (loop $loop
              (if (i32.eqz (local.get $arg1))
                  (br $block))
              (local.set
               $tmp (call $cons (call $car (local.get $arg1)) (i32.const 0)))
              (call $setcdr (local.get $cur) (local.get $tmp))
              (local.set $cur (local.get $tmp))
              (local.set $arg1 (call $cdr (local.get $arg1)))
              (br $loop)))
         (call $setcdr (local.get $cur) (local.get $arg2))
         (call $pop))  ;; For GC ()

   (func $subr_attrib (result i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         (call $drop (call $nconc (local.get $arg1) (local.get $arg2)))
         (local.get $arg2))

   (func $copy (param $x i32) (result i32)
         (local $left i32)
         (local $right i32)
         (local $ret i32)
         (if (i32.eqz (call $consp (local.get $x)))
             (return (local.get $x)))
         (local.set $left (call $copy (call $car (local.get $x))))
         (call $push (local.get $left))  ;; For GC (left)
         (local.set $right (call $copy (call $cdr (local.get $x))))
         (call $push (local.get $right))  ;; For GC (left, right)
         (local.set $ret (call $cons (local.get $left) (local.get $right)))
         (call $drop (call $pop))  ;; For GC (left)
         (call $drop (call $pop))  ;; For GC ()
         (local.get $ret))
   (func $subr_copy (result i32)
         (local $arg1 i32)
         (local.set $arg1 (call $getArg1))
         (call $copy (local.get $arg1)))

   (func $subr_not (result i32)
         (local $arg1 i32)
         (local.set $arg1 (call $getArg1))
         (if (i32.eqz (local.get $arg1))
             (return (global.get $sym_tstar)))
         (i32.const 0))

   (func $subr_prop (result i32)
         (local $a i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local $arg3 i32)
         (local $ret i32)
         (local.set $a (call $getAArgInSubr))
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         (local.set $arg3 (call $getArg3))
         (local.set $ret (call $prop (local.get $arg1) (local.get $arg2)))
         (if (i32.eqz (local.get $ret))
             (return
               (call $eval
                     (call $makeCatchableError
                           (global.get $ce_apply)
                           (call $cons (local.get $arg3) (i32.const 0)))
                     (local.get $a))))
         (local.get $ret))

   (func $subr_remprop (result i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         (call $remprop (local.get $arg1) (local.get $arg2))
         (i32.const 0))

   (func $subr_pair (result i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         (call $pairlis (local.get $arg1) (local.get $arg2) (i32.const 0)))

   (func $subr_sassoc (result i32)
         (local $a i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local $arg3 i32)
         (local $ret i32)
         (local.set $a (call $getAArgInSubr))
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         (local.set $arg3 (call $getArg3))
         (local.set $ret (call $assoc (local.get $arg1) (local.get $arg2)))
         (if (i32.eqz (local.get $ret))
             (return
               (call $eval
                     (call $makeCatchableError
                           (global.get $ce_apply)
                           (call $cons (local.get $arg3) (i32.const 0)))
                     (local.get $a))))
         (local.get $ret))

   (func $subst (param $x i32) (param $y i32) (param $z i32) (result i32)
         (local $left i32)
         (local $right i32)
         (local $ret i32)
         (if (call $equal (local.get $y) (local.get $z))
             (return (local.get $x)))
         (if (i32.eqz (call $consp (local.get $z)))
             (return (local.get $z)))
         (local.set $left (call $subst (local.get $x) (local.get $y)
                                (call $car (local.get $z))))
         (call $push (local.get $left))  ;; For GC (left)
         (local.set $right (call $subst (local.get $x) (local.get $y)
                                 (call $cdr (local.get $z))))
         (call $push (local.get $right))  ;; For GC (left, right)
         (local.set $ret (call $cons (local.get $left) (local.get $right)))
         (call $drop (call $pop))  ;; For GC (left)
         (call $drop (call $pop))  ;; For GC ()
         (local.get $ret))
   (func $subr_subst (result i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local $arg3 i32)
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         (local.set $arg3 (call $getArg3))
         (call $subst (local.get $arg1) (local.get $arg2) (local.get $arg3)))

   (func $sublis2 (param $x i32) (param $y i32) (result i32)
         (loop $loop
            (if (i32.eqz (local.get $x))
                (return (local.get $y)))
            (if (i32.eq (call $caar (local.get $x)) (local.get $y))
                (return (call $cdar (local.get $x))))
            (local.set $x (call $cdr (local.get $x)))
            (br $loop))
         (i32.const 0))
   (func $sublis (param $x i32) (param $y i32) (result i32)
         (local $left i32)
         (local $right i32)
         (local $ret i32)
         (if (i32.eqz (call $consp (local.get $y)))
             (return (call $sublis2 (local.get $x) (local.get $y))))
         (local.set
          $left (call $sublis (local.get $x) (call $car (local.get $y))))
         (call $push (local.get $left))  ;; For GC (left)
         (local.set
          $right (call $sublis (local.get $x) (call $cdr (local.get $y))))
         (call $push (local.get $right))  ;; For GC (left, right)
         (local.set
          $ret (call $cons (local.get $left) (local.get $right)))
         (call $drop (call $pop))  ;; For GC (left)
         (call $drop (call $pop))  ;; For GC ()
         (local.get $ret))

   (func $subr_sublis (result i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         (call $sublis (local.get $arg1) (local.get $arg2)))

   (func $subr_reverse (result i32)
         (local $arg1 i32)
         (local $ret i32)
         (local.set $arg1 (call $getArg1))
         (loop $loop
            (if (i32.eqz (local.get $arg1))
                (return (local.get $ret)))
            (local.set
             $ret (call $cons (call $car (local.get $arg1)) (local.get $ret)))
            (local.set $arg1 (call $cdr (local.get $arg1)))
            (br $loop))
         (i32.const 0))

   (func $subr_member (result i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         (call $member (local.get $arg1) (local.get $arg2)))

   (func $subr_length (result i32)
         (local $arg1 i32)
         (local.set $arg1 (call $getArg1))
         (call $int2fixnum (call $length (local.get $arg1))))

   (func $subr_efface (result i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local $ret i32)
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         ;; Find the first element which is not arg1.
         (block $block1
           (loop $loop1
              (if (i32.eqz (local.get $arg2))
                  (return (i32.const 0)))
              (if (i32.ne (local.get $arg1) (call $car (local.get $arg2)))
                  (br $block1))
              (local.set $arg2 (call $cdr (local.get $arg2)))
              (br $loop1)))
         (local.set $ret (local.get $arg2))
         (loop $loop2
            (if (i32.eqz (call $cdr (local.get $arg2)))
                (return (local.get $ret)))
            (if (i32.eq (call $cadr (local.get $arg2)) (local.get $arg1))
                (call $setcdr (local.get $arg2)
                      (call $cddr (local.get $arg2)))
                ;; Don't take CDR when deleting an element.
                (local.set $arg2 (call $cdr (local.get $arg2))))
            (br $loop2))
         (i32.const 0))

   (func $subr_maplist (result i32)
         (local $a i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local $ret i32)
         (local $val i32)
         (local.set $a (call $getAArgInSubr))
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         (local.set $ret (i32.const 0))
         (loop $loop
            (if (i32.eqz (local.get $arg1))
                (return (call $nreverse (local.get $ret))))
            (call $push (local.get $ret))  ;; For GC (ret)
            (local.set $val
                       (call $eval
                             (call $makeCatchableError
                                   (global.get $ce_apply)
                                   (call $list2 (local.get $arg2)
                                         (local.get $arg1)))
                             (local.get $a)))
            (call $drop (call $pop))  ;; For GC ()
            (local.set $ret (call $cons (local.get $val) (local.get $ret)))
            (if (call $errorp (local.get $val))
                (return (local.get $val)))
            (local.set $arg1 (call $cdr (local.get $arg1)))
            (br $loop))
         (i32.const 0))
   (func $subr_mapcon (result i32)
         (call $conc (call $subr_maplist)))
   (func $subr_map (result i32)
         (local $a i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local $val i32)
         (local.set $a (call $getAArgInSubr))
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         (loop $loop
            (if (i32.eqz (local.get $arg1))
                (return (i32.const 0)))
            (local.set
             $val (call $eval
                        (call $makeCatchableError
                              (global.get $ce_apply)
                              (call $list2 (local.get $arg2)
                                    (local.get $arg1)))
                        (local.get $a)))
            (if (call $errorp (local.get $val))
                (return (local.get $val)))
            (local.set $arg1 (call $cdr (local.get $arg1)))
            (br $loop))
         (i32.const 0))

   (func $subr_search (result i32)
         (local $a i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local $arg3 i32)
         (local $arg4 i32)
         (local $val i32)
         (local.set $a (call $getAArgInSubr))
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         (local.set $arg3 (call $getArg3))
         (local.set $arg4 (call $getArg4))
         (loop $loop
            (if (i32.eqz (local.get $arg1))
                (return
                  (call $eval
                        (call $makeCatchableError
                              (global.get $ce_apply)
                              (call $list2 (local.get $arg4)
                                    (i32.const 0)))
                        (local.get $a))))
            (local.set
             $val (call $eval
                        (call $makeCatchableError
                              (global.get $ce_apply)
                              (call $list2 (local.get $arg2)
                                    (local.get $arg1)))
                        (local.get $a)))
            (if (call $errorp (local.get $val))
                (return (local.get $val)))
            (if (i32.ne (local.get $val) (i32.const 0))
                (return
                  (call $eval
                        (call $makeCatchableError
                              (global.get $ce_apply)
                              (call $list2 (local.get $arg3)
                                    (local.get $arg1)))
                        (local.get $a))))
            (local.set $arg1 (call $cdr (local.get $arg1)))
            (br $loop))
         (i32.const 0))

   (func $subr_recip (result i32)
         (local $arg1 i32)
         (local.set $arg1 (call $getArg1))
         (if (i32.eqz (call $fixnump (local.get $arg1)))
             (return (call $perr1
                           (call $makeStrError (global.get $str_err_num))
                           (local.get $arg1))))
         (call $int2fixnum (i32.const 0)))

   (func $subr_expt (result i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local $x i32)
         (local $n i32)
         (local $acc i32)
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         (if (i32.eqz (call $fixnump (local.get $arg1)))
             (return (call $perr1
                           (call $makeStrError (global.get $str_err_num))
                           (local.get $arg1))))
         (if (i32.eqz (call $fixnump (local.get $arg2)))
             (return (call $perr1
                           (call $makeStrError (global.get $str_err_num))
                           (local.get $arg2))))
         (local.set $x (call $fixnum2int (local.get $arg1)))
         (local.set $n (call $fixnum2int (local.get $arg2)))
         (local.set $acc (i32.const 1))
         (loop $loop
            (if (i32.le_s (local.get $n) (i32.const 0))
                (return (call $int2fixnum (local.get $acc))))
            (local.set $acc (i32.mul (local.get $x) (local.get $acc)))
            (local.set $n (i32.sub (local.get $n) (i32.const 1)))
            (br $loop))
         (i32.const 0))

   (func $subr_fixp (result i32)
         (local $arg1 i32)
         (local.set $arg1 (call $getArg1))
         (if (call $fixnump (local.get $arg1))
             (return (global.get $sym_tstar)))
         (i32.const 0))

   (func $subr_floatp (result i32)
         (i32.const 0))

   (func $subr_leftshift (result i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         (if (i32.eqz (call $fixnump (local.get $arg1)))
             (return (call $perr1
                           (call $makeStrError (global.get $str_err_num))
                           (local.get $arg1))))
         (if (i32.eqz (call $fixnump (local.get $arg2)))
             (return (call $perr1
                           (call $makeStrError (global.get $str_err_num))
                           (local.get $arg2))))
         (local.set $arg1 (call $fixnum2int (local.get $arg1)))
         (local.set $arg2 (call $fixnum2int (local.get $arg2)))
         (if (i32.lt_s (local.get $arg2) (i32.const 0))
             (return
               (call $int2fixnum
                     (i32.shr_s (local.get $arg1)
                                (i32.mul (local.get $arg2) (i32.const -1))))))
         (call $int2fixnum (i32.shl (local.get $arg1) (local.get $arg2))))

   (func $subr_read (result i32)
         (call $read))

   (func $subr_punch (result i32)
         (call $subr_print))

   (func $subr_gensym (result i32)
         (local $p i32)
         (local $name i32)
         (local $cell i32)
         (local $sym i32)
         (global.set
          $gensym_num (i32.add (global.get $gensym_num) (i32.const 1)))
         (local.set $p (global.get $printp))  ;; original location of `printp`
         (call $printFixnum05 (call $int2fixnum (global.get $gensym_num)))
         (i32.store8 (global.get $boffo) (i32.const 71))  ;; 'G'
         (call $strcpy
               (i32.add (global.get $boffo) (i32.const 1))
               (local.get $p))
         (global.set $printp (local.get $p))  ;; restore `printp`
         (i32.store8 (global.get $printp) (i32.const 0))
         (local.set $name (call $makename (global.get $boffo)))
         (call $push (local.get $name))  ;; For GC (name)
         (local.set
          $sym (call $cons (global.get $tag_symbol) (i32.const 0)))
         (call $push (local.get $sym))  ;; For GC (name, sym)
         (local.set $cell (call $cons (local.get $name) (i32.const 0)))
         (call $setcdr (local.get $sym) (local.get $cell))  ;; For GC
         (local.set
          $cell (call $cons (global.get $sym_pname) (local.get $cell)))
         (call $setcdr (local.get $sym) (local.get $cell))
         (call $drop (call $pop))  ;; For GC (name)
         (call $drop (call $pop))  ;; For GC ()
         (local.get $sym))

   (func $subr_remob (result i32)
         (local $arg1 i32)
         (local.set $arg1 (call $getArg1))
         (call $removeFromOblist (local.get $arg1)))

   (func $subr_evlis (result i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         (call $evlis (local.get $arg1) (local.get $arg2)))

   (func $dump (param $low i32) (param $high i32) (result i32)
         ;; 8-byte align
         (local.set $low (i32.and (local.get $low) (i32.const 0xfffffff8)))
         (local.set
          $high (i32.and (i32.add (local.get $high) (i32.const 7))
                         (i32.const 0xfffffff8)))
         (call $printString (global.get $str_msg_dump_header))
         (call $terprif)
         (loop $loop
            (if (i32.gt_u (local.get $low) (local.get $high))
                (return (i32.const 0)))
            (call $printHex08 (local.get $low))
            (call $printSpace)
            (call $printHex08 (i32.load (local.get $low)))
            (call $printSpace)
            (call $printHex08 (i32.load (i32.add (local.get $low)
                                                 (i32.const 4))))
            (call $printSpace)
            (call $printWordAsChars (i32.load (local.get $low)))
            (call $printSpace)
            (call $printWordAsChars (i32.load (i32.add (local.get $low)
                                                       (i32.const 4))))
            (call $terprif)
            (local.set $low (i32.add (local.get $low) (i32.const 8)))
            (br $loop))
         (i32.const 0))
   (func $subr_dump (result i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local $arg3 i32)
         (local $arg4 i32)
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         (local.set $arg3 (call $getArg3))
         (local.set $arg4 (call $getArg4))
         (call $printObj (local.get $arg4))
         (call $terprif)
         (call $dump
               (call $fixnum2int (local.get $arg1))
               (call $fixnum2int (local.get $arg2))))

   (func $subr_error (result i32)
         (local $arg1 i32)
         (local.set $arg1 (call $getArg1))
         (call $perr1
               (call $makeStrError (global.get $str_err_error))
               (local.get $arg1)))

   (func $subr_count (result i32)
         (local $arg1 i32)
         (local.set $arg1 (call $getArg1))
         (if (i32.eqz (local.get $arg1))
             (then
              (global.set $cons_counting (i32.const 1))  ;; Resume counting
              (return (i32.const 0))))
         (if (i32.eqz (call $fixnump (local.get $arg1)))
             (return (call $perr1
                           (call $makeStrError (global.get $str_err_num))
                           (local.get $arg1))))
         (global.set $cons_counting (i32.const 1))
         (global.set $cons_limit (call $fixnum2int (local.get $arg1)))
         (global.set $cons_count (i32.const 0))
         (i32.const 0))

   (func $subr_uncount (result i32)
         (local $arg1 i32)
         (local.set $arg1 (call $getArg1))
         ;; I don't know how the first argument is used...
         (global.set $cons_counting (i32.const 0))
         (i32.const 0))

   (func $subr_speak (result i32)
         (local $arg1 i32)
         (local.set $arg1 (call $getArg1))
         ;; I don't know how the first argument is used...
         (call $int2fixnum (global.get $cons_count)))

   (func $subr_errorset (result i32)
         (local $counting i32)
         (local $count i32)
         (local $limit i32)
         (local $suppress i32)
         (local $val i32)
         (local $ret i32)
         (local $arg1 i32)
         (local $arg2 i32)
         (local $arg3 i32)
         (local $arg4 i32)
         (local.set $arg1 (call $getArg1))
         (local.set $arg2 (call $getArg2))
         (local.set $arg3 (call $getArg3))
         (local.set $arg4 (call $getArg4))
         ;; Save the current status.
         (local.set $counting (global.get $cons_counting))
         (local.set $count (global.get $cons_count))
         (local.set $limit (global.get $cons_limit))
         (local.set $suppress (global.get $suppress_error))
         ;; Set new status
         (global.set $cons_counting (i32.const 1))
         (global.set $cons_count (i32.const 0))
         (if (i32.ne (local.get $arg2) (i32.const 0))
             (global.set $cons_limit (call $fixnum2int (local.get $arg2))))
         (global.set $suppress_error (i32.eqz (local.get $arg3)))
         ;; Evaluate arg1
         (local.set $val (call $eval (local.get $arg1) (local.get $arg4)))
         ;; Restore the status.
         (global.set $cons_counting (local.get $counting))
         (global.set $cons_count (local.get $count))
         (global.set $cons_limit (local.get $limit))
         (global.set $suppress_error (local.get $suppress))
         (if (call $errorp (local.get $val))
             (return (i32.const 0)))
         (local.set $ret (call $cons (local.get $val) (i32.const 0)))
         (local.get $ret))

   (func $subr_bwrite (result i32)
         (local $arg1 i32)
         (local.set $arg1 (call $getArg1))
         (i32.store8
          (global.get $bwritep) (call $fixnum2int (local.get $arg1)))
         (global.set $bwritep (i32.add (global.get $bwritep) (i32.const 1)))
         (local.get $arg1))

   (func $subr_bdump (result i32)
         (call $dump (global.get $bwrite_start) (global.get $bwritep)))

   (func $subr_loadwasm (result i32)
         (local $ret i32)
         (call $loadWasm
               (global.get $bwrite_start)
               (i32.sub (global.get $bwritep) (global.get $bwrite_start)))
         (local.set $ret (call $int2fixnum (global.get $next_subr)))
         (global.set
          $next_subr (i32.add (global.get $next_subr) (i32.const 1)))
         (local.get $ret))

   (func $subr_nextsubr (result i32)
         (call $int2fixnum (global.get $next_subr)))

   (func $subr_fencode (result i32)
         (local $arg1 i32)
         (local.set $arg1 (call $getArg1))
         (if (i32.ge_u (local.get $arg1) (i32.const 0xc0000000))
             ;; TODO: Return the specific error
             (return (call $perr1
                           (call $makeStrError (global.get $str_err_generic))
                           (local.get $arg1))))
         (call $int2fixnum (local.get $arg1)))

 (func $fsubr_time (result i32)
       (local $args i32)
       (local $a i32)
       (local $ret i32)
       (local $exp i32)
       (local $n i32)
       (local $start i64)
       (local $end i64)
       (local $duration i32)
       (local $prev_suppress i32)
       (local $prev_count i32)
       (local $count i32)
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       (local.set $exp (call $safecar (local.get $args)))
       (local.set $n (call $safecar (call $safecdr (local.get $args))))
       (if (call $fixnump (local.get $n))
           (local.set $n (call $fixnum2int (local.get $n)))
           (local.set $n (i32.const 1)))

       (local.set $prev_suppress (global.get $suppress_gc_msg))
       (local.set $prev_count (global.get $gc_count))
       (global.set $suppress_gc_msg (i32.const 1))
       (global.set $gc_count (i32.const 0))
       (local.set $start (call $getTimeInMs))
       (loop $loop
          (local.set
           $ret (call $eval (local.get $exp) (local.get $a)))
          (local.set $n (i32.sub (local.get $n) (i32.const 1)))
          (br_if $loop (i32.gt_s (local.get $n) (i32.const 0))))
       (local.set $end (call $getTimeInMs))
       (local.set $count (global.get $gc_count))
       (global.set $suppress_gc_msg (local.get $prev_suppress))
       (global.set $gc_count (local.get $prev_count))

       (local.set
        $duration (i32.wrap_i64 (i64.sub (local.get $end) (local.get $start))))
       (call $printComment)
       (call $printString (global.get $str_msg_time_ms))
       (call $printObj (call $int2fixnum (local.get $duration)))
       (call $terprif)
       (call $printComment)
       (call $printString (global.get $str_msg_gc_count))
       (call $printObj (call $int2fixnum (local.get $count)))
       (call $terprif)
       (call $push (i32.const 0))  ;; Don't need to eval return value
       (local.get $ret))

   (func $subr_bstart (result i32)
         (global.set $bwritep (global.get $bwrite_start))
         (i32.const 0))
 ;;; END SUBR/FSUBR

 ;;; EXPR/FEXPR/APVAL
 (global $str_expr_defs i32 (i32.const 196608))
 (data
  (i32.const 196608)  ;; 64KB * 3
  "(PUTPROP 'DEFLIST '(LAMBDA (L IND) "
  "(IF L "
  "(CONS (PUTPROP (CAR (CAR L)) (CAR (CDR (CAR L))) IND) "
  "(DEFLIST (CDR L) IND)) "
  "L)) "
  "'EXPR) "
  "(DEFLIST '((DEFINE (LAMBDA (L) (DEFLIST L 'EXPR)))) 'EXPR) "
  "(DEFINE '( "
  " (FLAG (LAMBDA (L IND) (PROG () L1 (IF (NULL L) (RETURN NIL)) "
  "  (RPLACD (CAR L) (CONS IND (CDR (CAR L)))) (SETQ L (CDR L)) (GO L1)))) "
  " (REMFLAG (LAMBDA (L IND) (IF (NULL L) NIL "
  "  (PROG () (PROG (S) (SETQ S (CAR L)) "
  "  L1 (IF (NULL (CDR S)) (RETURN NIL)) "
  "  (IF (EQ (CAR (CDR S)) IND) (RETURN (RPLACD S (CDR (CDR S))))) "
  "  (SETQ S (CDR S)) (GO L1)) (REMFLAG (CDR L) IND))))) "
  " (TRACE (LAMBDA (X) (FLAG X 'TRACE)))"
  " (UNTRACE (LAMBDA (X) (REMFLAG X 'TRACE))) "
  " (TRACESET (LAMBDA (X) (FLAG X 'TRACESET)))"
  " (UNTRACESET (LAMBDA (X) (REMFLAG X 'TRACESET))) "
  " (CSET (LAMBDA (OB VAL) (PROG2(PUTPROP OB (LIST VAL) 'APVAL) (LIST VAL)))) "
  " (PRINTPROP (LAMBDA (X) (IF (ATOM X) (PROG2 (PRINT (CDR X)) X) NIL)))"
  " (PUNCHDEF (LAMBDA (X) (PROG (V) (SETQ V (GET X 'EXPR)) "
  "  (IF V (RETURN (PROG2 (PRINT V) X))) (SETQ V (GET X 'FEXPR)) "
  "  (IF V (RETURN (PROG2 (PRINT V) X)))))) "
  " (COMMON (LAMBDA (X) (FLAG X 'COMMON)))"  ;; Will be compiled
  " (UNCOMMON (LAMBDA (X) (REMFLAG X 'COMMON))) "  ;; Will be compiled
  " (SPECIAL (LAMBDA (X) (MAP X (FUNCTION (LAMBDA (Y) "
  "  (PUTPROP (CAR Y) (LIST NIL) 'SPECIAL)))))) "  ;; Will be compiled
  " (UNSPECIAL (LAMBDA (X) (MAP X (FUNCTION (LAMBDA (Y) "
  "  (REMPROP (CAR Y) 'SPECIAL)))))) "  ;; Will be compiled
  "))"
  "(DEFLIST '( "
  " (CSETQ (LAMBDA (S A) (CSET (CAR S) (EVAL (CAR (CDR S)) A)))) "
  " (SELECT (LAMBDA (S A) ((LABEL REC (LAMBDA (V L) "
  "  (COND ((NULL L) NIL) ((NULL (CDR L)) (EVAL (CAR L) A)) "
  "  ((EQ (EVAL (CAR (CAR L)) A) V) (EVAL (CAR (CDR (CAR L))) A)) "
  "  (T (REC V (CDR L)))))) (EVAL (CAR S) A) (CDR S)))) "
  " (CONC (LAMBDA (S A) (IF (NULL S) NIL "
  "  ((LABEL REC (LAMBDA (X Y) (IF (NULL Y) X "
  "  (REC (NCONC X (EVAL (CAR Y) A)) (CDR Y))))) "
  "  (EVAL (CAR S) A) (CDR S))))) "
  ") 'FEXPR) "
  "(CSETQ DOLLAR '$) "
  "(CSETQ SLASH '/) "
  "(CSETQ LPAR '$$|(|) "
  "(CSETQ RPAR '$$|)|) "
  "(CSETQ COMMA '$$|,|) "
  "(CSETQ PERIOD '$$|.|) "
  "(CSETQ PLUSS '+) "
  "(CSETQ DASH '-) "
  "(CSETQ STAR '*) "
  "(CSETQ BLANK '$$| |) "
  "(CSETQ EQSIGN '=) "
  "(CSETQ EOF '$EOF$) "
  "(CSETQ EOR '$EOR$) "
  ;; Ichigo Lisp Utilities
  "(DEFLIST '( "
  " (DEFUN (LAMBDA (S A) (PUTPROP (CAR S) (CONS 'LAMBDA (CDR S)) 'EXPR)))"
  " (DE (LAMBDA (S A) (PUTPROP (CAR S) (CONS 'LAMBDA (CDR S)) 'EXPR)))"
  " (DF (LAMBDA (S A) (PUTPROP (CAR S) (CONS 'LAMBDA (CDR S)) 'FEXPR)))"
  ") 'FEXPR) "
  "(DEFINE '( "
  " (NOT (LAMBDA (X) (NULL X))) "
  " (CAAR (LAMBDA (X) (CAR (CAR X)))) "
  " (CADR (LAMBDA (X) (CAR (CDR X)))) "
  " (CDAR (LAMBDA (X) (CDR (CAR X)))) "
  " (CDDR (LAMBDA (X) (CDR (CDR X)))) "
  " (SCAR (LAMBDA (X) (IF (NULL X) X (CAR X)))) "
  " (SCDR (LAMBDA (X) (IF (NULL X) X (CDR X)))) "
  " (CONSP (LAMBDA (X) (NOT (ATOM X)))) "
  " (SYMBOLP (LAMBDA (X) (AND (ATOM X) (NOT (NUMBERP X))))) "
  " (POSITION (LAMBDA (KEY LST) ((LABEL REC (LAMBDA (L N) "
  "  (COND ((NULL L) NIL) ((EQ (CAR L) KEY) N) (T (REC (CDR L) (1+ N)))))) "
  "  LST 0))) "
  " (REMOVE-IF-NOT (LAMBDA (F LST) (MAPCON LST "
  "  (FUNCTION (LAMBDA (X) (IF (F (CAR X)) (LIST (CAR X)) NIL)))))) "
  " (SYMBOLS-WITH (LAMBDA (IND) (REMOVE-IF-NOT "
  "  (FUNCTION (LAMBDA (X) (GET X IND))) OBLIST)))"
  " (BWRITES (LAMBDA (LST) (MAP LST "
  "  (FUNCTION (LAMBDA (X) (BWRITE (CAR X))))))) "
  " (SYMCAT (LAMBDA (X Y) (PROG2 (MAP (NCONC (UNPACK X) (UNPACK Y)) "
  "  (FUNCTION (LAMBDA (X) (PACK (CAR X))))) "
  "  (INTERN (MKNAM))))) "
  " (SET-DIFFERENCE (LAMBDA (X Y) (COND ((NULL X) NIL) "
  "  ((MEMBER (CAR X) Y) (SET-DIFFERENCE (CDR X) Y)) "
  "  (T (CONS (CAR X) (SET-DIFFERENCE (CDR X) Y)))))) "
  " (REMOVE-DUPLICATES (LAMBDA (X) (COND ((NULL X) NIL) "
  "  ((MEMBER (CAR X) (CDR X)) (REMOVE-DUPLICATES (CDR X))) "
  "  (T (CONS (CAR X) (REMOVE-DUPLICATES (CDR X))))))) "
  ")) "
  ;; Compiler (WIP)
  ;; https://en.wikipedia.org/wiki/LEB128
  "(DE ULEB128 (N) (PROG (B V) "
  " (SETQ B (LOGAND N 0x7F)) "
  ;; Suppress sign extension. Note that fixnum is 30 bit.
  " (SETQ V (LOGAND (LEFTSHIFT N -7) 0x7fffff)) "
  " (RETURN "
  "  (IF (ZEROP V) "
  "   (CONS B NIL) "
  "   (CONS (LOGOR B 0x80) (ULEB128 V)))))) "
  "(DE LEB128 (N) (PROG (B V) "
  " (SETQ B (LOGAND N 0x7F)) "
  " (SETQ V (LEFTSHIFT N -7)) "
  " (RETURN "
  "  (IF (OR (AND (ZEROP V) (ZEROP (LOGAND B 0x40))) "
  "          (AND (EQ V -1) (NOT (ZEROP (LOGAND B 0x40))))) "
  "   (CONS B NIL) "
  "   (CONS (LOGOR B 0x80) (LEB128 V)))))) "
  "(DE C::WASM-HEADER () (PROG () "
  " (BWRITES '(0x00 0x61 0x73 0x6d)) "
  " (BWRITES '(0x01 0x00 0x00 0x00)) "
  ")) "
  "(DE C::TYPE-SECTION () (PROG () "
  " (BWRITE 0x01) "  ;; section number
  " (BWRITE 0x26) "  ;; section size
  " (BWRITE 0x07) "  ;; 7 entry
  " (BWRITE 0x60) "  ;; functype (void -> i32)
  " (BWRITE 0x00) "  ;; no arguments
  " (BWRITE 0x01) "  ;; 1 value
  " (BWRITE 0x7f) "  ;; i32
  " (BWRITE 0x60) "  ;; functype (i32 -> void)
  " (BWRITE 0x01) "  ;; 1 parameter
  " (BWRITE 0x7f) "  ;; i32
  " (BWRITE 0x00) "  ;; 0 value
  " (BWRITE 0x60) "  ;; functype (i32 -> i32)
  " (BWRITE 0x01) "  ;; 1 parameter
  " (BWRITE 0x7f) "  ;; i32
  " (BWRITE 0x01) "  ;; 1 value
  " (BWRITE 0x7f) "  ;; i32
  " (BWRITE 0x60) "  ;; functype (i32*i32 -> i32)
  " (BWRITE 0x02) "  ;; 2 parameters
  " (BWRITE 0x7f) "  ;; i32
  " (BWRITE 0x7f) "  ;; i32
  " (BWRITE 0x01) "  ;; 1 value
  " (BWRITE 0x7f) "  ;; i32
  " (BWRITE 0x60) "  ;; functype (i32*i32 -> void)
  " (BWRITE 0x02) "  ;; 2 parameters
  " (BWRITE 0x7f) "  ;; i32
  " (BWRITE 0x7f) "  ;; i32
  " (BWRITE 0x00) "  ;; 0 value
  " (BWRITE 0x60) "  ;; functype (i32*i32*i32 -> i32)
  " (BWRITE 0x03) "  ;; 3 parameters
  " (BWRITE 0x7f) "  ;; i32
  " (BWRITE 0x7f) "  ;; i32
  " (BWRITE 0x7f) "  ;; i32
  " (BWRITE 0x01) "  ;; 1 value
  " (BWRITE 0x7f) "  ;; i32
  " (BWRITE 0x60) "  ;; functype (i32*i32*i32 -> void)
  " (BWRITE 0x03) "  ;; 3 parameters
  " (BWRITE 0x7f) "  ;; i32
  " (BWRITE 0x7f) "  ;; i32
  " (BWRITE 0x7f) "  ;; i32
  " (BWRITE 0x00) "  ;; 0 value
  ")) "
  "(DE C::IMPORT-SECTION (MEM TBL) (PROG (MS TS SS)"
  " (SETQ MS (ULEB128 MEM)) "
  " (SETQ TS (ULEB128 TBL)) "
  " (SETQ SS (+ 0x19 (LENGTH MS) (LENGTH TS))) "
  " (BWRITE 0x02) "  ;; section number
  " (BWRITE SS) "  ;; section size
  " (BWRITE 0x02) "  ;; 2 entries
  ;; "js" "memory" memory limit is ...
  " (BWRITES '(0x02 0x6a 0x73 0x06 0x6d 0x65 0x6d 0x6f 0x72 0x79 0x02 0x00)) "
  " (BWRITES MS) "  ;; memory size
  ;; "js" "table" table limit is ...
  " (BWRITES '(0x02 0x6a 0x73 0x05 0x74 0x61 0x62 0x6c 0x65 0x01 0x70 0x00)) "
  " (BWRITES TS) "  ;; table size
  "))"
  "(DE C::FUNC-SECTION () (PROG () "
  " (BWRITE 0x03) "  ;; section number
  " (BWRITE 0x02) "  ;; section size
  " (BWRITE 0x01) "  ;; 1 entry
  " (BWRITE 0x00) "  ;; type index 0 (v2i)
  ")) "
  "(DE C::ELM-SECTION (SIDX) (PROG (I) "
  " (SETQ I (ULEB128 SIDX)) "
  " (BWRITE 0x09) "  ;; section number
  " (BWRITE (+ 0x06 (LENGTH I))) "  ;; section size
  " (BWRITE 0x01) "  ;; 1 entry
  " (BWRITE 0x00) "  ;; table index 0
  " (BWRITE 0x41) "  ;; i32.const
  " (BWRITES I) "
  " (BWRITE 0x0b) "  ;; end
  " (BWRITE 0x01) "  ;; 1 function
  " (BWRITE 0x00) "  ;; function index 0 (see function section)
  ")) "
  "(DE C::CODE-SECTION (ASM) (PROG (INST LEN CS SS) "
  " (SETQ INST (C::ASSEMBLE-CODE ASM 0)) "
  " (SETQ LEN (LENGTH INST)) "
  " (SETQ CS (ULEB128 (+ 0x0b (LENGTH INST)))) "
  " (SETQ SS (ULEB128 (+ 0x0c (LENGTH INST) (LENGTH CS)))) "
  " (BWRITE 0x0a) "  ;; section number
  " (BWRITES SS) "  ;; section size
  " (BWRITE 0x01) "  ;; 1 entry
  " (BWRITES CS) "  ;; code size
  " (BWRITE 0x01) "  ;; 1 local variable sets
  " (BWRITE 0x02) "  ;; 2 local variables with the same type ($frame, $idx)
  " (BWRITE 0x7f) "  ;; i32
  ;; Init frame pointer
  " (BWRITE 0x41) "  ;; i32.const
  " (BWRITE 0x00) "  ;; 0 ($getsp)
  " (BWRITE 0x11) "  ;; call_indirect
  " (BWRITE 0x00) "  ;; type index 0 (v2i)
  " (BWRITE 0x00) "  ;; end of call_indirect
  " (BWRITE 0x21) "  ;; local.set
  " (BWRITE 0x00) "  ;; local index 0 ($frame)
  ;;; Body instructions
  " (BWRITES INST) "
  " (BWRITE 0x0b) "  ;; end
  ")) "
  "(DE C::ASSEMBLE (ASM) (PROG (SIDX) "
  " (SETQ SIDX (NEXT-SUBR)) "
  " (C::WASM-HEADER )"
  " (C::TYPE-SECTION) "
  " (C::IMPORT-SECTION 6 512) "
  " (C::FUNC-SECTION) "
  " (C::ELM-SECTION SIDX) "
  " (C::CODE-SECTION ASM) "
  ")) "
  "(DE C::ASSEMBLE-CODE (X L) "
  " (COND "
  "  ((ATOM X) (C::ASSEMBLE-ATOM X L)) "
  "  ((EQ (CAR X) 'CONST) (C::ASSEMBLE-CONST (CADR X) L)) "
  "  ((EQ (CAR X) 'GET-LOCAL) (C::ASSEMBLE-GET-LOCAL (CADR X) L)) "
  "  ((EQ (CAR X) 'SET-LOCAL) (C::ASSEMBLE-SET-LOCAL (CDR X) L)) "
  "  ((EQ (CAR X) 'CALL) (C::ASSEMBLE-CALL (CDR X) L)) "
  "  ((EQ (CAR X) 'LOAD) (C::ASSEMBLE-LOAD (CDR X) L)) "
  "  ((EQ (CAR X) 'STORE) (C::ASSEMBLE-STORE (CDR X) L)) "
  "  ((EQ (CAR X) 'PROGN) (C::ASSEMBLE-PROGN (CDR X) L)) "
  "  ((EQ (CAR X) 'BLOCK) (C::ASSEMBLE-BLOCK (CDR X) L)) "
  "  ((EQ (CAR X) 'IF) (C::ASSEMBLE-IF (CDR X) L)) "
  "  ((EQ (CAR X) 'WHEN) (C::ASSEMBLE-WHEN (CDR X) L)) "
  "  ((EQ (CAR X) 'LOOP) (C::ASSEMBLE-LOOP (CDR X) L)) "
  "  ((EQ (CAR X) '<) (C::ASSEMBLE-LESS (CDR X) L)) "
  "  ((EQ (CAR X) 'RETURN) (C::ASSEMBLE-RETURN (CADR X) L)) "
  "  ((EQ (CAR X) 'BR-LOOP) (C::ASSEMBLE-BR-LOOP (CDR X) L)) "
  "  ((EQ (CAR X) 'BR-BLOCK) (C::ASSEMBLE-BR-BLOCK (CDR X) L)) "
  "  (T (ERROR (SYMCAT (CAR X) '$$| is not asm opcode|))))) "
  "(DE C::ASSEMBLE-ATOM (X L) "
  " (COND "
  "  ((FIXP X) (CONS 0x41 (LEB128 X))) "
  "  (T (ERROR (SYMCAT X '$$| is not supported asm instruction|))))) "
  "(DE C::ENCODE-FIXNUM (X) "
  " (+ (LEFTSHIFT X 2) 2)) "
  "(DE C::ASSEMBLE-CONST (X L) "  ;; X of (CONST X)
  " (COND "
  "  ((NULL X) (LIST 0x41 0x00)) "
  "  ((FIXP X) (CONS 0x41 (LEB128 (C::ENCODE-FIXNUM X)))) "
  "  ((OR (SYMBOLP X) (CONSP X)) (CONS 0x41 (LEB128 (FENCODE X)))) "
  "  (T (ERROR (SYMCAT X '$$| is not supported const|))))) "
  "(DE C::ASSEMBLE-GET-LOCAL (X L) "  ;; X of (GET-LOCAL X)
  " (CONS 0x20 (LEB128 X))) "
  "(DE C::ASSEMBLE-SET-LOCAL (X L) "  ;; X of (SET-LOCAL X=(idx val))
  " (NCONC (C::ASSEMBLE-CODE (CADR X) L) (CONS 0x21 (LEB128 (CAR X))))) "
  "(DE C::ASSEMBLE-TYPE (X) "
  " (COND "
  "  ((EQ X 'V2I) 0) "
  "  ((EQ X 'I2V) 1) "
  "  ((EQ X 'I2I) 2) "
  "  ((EQ X 'II2I) 3) "
  "  ((EQ X 'II2V) 4) "
  "  ((EQ X 'III2I) 5) "
  "  ((EQ X 'III2V) 6) "
  "  (T (ERROR (SYMCAT X '$$| is not supported type|))))) "
  "(DE C::ASSEMBLE-CALL (X L) "  ;; X of (CALL . X=(TYPE . ARGS))
  " (NCONC "
     ;; Push arguments
  "  (MAPCON (CDR X) (FUNCTION (LAMBDA (Y) "
  "   (C::ASSEMBLE-CODE (CAR Y) L)))) "
     ;; Call the function.
  "  (LIST 0x11 (C::ASSEMBLE-TYPE (CAR X)) 0x00))) "  ;; call_indirect
  "(DE C::ASSEMBLE-LOAD (X L) "  ;; X of (LOAD . X=(CELL))
  " (NCONC "
     ;; Push the address
  "  (MAPCON X (FUNCTION (LAMBDA (Y) "
  "   (C::ASSEMBLE-CODE (CAR Y) L)))) "
     ;; Load
  "  (LIST 0x28 0x02 0x00))) "  ;; align=2 (I'm not sure if it's necessary)
  "(DE C::ASSEMBLE-STORE (X L) "  ;; X of (STORE . X=(CELL VAL))
  " (NCONC "
     ;; Push the address and value
  "  (MAPCON X (FUNCTION (LAMBDA (Y) "
  "   (C::ASSEMBLE-CODE (CAR Y) L)))) "
     ;; Store
  "  (LIST 0x36 0x02 0x00))) "  ;; align=2 (I'm not sure if it's necessary)
  "(DE C::ASSEMBLE-PROGN (X L) "  ;; X of (PROGN . X)
  " (MAPCON X (FUNCTION (LAMBDA (Y) "
  "   (C::ASSEMBLE-CODE (CAR Y) L))))) "
  "(DE C::ASSEMBLE-BLOCK (X L) "  ;; X of (BLOCK . X)
  " (CONC "
  "  (LIST 0x02 0x7f)"  ;; block with i32
  "  (MAPCON X (FUNCTION (LAMBDA (Y) "
  "    (C::ASSEMBLE-CODE (CAR Y) (1+ L))))) "
  "  (LIST 0x0b))) "
  "(DE C::ASSEMBLE-IF (X L) "  ;; X of (IF . X)
  " (CONC "
  "  (C::ASSEMBLE-CODE (CAR X) L) "
  "  (LIST 0x04 0x7f) "  ;; if with i32
  "  (C::ASSEMBLE-CODE (CADR X) (1+ L)) "
  "  (LIST 0x05) "  ;; else
  "  (C::ASSEMBLE-CODE (CAR (CDDR X)) (1+ L)) "
  "  (LIST 0x0b))) "
  "(DE C::ASSEMBLE-WHEN (X L) "  ;; X of (WHEN . X)
  " (CONC "
  "  (C::ASSEMBLE-CODE (CAR X)) L "
  "  (LIST 0x04 0x40) "  ;; if without value
  "  (C::ASSEMBLE-CODE (CADR X) (1+ L)) "
  "  (LIST 0x0b))) "
  "(DE C::ASSEMBLE-LOOP (X L) "  ;; X of (LOOP . X)
  " (CONC "
  "  (LIST 0x03 0x40) "  ;; loop without value
  "  (C::ASSEMBLE-CODE (CAR X) (1+ L)) "
  "  (LIST 0x0b))) "
  "(DE C::GET-CONSTS (ASM L) "
  " (REMOVE-DUPLICATES ((LABEL REC (LAMBDA (AS) "
  "   (COND "
  "    ((ATOM AS) NIL) "
  "    ((AND (EQ (CAR AS) 'CONST) (CADR AS) (NOT (NUMBERP (CADR AS)))) "
  "     (LIST (CADR AS))) "
  "    (T (MAPCON (CDR AS) (FUNCTION (LAMBDA (Y) (REC (CAR Y))))))))) "
  "  ASM))) "
  "(DE C::ASSEMBLE-LESS (X L) "  ;; X of (< . X=(a b))
  " (CONC "
  "  (C::ASSEMBLE-CODE (CAR X) L) "
  "  (C::ASSEMBLE-CODE (CADR X) L) "
  "  (LIST 0x48))) "  ;; i32.lt_s
  "(DE C::ASSEMBLE-RETURN (X L) "  ;; X of (RETURN X)
  " (CONC "
  "  (C::ASSEMBLE-CODE X L) "
  "  (LIST 0x0f))) "  ;; return
  "(DE C::ASSEMBLE-BR-LOOP (X L) "  ;; X of (BR-LOOP . X=NIL)
  "  (CONS 0x0c (LEB128 (- L 2)))) "  ;; br
  "(DE C::ASSEMBLE-BR-BLOCK (X L) "  ;; X of (BR-BLOCK . X=NIL)
  "  (CONS 0x0c (LEB128 (- L 1)))) "  ;; br
  "(DE C::COMPILE-ARG (N L) "
  " (IF (< N 4) "
  "  (LIST 'CALL 'I2I (LIST 'GET-LOCAL 0) (+ 11 N)) " ;; 11: getArgF1
  "  (LIST 'CALL 'II2I (LIST 'GET-LOCAL 0) N 15))) " ;; 15: getArgFN
  "(DE C::COMPILE-APVAL (CELL) "
  " (LIST 'CALL 'I2I "
  "  (LIST 'LOAD (LIST 'CONST CELL)) "
  "  4))"  ;; 4: car
  "(DE C::COMPILE-GET-ALIST-VAR (X) "
  " (LIST 'CALL 'II2I "
  "  (LIST 'CONST X) "
  "  (LIST 'CALL 'I2I (LIST 'GET-LOCAL 0) 10) "  ;; 10: getAArgFInSubr
  "  25)) "  ;; 25: getVarInAlist
  "(DE C::COMPILE-SPECIAL-VAR (CELL) "
  " (LIST 'CALL 'I2I "
  "  (LIST 'LOAD (LIST 'CONST CELL)) "
  "  4))"  ;; 4: car
  "(DE C::COMPILE-ATOM (X ARGS) "
  " (COND "
  "  ((NULL X) (LIST 'CONST NIL)) "
  "  ((FIXP X) (LIST 'CONST X)) "
  "  ((GET X 'APVAL) (C::COMPILE-APVAL (PROP X 'APVAL))) "
  "  ((GET X 'COMMON) (C::COMPILE-GET-ALIST-VAR X)) "
  "  ((GET X 'SPECIAL) (C::COMPILE-SPECIAL-VAR (PROP X 'SPECIAL))) "
  "  ((POSITION X ARGS) (C::COMPILE-ARG (POSITION X ARGS))) "
  "  ((SYMBOLP X) (C::COMPILE-GET-ALIST-VAR X)) "
  "  (T (ERROR (SYMCAT X '$$| is not supported atom|))))) "
  "(DE C::COMPILE-SUBR-CALL (SYM ARGS SB AA) "
  " (CONC "
  "  (LIST 'PROGN) "
     ;; Push alist (10: getAArgFInSubr)
  "  (LIST (LIST 'CALL 'I2V (LIST 'CALL 'I2I (LIST 'GET-LOCAL 0) 10) 1)) "
     ;; Push arguments
  "  (MAPLIST AA "
  "   (FUNCTION (LAMBDA (Y) "
  "    (LIST 'CALL 'I2V (C::COMPILE-CODE SYM ARGS (CAR Y)) 1)))) "  ;; 1: push
  "  (LIST (LIST 'CALL 'II2I (CAR SB) (LENGTH AA) 20)))) "  ;; 20: subrCall
  ;;; FN and ALST must be an instruction
  "(DE C::COMPILE-FUNC-CALL-WITH-ALIST (SYM ARGS FN AA ALST) "
  " (CONC "
  "  (LIST 'PROGN ALST) "
     ;; Push arguments
  "  (MAPLIST AA "
  "   (FUNCTION (LAMBDA (Y) "
  "    (LIST 'CALL 'I2V (C::COMPILE-CODE SYM ARGS (CAR Y)) 1)))) "  ;; 1: push
     ;; Call FN
  "  (LIST (LIST 'CALL 'II2I FN (LENGTH AA) 21)))) "  ;; 21: funcCall
  ;;; FN must be an instruction
  "(DE C::COMPILE-FUNC-CALL (SYM ARGS FN AA) "
  " (C::COMPILE-FUNC-CALL-WITH-ALIST SYM ARGS FN AA"
     ;; Push the alist (10: getAArgFInSubr)
  "  (LIST 'CALL 'I2V (LIST 'CALL 'I2I (LIST 'GET-LOCAL 0) 10) 1))) "
  "(DE C::COMPILE-FSUBR-CALL (SYM ARGS FS E) "
  " (CONC "
  "  (LIST 'PROGN) "
     ;; Push expression
  "  (LIST (LIST 'CALL 'I2V (LIST 'CONST E) 1)) "
     ;; Push alist (22: createAlistFromStack)
  "  (LIST (LIST 'CALL 'I2V "
  "   (LIST 'CALL 'II2I (LIST 'GET-LOCAL 0) (LIST 'CONST ARGS) 22) 1)) "
  "  (LIST (LIST 'CALL 'I2I FS 23)))) "  ;; 23: fsubrCall
  "(DE C::COMPILE-FEXPR-CALL (SYM ARGS FE E) "
  " (CONC "
  "  (LIST 'PROGN) "
     ;; Push dummy unused alist
  "  (LIST (LIST 'CALL 'I2V (LIST 'CONST NIL) 1)) "
     ;; Push arguments
  "  (LIST (LIST 'CALL 'I2V (LIST 'CONST (CDR E)) 1)) "
     ;; Push actual alist (22: createAlistFromStack)
  "  (LIST (LIST 'CALL 'I2V "
  "   (LIST 'CALL 'II2I (LIST 'GET-LOCAL 0) (LIST 'CONST ARGS) 22) 1)) "
  "  (LIST (LIST 'CALL 'II2I (LIST 'CONST FE) 2 21)))) "  ;; 21: funcCall
  "(DE C::COMPILE-SYM-CALL (SYM ARGS X) (PROG (SB FS EX FE) "
  " (SETQ SB (GET (CAR X) 'SUBR)) "
  " (SETQ FS (GET (CAR X) 'FSUBR)) "
  " (SETQ EX (GET (CAR X) 'EXPR)) "
  " (SETQ FE (GET (CAR X) 'FEXPR)) "
  " (RETURN (COND "
  "  (FE "
  "   (C::COMPILE-FEXPR-CALL SYM ARGS FE X)) "
  "  (FS "
  "   (C::COMPILE-FSUBR-CALL SYM ARGS FS X)) "
     ;; Primitive SUBRs
  "  ((AND SB (< (CAR SB) 300)) "  ;; <300 means primitive SUBRs
  "   (C::COMPILE-SUBR-CALL SYM ARGS SB (CDR X))) "
     ;; Prefer global function
  "  ((OR SB EX) "
  "   (C::COMPILE-FUNC-CALL SYM ARGS (LIST 'CONST (CAR X)) (CDR X))) "
     ;; Call local function if exists
  "  ((AND (MEMBER (CAR X) ARGS) "
  "    (NOT (GET (CAR X) 'COMMON)) (NOT (GET (CAR X) 'SPECIAL))) "
  "   (C::COMPILE-FUNC-CALL SYM ARGS "
  "    (C::COMPILE-ARG (POSITION (CAR X) ARGS)) (CDR X))) "
     ;; Special variable
  "  ((GET (CAR X) 'SPECIAL) "
  "   (C::COMPILE-FUNC-CALL SYM ARGS "
  "    (C::COMPILE-SPECIAL-VAR (PROP (CAR X) 'SPECIAL)) (CDR X))) "
     ;; Assume the function will be defined later
  "  (T (C::COMPILE-FUNC-CALL SYM ARGS (LIST 'CONST (CAR X)) (CDR X))))))) "
  "(DE C::COMPILE-IF-CALL (SYM ARG X) "  ;; X of (IF . X=(c th el))
  " (LIST 'IF "
  "  (C::COMPILE-CODE SYM ARG (SCAR X)) "
  "  (C::COMPILE-CODE SYM ARG (SCAR (SCDR X))) "
  "  (C::COMPILE-CODE SYM ARG (SCAR (SCDR (SCDR X)))))) "
  "(DE C::COMPILE-QUOTE-CALL (SYM ARG X) "  ;; X of (QUOTE . X=(exp))
  " (LIST 'CONST (SCAR X))) "
  "(DE C::COMPILE-LSUBR-CALL (SYM ARGS IDX X) "
  " (C::COMPILE-SUBR-CALL SYM ARGS (LIST IDX 2) X)) "
  "(DE C::COMPILE-FUNCTION-CALL (SYM ARG X) "  ;; X of (FUNCTION . X=(fn))
  " (LIST 'CALL 'II2I "
     ;; Create alist (22: createAlistFromStack)
  "  (LIST 'CALL 'II2I (LIST 'GET-LOCAL 0) (LIST 'CONST ARGS) 22) "
  "  (LIST 'CONST (C::CREATE-SUBR-FROM-LAMBDA (CAR X))) "
  "  24)) "  ;; 24: createFunarg
  "(DE C::COMPILE-LABEL-CALL (SYM ARG X) (PROG (SB) "   ;; X of (LABEL . X)
  " (SETQ SB (C::CREATE-SUBR-FROM-LAMBDA (CADR X))) "
  " (RETURN (LIST 'CALL 'III2I "
     ;; Create alist (22: createAlistFromStack)
  "  (LIST 'CALL 'II2I (LIST 'GET-LOCAL 0) (LIST 'CONST ARGS) 22) "
  "  (LIST 'CONST SB) "
  "  (LIST 'CONST (CAR X)) "
  "  26)))) "  ;; 26: createLabelFunarg
  "(DE C::COMPILE-CSETQ-CALL (SYM ARG X) "   ;; X of (CSETQ . X)
  " (LIST 'CALL 'II2I "
  "  (LIST 'CONST (CAR X)) "
  "  (C::COMPILE-CODE SYM ARG (CADR X))"
  "  27)) "  ;; 27: apvalSet
  "(DE C::COMPILE-SETQ-CALL (SYM ARG X) (PROG (N)  "   ;; X of (SETQ . X)
  " (SETQ N (POSITION (CAR X) ARGS))"
  " (RETURN (COND "
     ;; Set var in special cell
  "  ((GET (CAR X) 'SPECIAL) "
  "   (LIST 'PROGN "
  "    (LIST 'CALL 'I2V (C::COMPILE-CODE SYM ARG (CADR X)) 1) "  ;; 1: push
  "   (LIST 'STORE "
  "    (LIST 'CALL 'I2I (LIST 'CONST (PROP (CAR X) 'SPECIAL)) 4) "  ;; 4: car
  "    (LIST 'CALL 'V2I 7)) "  ;; 7: peek
  "    (LIST 'CALL 'V2I 2))) "  ;; 2: pop (val)
     ;; Set var in alist
  "  ((OR (NOT N) (GET (CAR X) 'COMMON)) "
  "   (LIST 'CALL 'III2I "
  "    (LIST 'CONST (CAR X)) "
  "    (C::COMPILE-CODE SYM ARG (CADR X)) "
  "    (LIST 'CALL 'I2I (LIST 'GET-LOCAL 0) 10) "  ;; 10: getAArgFInSubr
  "    28)) "  ;; 28: setVarInAlist
     ;; Set var in stack
  "  (T "
  "   (LIST 'PROGN "
  "    (LIST 'CALL 'I2V (C::COMPILE-CODE SYM ARG (CADR X)) 1) "  ;; 1: push
  "    (IF (< N 4) "
  "     (LIST 'CALL 'II2V "
  "      (LIST 'GET-LOCAL 0) "
  "      (LIST 'CALL 'V2I 7) "  ;; 7: peek (val)
  "      (+ 31 N)) "  ;; ;; 31: setArgF1
  "     (LIST 'CALL 'III2V "
  "      (LIST 'GET-LOCAL 0) "
  "      N"
  "      (LIST 'CALL 'V2I 7) "  ;; 7: peek (val)
  "      35)) "  ;; ;; 35: setArgFN
  "    (LIST 'CALL 'V2I 2))))))) "  ;; 2: pop (val)
  "(DE C::CREATE-SUBR-FROM-PROG (PR) (PROG (IDX-OBJ) "
  " (SETQ IDX-OBJ (C::COMPILE-PROG PR)) "
  " (RETURN (LIST 'SUBR (CAR IDX-OBJ) (LENGTH (CADR FN)) (CDR IDX-OBJ))))) "
  "(DE C::COMPILE-PROG-CALL (SYM ARG X) "   ;; X of whole (PROG ...)
  "   (C::COMPILE-FUNC-CALL-WITH-ALIST SYM ARGS "
  "    (LIST 'CONST (C::CREATE-SUBR-FROM-PROG X)) "
  "    NIL "  ;; no arguments
       ;; Push alist (22: createAlistFromStack)
  "    (LIST 'CALL 'I2V "
  "     (LIST 'CALL 'II2I (LIST 'GET-LOCAL 0) (LIST 'CONST ARGS) 22) 1))) "
  "(DE C::COMPILE-RETURN-CALL (FI ARG X) "   ;; X of (RETURN . X)
  " (IF (OR (ATOM FI) (NOT (EQ (CAR FI) 'PROG))) "
  "  (ERROR '$$|RETURN cannot be used outside PROG|) "
  "  (LIST 'PROGN (C::COMPILE-CODE FI ARG (CAR X)) (LIST 'BR-BLOCK)))) "
  "(DE C::COMPILE-GO-CALL (FI ARG X) "   ;; X of (GO . X=(label))
  " (IF (OR (ATOM FI) (NOT (EQ (CAR FI) 'PROG))) "
  "  (ERROR '$$|GO cannot be used outside PROG|) "
  "  (LIST 'PROGN "
  "   (LIST 'SET-LOCAL 1 (1+ (POSITION (CAR X) (CADR FI)))) "
  "   (LIST 'BR-LOOP)))) "
  "(DE C::COMPILE-SPECIAL-CALL (SYM ARG X) "
  " (COND "
  "  ((EQ (CAR X) 'IF) (C::COMPILE-IF-CALL SYM ARG (CDR X))) "
  "  ((EQ (CAR X) 'QUOTE) (C::COMPILE-QUOTE-CALL SYM ARG (CDR X))) "
  "  ((EQ (CAR X) 'LOGAND2) (C::COMPILE-LSUBR-CALL SYM ARG 204 (CDR X))) "
  "  ((EQ (CAR X) 'LOGOR2) (C::COMPILE-LSUBR-CALL SYM ARG 205 (CDR X))) "
  "  ((EQ (CAR X) 'LOGXOR2) (C::COMPILE-LSUBR-CALL SYM ARG 206 (CDR X))) "
  "  ((EQ (CAR X) 'MAX2) (C::COMPILE-LSUBR-CALL SYM ARG 207 (CDR X))) "
  "  ((EQ (CAR X) 'MIN2) (C::COMPILE-LSUBR-CALL SYM ARG 208 (CDR X))) "
  "  ((EQ (CAR X) 'PLUS2) (C::COMPILE-LSUBR-CALL SYM ARG 209 (CDR X))) "
  "  ((EQ (CAR X) 'TIMES2) (C::COMPILE-LSUBR-CALL SYM ARG 210 (CDR X))) "
  "  ((EQ (CAR X) 'FUNCTION) (C::COMPILE-FUNCTION-CALL SYM ARG (CDR X))) "
  "  ((EQ (CAR X) 'LABEL) (C::COMPILE-LABEL-CALL SYM ARG (CDR X))) "
  "  ((EQ (CAR X) 'CSETQ) (C::COMPILE-CSETQ-CALL SYM ARG (CDR X))) "
  "  ((EQ (CAR X) 'SETQ) (C::COMPILE-SETQ-CALL SYM ARG (CDR X))) "
  "  ((EQ (CAR X) 'PROG) (C::COMPILE-PROG-CALL SYM ARG X)) "  ;; Use whole X
  "  ((EQ (CAR X) 'RETURN) (C::COMPILE-RETURN-CALL SYM ARG (CDR X))) "
  "  ((EQ (CAR X) 'GO) (C::COMPILE-GO-CALL SYM ARG (CDR X))) "
  "  (T (ERROR (SYMCAT (CAR X) '$$| is not supported special fn|))))) "
  "(DE C::SPECIALFNP (X) "
  " (MEMBER X '(IF QUOTE LOGAND2 LOGOR2 LOGXOR2 MAX2 MIN2 PLUS2 TIMES2 "
  "  FUNCTION LABEL CSETQ SETQ PROG GO RETURN))) "
  "(DE C::CREATE-SUBR-FROM-LAMBDA (FN) (PROG (IDX-OBJ) "
  " (C::VERIFY0 'LAMBDA FN) "
  " (SETQ IDX-OBJ (C::COMPILE-LAMBDA 'LAMBDA FN)) "
  " (RETURN (LIST 'SUBR (CAR IDX-OBJ) (LENGTH (CADR FN)) (CDR IDX-OBJ))))) "
  "(DE C::COMPILE-LIST-CALL (SYM ARGS FN AA) "
  " (COND "
  "  ((EQ (CAR FN) 'LAMBDA) "
  "   (C::COMPILE-FUNC-CALL-WITH-ALIST SYM ARGS "
  "    (LIST 'CONST (C::CREATE-SUBR-FROM-LAMBDA FN)) AA "
       ;; Push alist (22: createAlistFromStack)
  "    (LIST 'CALL 'I2V "
  "     (LIST 'CALL 'II2I (LIST 'GET-LOCAL 0) (LIST 'CONST ARGS) 22) 1))) "
  "  (T (C::COMPILE-FUNC-CALL SYM ARGS (C::COMPILE-CODE SYM ARGS FN) AA)))) "
  "(DE C::COMPILE-COMP (SYM ARGS X) "
  " (COND "
  "  ((C::SPECIALFNP (CAR X)) (C::COMPILE-SPECIAL-CALL SYM ARGS X)) "
  "  ((ATOM (CAR X)) (C::COMPILE-SYM-CALL SYM ARGS X)) "
  "  (T (C::COMPILE-LIST-CALL SYM ARGS (CAR X) (CDR X))))) "
  "(DE C::COMPILE-CODE (SYM ARGS X) "
  " (COND "
  "  ((ATOM X) (C::COMPILE-ATOM X ARGS)) "
  "  (T (C::COMPILE-COMP SYM ARGS X)))) "
  "(DE C::INIT-CV-STACK1 (V N) "
  " (IF (< N 4) "
  "  (LIST 'CALL 'II2V "
  "   (LIST 'GET-LOCAL 0) "
  "   (LIST 'CALL 'II2I (LIST 'CONST 'C::VCTAG) "
  "    (LIST 'CALL 'II2I (LIST 'CONST V) (C::COMPILE-ARG N) 6) 6) "  ;; 6: cons
  "   (+ 31 N)) "  ;; 31: setArgF1
  "  (LIST 'CALL 'III2V "
  "   (LIST 'GET-LOCAL 0) "
  "   N"
  "   (LIST 'CALL 'II2I (LIST 'CONST 'C::VCTAG) "
  "    (LIST 'CALL 'II2I (LIST 'CONST V) (C::COMPILE-ARG N) 6) 6) "  ;; 6: cons
  "   35))) "  ;; 35: setArgFN
  "(DE C::INIT-CV-STACK (ARGS CV) "
  " (MAPLIST CV (FUNCTION (LAMBDA (Y) "
  "  (C::INIT-CV-STACK1 (CAR Y) (POSITION (CAR Y) ARGS)))))) "
  "(DE C::REPLACE-CV-REF (ARGS EXP CV) "
  " (COND "
  "  ((NULL CV) EXP) "
  "  ((ATOM EXP) (IF (MEMBER EXP CV) (LIST 'CDDR EXP) EXP)) "
  "  ((EQ (CAR EXP) 'SETQ) "
  "   (IF (MEMBER (CADR EXP) CV) "
  "    (LIST 'RPLACD (LIST 'CDR (CADR EXP)) "
  "     (C::REPLACE-CV-REF ARGS (CAR (CDDR EXP)) CV)) "
  "    (LIST 'SETQ (CADR EXP) "
  "     (C::REPLACE-CV-REF ARGS (CAR (CDDR EXP)) CV)))) "
  "  ((EQ (CAR EXP) 'QUOTE) EXP) "
  "  ((EQ (CAR EXP) 'LAMBDA) EXP) "
  "  ((EQ (CAR EXP) 'PROG) EXP) "
  "  ((GET (CAR EXP) 'FSUBR) EXP) "
  "  ((GET (CAR EXP) 'FEXPR) EXP) "
  "  (T (CONS (C::REPLACE-CV-REF ARGS (CAR EXP) CV) "
  "           (C::REPLACE-CV-REF ARGS (CDR EXP) CV))))) "
  "(DE C::INIT-COMMON-VARS (ARGS COV) "
  " (IF (NULL COV)"
  "  NIL "
  "  (CONS "
  "   (LIST 'CALL 'II2V "
  "    (LIST 'GET-LOCAL 0) "
  "    (LIST 'CALL 'II2I "
  "     (LIST 'CALL 'II2I (LIST 'CONST (CAR COV)) "
  "      (C::COMPILE-ARG (POSITION (CAR COV) ARGS)) 6) "  ;; 6: cons
  "     (LIST 'CALL 'I2I (LIST 'GET-LOCAL 0) 10) "  ;; 10: getAArgFInSubr
  "     6) "  ;; 6: cons
  "    30) "  ;; 30: setAArgFInSubr
  "   (C::INIT-COMMON-VARS ARGS (CDR COV))))) "
  "(DE C::INIT-SPECIAL-VARS (ARGS SV) "
  " (IF (NULL SV)"
  "  NIL "
  "  (CONS "
  "   (LIST 'PROGN "
  "    (LIST 'CALL 'I2V (C::COMPILE-SPECIAL-VAR (PROP (CAR SV) 'SPECIAL)) 1) "
  "    (LIST 'CALL 'I2V (C::COMPILE-ARG (POSITION (CAR SV) ARGS)) 1) "
  "    (LIST 'STORE "
  "     (LIST 'CALL 'I2I (LIST 'CONST (PROP (CAR SV) 'SPECIAL)) 4) "  ;; 4: car
  "     (LIST 'CALL 'V2I 2)) "  ;; 2: pop (args)
       ;; TODO: make a utility function for set argument
  "    (LIST 'CALL 'III2V "
  "     (LIST 'GET-LOCAL 0) (POSITION (CAR SV) ARGS) "
  "     (LIST 'CALL 'V2I 2) "  ;; 2: pop (special)
  "     35)) "  ;; 35: setArgFN
  "   (C::INIT-SPECIAL-VARS ARGS (CDR SV))))) "
  "(DE C::CLEANUP-SPECIAL-VARS (ARGS SV) "
  " (IF (NULL SV)"
  "  NIL "
  "  (CONS "
  "   (LIST 'PROGN "
  "    (LIST 'CALL 'I2V (C::COMPILE-ARG (POSITION (CAR SV) ARGS)) 1) "
  "    (LIST 'STORE "
  "     (LIST 'CALL 'I2I (LIST 'CONST (PROP (CAR SV) 'SPECIAL)) 4) "  ;; 4: car
  "     (LIST 'CALL 'V2I 2))) "  ;; 2: pop (args)
  "   (C::CLEANUP-SPECIAL-VARS ARGS (CDR SV))))) "
  "(DE C::INIT-FSUBR-STACK (FI) "
  " (IF (OR (ATOM FI) (NOT (EQ (CAR FI) 'FEXPR))) "
  "  NIL "
     ;; 29: createSubrStackFromFsubrStack
  "  (LIST (LIST 'CALL 'I2V (LIST 'GET-LOCAL 0) 29) "
  "   (LIST 'SET-LOCAL 0 (LIST 'CALL 'V2I 0))))) "  ;; 0: getSp
  "(DE C::CLEANUP-FSUBR-STACK (FI) "
  " (IF (OR (ATOM FI) (NOT (EQ (CAR FI) 'FEXPR))) "
  "  NIL "
     ;; 40: cleanupSubrStackFromFsubrStack
  "  (LIST (LIST 'CALL 'I2V (LIST 'GET-LOCAL 0) 40) "
      ;; Don't need to eval return value
  "   (LIST 'CALL 'I2V 0 1)))) "
  "(DE C::COMPILE-FUNC (SYM ARGS EXP) (PROG (CV COV SV) "
  " (SETQ CV (C::CAPTURED-VARS ARGS EXP)) "
  " (SETQ COV (REMOVE-IF-NOT (FUNCTION (LAMBDA (X) (GET X 'COMMON))) ARGS)) "
  " (SETQ SV (REMOVE-IF-NOT (FUNCTION (LAMBDA (X) (GET X 'SPECIAL))) ARGS)) "
  " (RETURN "
  "  (LIST 'PROGN "
  "   (CONC (LIST 'BLOCK) "
       ;; Initialization
  "    (C::INIT-FSUBR-STACK SYM)"
  "    (C::INIT-CV-STACK ARGS CV) "
  "    (C::INIT-COMMON-VARS ARGS COV) "
  "    (C::INIT-SPECIAL-VARS ARGS SV) "
       ;; Body
  "    (LIST (C::COMPILE-CODE SYM ARGS (C::REPLACE-CV-REF ARGS EXP CV)))) "
      ;; Cleanup
  "   (CONC (LIST 'PROGN) "
  "    (C::CLEANUP-SPECIAL-VARS ARGS SV) "
  "    (C::CLEANUP-FSUBR-STACK SYM)))))) "
  "(DE C::COMPILE-PROG-CODE (FI ARGS EXP) (PROG (ASM) "
  " (IF (ATOM EXP) (RETURN (LIST 'PROG))) "  ;; Return nop for a label
  " (SETQ ASM (C::COMPILE-CODE FI ARGS EXP)) "
  " (IF (AND (CONSP EXP) (MEMBER (CAR EXP) '(RETURN GO))) "
  "  (RETURN ASM) "
     ;; TODO: error check
  "  (RETURN (LIST 'CALL 'I2V ASM 3))))) "  ;; 3: drop
  "(DE C::COMPILE-PROG-FRAGMENT (FI ARGS FRGM N) "
  " (LIST 'WHEN (LIST '< (LIST 'GET-LOCAL 1) N) "
  "  (CONS 'PROGN (MAPLIST FRGM (FUNCTION (LAMBDA (E) "
  "   (C::COMPILE-PROG-CODE FI ARGS (CAR E)))))))) "
  "(DE C::GET-PROG-FRAGMENT-AFTER (LBL BODY) "
  " (IF (NULL LBL) "
  "  (IF (OR (NULL BODY) (ATOM (CAR BODY)))"
  "   NIL"
  "   (CONS (CAR BODY) (C::GET-PROG-FRAGMENT-AFTER LBL (CDR BODY)))) "
  "  (COND "
  "   ((NULL BODY) (ERROR (SYMCAT '$$|Label not found: | LBL))) "
  "   ((EQ (CAR BODY) LBL) (C::GET-PROG-FRAGMENT-AFTER NIL (CDR BODY))) "
  "   (T (C::GET-PROG-FRAGMENT-AFTER LBL (CDR BODY)))))) "
  "(DE C::COMPILE-PROG-BODY (FI ARGS BODY) (PROG (N CV COV SV FRAGMENTS) "
    ;; Replace captured variables
  " (SETQ CV (C::CAPTURED-VARS ARGS BODY)) "
  " (SETQ COV (REMOVE-IF-NOT (FUNCTION (LAMBDA (X) (GET X 'COMMON))) ARGS)) "
  " (SETQ SV (REMOVE-IF-NOT (FUNCTION (LAMBDA (X) (GET X 'SPECIAL))) ARGS)) "
  " (SETQ BODY (C::REPLACE-CV-REF ARGS BODY CV)) "
    ;; Create fragments
  " (SETQ FRAGMENTS (MAPLIST (CONS NIL (CADR FI)) (FUNCTION (LAMBDA (X) "
  "  (C::GET-PROG-FRAGMENT-AFTER (CAR X) BODY))))) "
  " (SETQ N 0) "
  " (RETURN (LIST 'PROGN "
  "  (LIST 'BLOCK "
  "   (CONC (LIST 'PROGN) "
  "    (C::INIT-CV-STACK ARGS CV)"
  "    (C::INIT-COMMON-VARS ARGS COV) "
  "    (C::INIT-SPECIAL-VARS ARGS SV)) "
  "   (LIST 'SET-LOCAL 1 0) "  ;; $idx = 0
  "   (LIST 'LOOP (CONS 'PROGN (MAPLIST FRAGMENTS (FUNCTION (LAMBDA (FR) "
  "    (C::COMPILE-PROG-FRAGMENT FI ARGS (CAR FR) (SETQ N (+ N 1)))))))) "
  "   (LIST 'CONST NIL)) "
  "  (CONC (LIST 'PROGN) (C::CLEANUP-SPECIAL-VARS ARGS SV)))))) "
  "(DE C::TRANSFORM-COND (X) "  ;; X of (COND . X)
  " (IF (NULL X) "
  "  NIL"
  "  (LIST 'IF (C::TRANSFORM (SCAR (CAR X))) "
  "   (C::TRANSFORM (SCAR (SCDR (CAR X)))) "
  "   (C::TRANSFORM-COND (CDR X))))) "
  "(DE C::TRANSFORM-AND (X) "  ;; X of (AND . X)
  " (COND ((NULL X) T)"
  "  ((NULL (CDR X)) (C::TRANSFORM (CAR X))) "
  "  (T (LIST 'IF (LIST 'NOT (C::TRANSFORM (CAR X))) "
  "   NIL "
  "   (C::TRANSFORM-AND (CDR X)))))) "
  "(DE C::TRANSFORM-OR (X) "  ;; X of (OR . X)
  " (COND ((NULL X) NIL) "
  "  ((NULL (CDR X)) (C::TRANSFORM (CAR X))) "
  "  (T (LIST 'IF "
  "   (LIST 'CAR (LIST 'CSETQ '*OR-RESULT* (C::TRANSFORM (CAR X)))) "
  "   '*OR-RESULT* "
  "   (C::TRANSFORM-OR (CDR X)))))) "
  "(DE C::TRANSFORM-LIST (X) "  ;; X of (LIST . X)
  " (COND ((NULL X) NIL) "
  "  (T (LIST 'CONS (C::TRANSFORM (CAR X)) (C::TRANSFORM-LIST (CDR X)))))) "
  "(DE C::TRANSFORM-LSUBR (FN X D) "
  " (COND ((NULL X) D) "
  "  ((NULL (CDR X)) (C::TRANSFORM (CAR X))) "
  "  (T (LIST FN (C::TRANSFORM (CAR X)) (C::TRANSFORM-LSUBR FN (CDR X) D))))) "
  "(DE C::TRANSFORM (EXP) "
  " (COND "
  "  ((ATOM EXP) EXP) "
  "  ((EQ (CAR EXP) 'QUOTE) EXP) "
  "  ((EQ (CAR EXP) 'LAMBDA) EXP) "
  "  ((EQ (CAR EXP) 'COND) (C::TRANSFORM-COND (CDR EXP))) "
  "  ((EQ (CAR EXP) 'AND) (C::TRANSFORM-AND (CDR EXP))) "
  "  ((EQ (CAR EXP) 'OR) (C::TRANSFORM-OR (CDR EXP))) "
  "  ((EQ (CAR EXP) 'LIST) (C::TRANSFORM-LIST (CDR EXP))) "
  "  ((EQ (CAR EXP) 'LOGAND) (C::TRANSFORM-LSUBR 'LOGAND2 (CDR EXP) -1)) "
  "  ((EQ (CAR EXP) 'LOGOR) (C::TRANSFORM-LSUBR 'LOGOR2 (CDR EXP) 0)) "
  "  ((EQ (CAR EXP) 'LOGXOR) (C::TRANSFORM-LSUBR 'LOGXOR2 (CDR EXP) 0)) "
  "  ((EQ (CAR EXP) 'MAX) (C::TRANSFORM-LSUBR 'MAX2 (CDR EXP) 0)) "
  "  ((EQ (CAR EXP) 'MIN) (C::TRANSFORM-LSUBR 'MIN2 (CDR EXP) 0)) "
  "  ((EQ (CAR EXP) 'PLUS) (C::TRANSFORM-LSUBR 'PLUS2 (CDR EXP) 0)) "
  "  ((EQ (CAR EXP) '+) (C::TRANSFORM-LSUBR 'PLUS2 (CDR EXP) 0)) "
  "  ((EQ (CAR EXP) 'TIMES) (C::TRANSFORM-LSUBR 'TIMES2 (CDR EXP) 1)) "
  "  ((EQ (CAR EXP) '*) (C::TRANSFORM-LSUBR 'TIMES2 (CDR EXP) 1)) "
  "  ((EQ (CAR EXP) 'CONC) (C::TRANSFORM-LSUBR 'NCONC (CDR EXP) NIL)) "
  "  ((EQ (CAR EXP) 'SETQ) "
  "   (LIST 'SETQ (CADR EXP) (C::TRANSFORM (CAR (CDDR EXP))))) "
  "  ((OR (GET (CAR EXP) 'FSUBR) (GET (CAR EXP) 'FEXPR)) EXP) "
  "  (T (MAPLIST EXP (FUNCTION (LAMBDA (Y) (C::TRANSFORM (CAR Y)))))))) "
  "(DE C::CAPTURED-VARS (ARGS EXP) "
  " (REMOVE-DUPLICATES ((LABEL REC (LAMBDA (ARGS E INL) "
  "  (COND"
  "   ((ATOM E) (IF (AND INL (MEMBER E ARGS) (NOT (GET E 'COMMON)) "
  "     (NOT (GET E 'SPECIAL))) (LIST E) NIL)) "
  "   ((EQ (CAR E) 'QUOTE) NIL) "
  "   ((EQ (CAR E) 'LAMBDA) "
  "    (REC "
  "     (SET-DIFFERENCE ARGS (CADR E)) (CAR (CDDR E)) T)) "
  "   ((EQ (CAR E) 'PROG) "
  "    (REC "
  "     (SET-DIFFERENCE ARGS (CADR E)) (CDDR E) T)) "
  "   (T (MAPCON E (FUNCTION (LAMBDA (Y) "
  "    (REC ARGS (CAR Y) INL)))))))) ARGS EXP NIL))) "
  "(DE C::VERIFY0 (SYM FN) (PROG () "
  " (IF (ATOM FN) (ERROR (SYMCAT SYM '$$| is not a function|))) "
  " (IF (NOT (EQ (CAR FN) 'LAMBDA)) "
  "  (ERROR (SYMCAT SYM '$$| is not a lambda|))) "
  " )) "
  "(CSETQ *COMPILED-EXPRS* NIL) "
  "(CSETQ *COMPILED-FEXPRS* NIL) "
  "(DE EVAL-ENTER-HOOK () (PROG ()"
  " (MAP *COMPILED-EXPRS* (FUNCTION (LAMBDA (X) (REMPROP (CAR X) 'EXPR)))) "
  " (MAP *COMPILED-FEXPRS* (FUNCTION (LAMBDA (X) (REMPROP (CAR X) 'FEXPR)))) "
  " (CSETQ *COMPILED-EXPRS* NIL) "
  " (CSETQ *COMPILED-FEXPRS* NIL) "
  "))"
  "(DE C::GET-LABELS (BODY) "
  " (MAPCON BODY (FUNCTION (LAMBDA (X) "
  "  (IF (ATOM (CAR X)) (LIST (CAR X)) NIL))))) "
  ;;; Returns (SUBR-index . OBJ-list).
  "(DE C::COMPILE-PROG (EXP) (PROG (BODY LS OBJS ASM) "  ;; EXP = (PROG ...)
  " (SETQ BODY (C::TRANSFORM (CDDR EXP))) "
  " (SETQ LS (C::GET-LABELS BODY)) "
  " (SETQ ASM (C::COMPILE-PROG-BODY (LIST 'PROG LS) (CADR EXP) BODY)) "
  " (BSTART)"
  " (C::ASSEMBLE ASM) "
  " (SETQ OBJS (C::GET-CONSTS ASM)) "
  " (RETURN (CONS (LOAD-WASM) OBJS)))) "
  ;;; Returns (SUBR-index . OBJ-list).
  "(DE C::COMPILE-LAMBDA (SYM FN) (PROG (OBJS ASM) "
  " (C::VERIFY0 SYM FN) "
  " (SETQ FN (LIST (CAR FN) (CADR FN) (C::TRANSFORM (CAR (CDDR FN))))) "
  " (SETQ ASM (C::COMPILE-FUNC SYM (CADR FN) (CAR (CDDR FN)))) "
  " (BSTART)"
  " (C::ASSEMBLE ASM) "
  " (SETQ OBJS (C::GET-CONSTS ASM)) "
  " (RETURN (CONS (LOAD-WASM) OBJS)))) "
  "(DE C::COMPILE1 (SYM) (PROG (FE FN IDX-OBJ) "
  " (SETQ FE (GET SYM 'FEXPR)) "
  " (IF FE "
  "  (SETQ FN FE) "
  "  (SETQ FN (GET SYM 'EXPR))) "
  " (IF (NULL FN) (ERROR (SYMCAT SYM '$$| does not have EXPR or FEXPR|))) "
  " (SETQ IDX-OBJ (C::COMPILE-LAMBDA (IF FE (LIST 'FEXPR SYM) SYM) FN)) "
  " (IF FE"
  "  (PUTPROP SYM (CAR IDX-OBJ) 'FSUBR) "  ;; TODO: Keep OBJ
  "  (PUTPROP SYM (LIST (CAR IDX-OBJ) (LENGTH (CADR FN)) (CDR IDX-OBJ)) 'SUBR)) "
  "  (IF FE (PUTPROP SYM (CDR IDX-OBJ) 'OBJ)) "
    ;; Remove EXPR later because WebAssembly modules are actually loaded
    ;; after all functions returned.
  " (IF FE"
  "  (CSETQ *COMPILED-FEXPRS* (CONS SYM *COMPILED-FEXPRS*)) "
  "  (CSETQ *COMPILED-EXPRS* (CONS SYM *COMPILED-EXPRS*))) "
  " )) "
  "(DE COMPILE (LST) "
  " (MAP LST (FUNCTION (LAMBDA (X) (C::COMPILE1 (CAR X))))))"
  "(CSETQ *OR-RESULT* NIL) "
  "(MAP '( "
  " PLUS2 TIMES2 MAX2 MIN2 LOGAND2 LOGOR2 LOGXOR2 "
  " C::VCTAG "
  " ) (FUNCTION (LAMBDA (X) (REMOB (CAR X))))) "
  " (COMPILE '(NOT CAAR CADR CDAR CDDR SCAR SCDR CONSP SYMBOLP)) "
  " (COMPILE '(COMMON UNCOMMON)) "
  " (COMPILE '(SPECIAL UNSPECIAL)) "
  ;; Greeting
  "(PRINT '$$|\F0\9F\8D\93 Ichigo Lisp version 0.0.1 powered by WebAssembly|) "
  "(PRINT '$$|\F0\9F\8D\93 Enjoy LISP 1.5(-ish) programming|) "
  "(RECLAIM)"
  "STOP "  ;; END OF EXPR/FEXPR/APVAL
  "\00")

 (func $initexpr
       (local $rd i32)
       (local $ret i32)
       (call $rdset (global.get $str_expr_defs))
       (loop $loop
          (global.set $printp (i32.const 40960))
          (local.set $rd (call $read))
          (if (i32.eq (local.get $rd) (global.get $sym_stop))
              (return))
          (local.set $ret (call $eval (local.get $rd) (i32.const 0)))
          (call $printObj (local.get $ret))
          (call $ilogstr (i32.const 40960))
          (if (call $errorp (local.get $ret))
              (call $logstr (i32.const 40960)))
          (br_if $loop (i32.eqz (call $errorp (local.get $ret))))))
 ;;; END EXPR/FEXPR

 (func $fflush
       (call $outputString (i32.const 40960))
       (global.set $printp (i32.const 40960)))

 (func (export "init")
       (global.set $suppress_gc_msg (i32.const 1))
       (call $init)
       (call $initexpr)
       (global.set $suppress_gc_msg (i32.const 0)))

 (func (export "setDebugLevel") (param $level i32)
       (global.set $debug_level (local.get $level)))

 (func (export "readAndEval")
       (local $alist i32)
       (local.set $alist (i32.const 0))
       (global.set $printp (i32.const 40960))
       (call $drop (call $apply (global.get $sym_eval_enter_hook)
                         (i32.const 0) (i32.const 0)))

       (global.set $st_level (i32.const 0))
       (call $rdset (i32.const 51200))
       (call $printObj
             (call $eval (call $read) (local.get $alist)))
       (if (i32.ne (global.get $sp) (global.get $stack_bottom))
           (then
            (call $log (i32.const 999001))
            (call $log (global.get $sp))
            (unreachable)))  ;; TODO: Show better error messages
       (call $outputString (i32.const 40960)))

 (func (export "readAndEvalquote")
       (local $fn i32)
       (local $args i32)
       (local $alist i32)
       (local.set $alist (i32.const 0))
       (global.set $printp (i32.const 40960))
       (call $drop (call $apply (global.get $sym_eval_enter_hook)
                         (i32.const 0) (i32.const 0)))

       (global.set $st_level (i32.const 0))
       (call $rdset (i32.const 51200))
       (local.set $fn (call $read))
       (call $push (local.get $fn))  ;; For GC (fn)
       (local.set $args (call $read))
       (call $push (local.get $args))  ;; For GC (fn args)
       (call
        $printObj
        (call $apply (local.get $fn) (local.get $args) (local.get $alist)))
       (call $drop (call $pop))  ;; For GC (fn)
       (call $drop (call $pop))  ;; For GC ()
       (if (i32.ne (global.get $sp) (global.get $stack_bottom))
           (then
            (call $log (i32.const 999001))
            (call $log (global.get $sp))
            (unreachable)))  ;; TODO: Show better error messages
       (call $outputString (i32.const 40960)))
 )
