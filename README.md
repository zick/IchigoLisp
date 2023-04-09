# Ichigo Lisp
LISP 1.5(-ish) implementation in WebAssembly

## How to use
Try [demo page](http://pages.zick.run/ichigo/).

```
> (car '(a b c))
A
> (cdr '(a b c))
(B C)
> (cons 1 (cons 2 (cons 3 ())))
(1 2 3)
> (define '((fact (lambda (n) (cond ((zerop n) 1) (t (times n (fact (sub1 n)))))))))
(FACT)
> (fact 10)
3628800
> (define '((gen (lambda (n) (function (lambda (m) (setq n (plus n m))))))))
(GEN)
> (prog (x) (setq x (gen 100)) (print (x 10)) (print (x 90)) (print (x 300)))
110
200
500
NIL
> (compile '(fact))
NIL
> (fact 10)
3628800
```

For running locally:
```
% wat2wasm ichigo.wat -o ichigo.wasm  # Convert WASM text format to binary
% http-server  # Run HTTP server locally because file:// isn't supported
```

Alternatively, using the [Binaryen](https://github.com/WebAssembly/binaryen)
toolchain to assemble the binary:

```
# Assemble
wasm-as -o ichigo.wasm ichigo.wat

# Optimize (optional)
wasm-opt -O3 -o ichigo.wasm ichigo.wasm
```

## Supported Features
Ichigo Lisp supports most of features written in
[LISP 1.5 Programmer's Manual](http://www.softwarepreservation.org/projects/LISP/book/LISP%201.5%20Programmers%20Manual.pdf/view)
except array and floating point number.
COMPILE generates WebAssembly binaries.
Some functions behave differently from LISP 1.5.
For example `COND` returns NIL when no conditions are satisfied while LISP 1.5
returns an error in that case.

### SUBR
SUBRs are functions written in WebAssembly.
You can check the latest status by evaluating `(symbols-with 'subr)`.

#### LISP 1.5 SUBRs
- ADD1
- ADVANCE
- APPEND
- APPLY
- ATOM
- ATTRIB
- CAR
- CDR
- CLEARBUFF
- COMMON
- COMPILE
- CONS
- COPY
- COUNT
- DASH
- DIFFERENCE
- DIGIT
- DIVIDE
- DUMP
- EFFACE
- ENDREAD
- EQ
- EQUAL
- ERROR
- ERRORSET
- EVAL
- EVLIS
- EXPT
- FIXP
- FLOATP
- GENSYM
- GET
- GREATERP
- INTERN
- LEFTSHIFT
- LENGTH
- LESSP
- LITER
- MAP
- MAPCON
- MAPLIST
- MEMBER
- MINUS
- MINUSP
- MKNAM
- NCONC
- NOT
- NULL
- NUMBERP
- NUMOB
- ONEP
- OPCHAR
- PACK
- PAIR
- PRIN1
- PRINT
- PROG2
- PROP
- PUNCH
- QUOTIENT
- READ
- RECIP
- RECLAIM
- REMAINDER
- REMOB
- REMPROP
- RETURN
- REVERSE
- RPLACA
- RPLACD
- SASSOC
- SEARCH
- SET
- SPEAK
- SPECIAL
- STARTREAD
- SUB1
- SUBLIS
- SUBST
- TERPRI
- UNCOMMON
- UNCOUNT
- UNPACK
- UNSPECIAL
- ZEROP

#### Non-LISP 1.5 SUBRs
- \- (same as `DIFFERENCE`)
- / (same as `QUOTIENT`)
- 1+ (same as `ADD1`)
- 1- (same as `SUB1`)
- < (same as `LESSP`)
- \> (same as `GREATERP`)
- PUTPROP

#### Unsupported SUBRs
- ARRAY
- CP1
- ERROR1
- EXCISE
- LAP
- LOAD
- PAUSE
- PLB
- READLAP
- TEMPUS-FUGIT

### FSUBR
FSUBRs are functions, that don't evaluate arguments,  written in WebAssembly.
You can check the latest status by evaluating `(symbols-with 'fsubr)`.

#### LISP 1.5 FSUBRs
- AND
- COND
- FUNCTION
- GO
- LABEL
- LIST
- LOGAND
- LOGOR
- LOGXOR
- MAX
- MIN
- OR
- PLUS
- PROG
- QUOTE
- SETQ
- TIMES

#### Non-LISP 1.5 FSUBRs
- \* (same as `TIMES`)
- \+ (same as `PLUS`)
- IF

### EXPR
EXPRs are functions written in Lisp.
You can check the latest status by evaluating `(symbols-with 'expr)`.

#### LISP 1.5 EXPRs
- CSET
- DEFINE
- DEFLIST
- FLAG
- PRINTPROP
- PUNCHDEF
- REMFLAG
- TRACE
- TRACESET
- UNTRACE
- UNTRACESET

#### Non-LISP 1.5 EXPRs
- REMOVE-IF-NOT
- SYMBOLS-WITHs

#### Unsupported EXPRs
- OPDEFINE
- PUNCHLAP

### FEXPR
FEXPRs are functions, that don't evaluate arguments, written in Lisp.
You can check the latest status by evaluating `(symbols-with 'fexpr)`.

#### LISP 1.5 FEXPRs
- CONC
- CSETQ
- SELECT

#### Non-LISP 1.5 FEXPRs
- DE
- DEFUN
- DF
