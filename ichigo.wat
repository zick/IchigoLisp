;;; $ wat2wasm ichigo.wat -o ichigo.wasm
;;; ...XX1: fixnum
;;; ...G00: cons (G: gc mark)
;;; ...G10: other pointer (G: gc mark)
;;; 0: NIL
;;; -2: mark for symbol (same format as "other pointer")
;;; name: list of packed characters like ("abc" "def" "gh\00")
;;; name1: a packed characters like "abc"

(module
 (func $log (import "console" "log") (param i32))
 (func $logstr (import "console" "logstr") (param i32))
 (func $printlnString (import "io" "printlnString") (param i32))
 (func $output (import "io" "output") (param i32))
 ;; page 0: any
 ;; page 1: free list
 ;; page 2: stack
 (import "js" "memory" (memory 3))
 (import "js" "table" (table 256 funcref))

 (type $subr_type (func (result i32)))
 (type $fsubr_type (func (result i32)))

 ;; points to the head of free list
 (global $fp (mut i32) (i32.const 65536))
 ;; maximum used cell address
 (global $used (mut i32) (i32.const 0))
 ;; stack pointer
 (global $sp (mut i32) (i32.const 131072))

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
 (global $str_plus i32 (i32.const 2080))
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

 (global $boffo i32 (i32.const 10240))
 (global $boffop (mut i32) (i32.const 10240))
 (global $readp (mut i32) (i32.const 0))
 (global $printp (mut i32) (i32.const 0))

 (global $oblist (mut i32) (i32.const 0))

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

 (func $push (param $val i32)
       (i32.store (global.get $sp) (local.get $val))
       (global.set $sp (i32.add (global.get $sp) (i32.const 4))))
 (func $pop (result i32)
      (global.set $sp (i32.sub (global.get $sp) (i32.const 4)))
      (i32.load (global.get $sp)))
 (func $drop (param i32))

 (func $car (param i32) (result i32)
       (i32.load (local.get 0)))
 (func $cdr (param i32) (result i32)
       (i32.load (i32.add (local.get 0) (i32.const 4))))

 (func $rawcons (result i32)
       (local $prev i32)
       (local.set $prev (global.get $fp))
       (if (i32.lt_u (global.get $used) (global.get $fp))  ;; used < fp
           (then
            (global.set $used (local.get $prev))
            (global.set $fp (i32.add (local.get $prev) (i32.const 8))))
           (else
            (global.set $fp (call $cdr (local.get $prev)))))
       (local.get $prev))  ;; return prev

 (func $cons (param $a i32) (param $d i32) (result i32)
      (local $cell i32)
      (local.set $cell (call $rawcons))
      (call $setcar (local.get $cell) (local.get $a))
      (call $setcdr (local.get $cell) (local.get $d))
      (local.get $cell))

 (func $setcar (param i32) (param i32)
       (i32.store (local.get 0) (local.get 1)))
 (func $setcdr (param i32) (param i32)
       (i32.store (i32.add (local.get 0) (i32.const 4))
                  (local.get 1)))

 ;;; Returns a fixnum representing a packed characters from a string.
 (func $makename1 (param $str i32) (result i32)
       (local $ret i32)
       ;; xxcccccc => cccccc01
       (local.set
        $ret
        (i32.add
         (i32.shl
          (i32.and (i32.load (local.get $str)) (i32.const 0x00ffffff))
          (i32.const 8))
         (i32.const 1)))
       ;; xxxx0001 => 00000001
       (if (i32.eqz (i32.and (local.get $ret) (i32.const 0x0000ff00)))
           (local.set $ret (i32.const 1)))
       ;; xx00cc01 => 0000cc01
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

 ;;; Returns a list of packed characters.
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

 (func $int2fixnum (param $n i32) (result i32)
       (i32.add (i32.shl (local.get $n) (i32.const 1)) (i32.const 1)))
 (func $fixnum2int (param $n i32) (result i32)
       (i32.shr_s (local.get $n) (i32.const 1)))

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

 (func $tag0p (param $obj i32) (result i32)
       (i32.eqz (i32.and (local.get $obj) (i32.const 1))))

 (func $specialTagp (param $obj i32) (result i32)
       (i32.eq (local.get $obj) (i32.const -2)))

 (func $symbolp (param $obj i32) (result i32)
       (local $ret i32)
       (local.set $ret (i32.const 0))
       (if (call $tag0p (local.get $obj))
           (if (i32.eq (call $car (local.get $obj)) (i32.const -2))
               (local.set $ret (i32.const 1))))
       (local.get $ret))

 (func $consp (param $obj i32) (result i32)
       (local $ret i32)
       (local.set $ret (i32.const 0))
       (if (call $tag0p (local.get $obj))
           (if (i32.eqz (call $specialTagp (call $car (local.get $obj))))
               (local.set $ret (i32.const 1))))
       (local.get $ret))

 (func $fixnump (param $obj i32) (result i32)
       (i32.and (local.get $obj) (i32.const 1)))

 (func $numberp (param $obj i32) (result i32)
       (call $fixnump (local.get $obj)))

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
       (local.set $p (call $prop (local.get $obj) (local.get $key)))
       (if (i32.eqz (local.get $p))
           (return (i32.const 0)))
       (call $car (local.get $p)))

 (func $putprop (param $obj i32) (param $key i32) (param $val i32)
       (local $p i32)
       (local.set $p (call $prop (local.get $obj) (local.get $key)))
       (if (i32.eqz (local.get $p))
           (then
            (local.set $p (call $cons (i32.const 0) (i32.const 0)))
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

 (func $printChar (param $c i32)
       (i32.store8 (global.get $printp) (local.get $c))
       (global.set $printp (i32.add (global.get $printp) (i32.const 1))))

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
       (local.set $sym (call $cons (i32.const -2) (i32.const 0)))
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
                 (local.set $ret (i32.const 0))  ;; TODO: Return an error
                 (br $block)))
            (if (i32.eq (local.get $c) (i32.const 41))  ;; RPar
                (br $block))
            (call $push (local.get $ret))  ;; For GC (ret)
            (local.set $elm (call $read))
            ;; Special read for dotted list
            (if (i32.eq (local.get $elm) (global.get $sym_dot))
                (then
                 (call $skipSpaces)
                 (local.set $c (i32.load8_u (global.get $readp)))
                 (if (i32.eq (local.get $c) (i32.const 41))  ;; RPar after dot
                     (then
                      (call $drop (call $pop))  ;; For GC ()
                      (local.set $ret (i32.const 0))  ;; TODO: Return an error
                      (br $block)))
                 (local.set $elm (call $read))
                 (call $drop (call $pop))  ;; For GC ()
                 (call $skipSpaces)
                 (local.set $c (i32.load8_u (global.get $readp)))
                 (if (i32.ne (local.get $c) (i32.const 41))  ;; Not RPar
                     (then
                      (local.set $ret (i32.const 0))  ;; TODO: Return an error
                      (br $block)))
                 (br $block)))  ;; valid dotted list
            ;; Proper list
            (call $push (local.get $elm))  ;; For GC (ret elm)
            (local.set $ret (call $cons (local.get $elm) (local.get $ret)))
            (local.set $elm (i32.const 0))
            (call $drop (call $pop))  ;; For GC (ret)
            (call $drop (call $pop))  ;; For GC ()
            (br $loop)))
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
             (then (local.set $ret (i32.const 0))  ;; TODO: Return an error
                   (br $block)))
         (if (i32.eq (local.get $c) (i32.const 41))  ;; RPar
             (then (local.set $ret (i32.const 0))  ;; TODO: Return an error
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
            (call $push (local.get $elm))  ;; For GC (ret elm)
            (local.set $ret (call $cons (local.get $elm) (local.get $ret)))
            (call $drop (call $pop))  ;; For GC (ret)
            (call $drop (call $pop))  ;; For GC (a)
            (local.set $lst (call $cdr (local.get $lst)))
            (br $loop)))
       (call $nreverse (local.get $ret)))

 ;;; Pushes 4 elements
 ;;; `lst` and `a` must be protected from GC
 (func $evpush (param $lst i32) (param $a i32)
       ;; Push the first argument
       (if (i32.eqz (local.get $lst))
           (then (call $push (i32.const 0)))
           (else
            (call $push
                  (call $eval (call $car (local.get $lst)) (local.get $a)))
            (local.set $lst (call $cdr (local.get $lst)))))
       ;; Push the second argument
       (if (i32.eqz (local.get $lst))
           (then (call $push (i32.const 0)))
           (else
            (call $push
                  (call $eval (call $car (local.get $lst)) (local.get $a)))
            (local.set $lst (call $cdr (local.get $lst)))))
       ;; Push the third argument
       (if (i32.eqz (local.get $lst))
           (then (call $push (i32.const 0)))
           (else
            (call $push
                  (call $eval (call $car (local.get $lst)) (local.get $a)))
            (local.set $lst (call $cdr (local.get $lst)))))
       ;; Push the rest of arguments
       (if (i32.eqz (local.get $lst))
           (call $push (i32.const 0))
           (call $push (call $evlis (local.get $lst) (local.get $a)))))

 (func $evpop
       (global.set $sp (i32.sub (global.get $sp) (i32.const 16))))

 (func
  $eval (param $e i32) (param $a i32) (result i32)
  (local $ret i32)
  (local $tmp i32)
  (local $fn i32)
  (local $args i32)
  (local.set $ret (i32.const 0))
  (call $log (i32.const 11111));;;;;
  (call $log (global.get $sp));;;;;
  (call $push (local.get $e))  ;; For GC (e)
  (call $push (local.get $a))  ;; For GC (e, a)
  (block $evalbk
    (loop $evallp
       ;; Evaluate an atom
       (call $log (i32.const 10000001));;;;;
       (if (i32.eqz (local.get $e))
           (then (local.set $ret (i32.const 0))
                 (br $evalbk)))
       (call $log (i32.const 10000002));;;;;
       (if (call $symbolp (local.get $e))
           (then
            (local.set $tmp
                       (call $get (local.get $e) (global.get $sym_apval)))
            (if (i32.ne (local.get $tmp) (i32.const 0))
                (then
                 (local.set $ret (call $car (local.get $tmp)))
                 (br $evalbk)))))
       (call $log (i32.const 10000003));;;;;
       (if (call $numberp (local.get $e))
           (then (local.set $ret (local.get $e))
                 (br $evalbk)))
       (if (i32.eqz (call $consp (local.get $e)))  ;; Unknown object
           (then (local.set $ret (i32.const 0))  ;; TODO: Return an error
                 (br $evalbk)))
       (call $log (i32.const 10000004));;;;;
       ;; Evaluate a compound expression
       (local.set $fn (call $car (local.get $e)))
       (local.set $args (call $cdr (local.get $e)))
       (if (i32.eq (local.get $fn) (global.get $sym_quote))
           (then (local.set $ret (call $car (local.get $args)))
                 (br $evalbk)))
       ;; TODO: Other special forms
       (call $log (i32.const 10000004));;;;;
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
            (call $evpush (local.get $args) (local.get $a))
            (local.set
             $ret
             (call_indirect
              (type $subr_type)
              (call $fixnum2int (local.get $tmp))))
            (call $evpop)
            (br $evalbk)))
       ))
  (call $drop (call $pop))  ;; For GC (e)
  (call $drop (call $pop))  ;; For GC ()
  (call $log (global.get $sp));;;;;
  (call $log (i32.const 22222));;;;;
  (local.get $ret))

 ;; Creates a minimum symbol.
 ;; This function doesn't care GC
 (func $initsym0 (param $sym i32) (param $str i32)
       (local $cell i32)
       (local.set $cell (call $makename (local.get $str)))
       (local.set $cell (call $cons (local.get $cell) (i32.const 0)))
       (local.set $cell (call $cons (global.get $sym_pname) (local.get $cell)))
       (call $setcdr (local.get $sym) (local.get $cell))
       (call $setcar (local.get $sym) (i32.const -2))
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
       (call $setcar (local.get $sym) (i32.const -2))
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
       (call $setcar (local.get $sym) (i32.const -2))
       (call $pushToOblist (local.get $sym)))

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
       (call $initsym1
             (global.get $sym_nil) (global.get $str_nil) (i32.const 0))
       (call $initsym1
             (global.get $sym_f) (global.get $str_f) (i32.const 0))
       (call $initsym1
             (global.get $sym_t) (global.get $str_t) (global.get $sym_tstar))
       (call $initsym1
             (global.get $sym_tstar) (global.get $str_tstar)
             (global.get $sym_tstar))

       (call $initsymKv
             (global.get $sym_car) (global.get $str_car)
             (global.get $sym_subr) (call $int2fixnum (global.get $idx_car)))
       (call $initsymKv
             (global.get $sym_cdr) (global.get $str_cdr)
             (global.get $sym_subr) (call $int2fixnum (global.get $idx_cdr)))
       (call $initsymKv
             (global.get $sym_cons) (global.get $str_cons)
             (global.get $sym_subr) (call $int2fixnum (global.get $idx_cons)))
       (call $initsymKv
             (global.get $sym_atom) (global.get $str_atom)
             (global.get $sym_subr) (call $int2fixnum (global.get $idx_atom)))
       (call $initsymKv
             (global.get $sym_eq) (global.get $str_eq)
             (global.get $sym_subr) (call $int2fixnum (global.get $idx_eq)))
       (call $initsymKv
             (global.get $sym_equal) (global.get $str_equal)
             (global.get $sym_subr) (call $int2fixnum (global.get $idx_equal)))
       (call $initsymKv
             (global.get $sym_list) (global.get $str_list)
             (global.get $sym_fsubr) (call $int2fixnum (global.get $idx_list)))
       (call $initsymKv
             (global.get $sym_if) (global.get $str_if)
             (global.get $sym_fsubr) (call $int2fixnum (global.get $idx_if)))
       )

 ;;; SUBR/FSUBR
 ;;; SUBR stack: (..., arg1, arg2, arg3, restArgs)
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
       (local.set $a (call $getAArg))
       (local.set $args (call $cdr (call $getEArg)))
       (if (i32.eqz (call $eval (call $car (local.get $args)) (local.get $a)))
           (local.set $ret
                      (call $car (call $cdr (call $cdr (local.get $args)))))
           (local.set $ret
                      (call $car (call $cdr (local.get $args)))))
       (call $push (i32.const 1))  ;; *Need* to eval return value
       (local.get $ret))
 ;;; END SUBR/FSUBR

 (func (export "init")
       (call $init))

 (func (export "readAndEval")
       (global.set $printp (i32.const 1024))
       (global.set $readp (i32.const 51200))
       (call $printObj
             (call $eval (call $read) (i32.const 0)))
       (call $output (i32.const 1024)))

 (func (export "read")
       (global.set $printp (i32.const 1024))
       (global.set $readp (i32.const 51200))
       (call $printObj (call $read))
       (call $output (i32.const 1024)))

 )
