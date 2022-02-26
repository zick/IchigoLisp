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
```

For running locally:
```
% wat2wasm ichigo.wat -o ichigo.wasm  # Convert WASM text format to binary
% http-server  # Run HTTP server locally because file:// isn't supported
```

## Supported Features
Ichigo Lisp supports most of features written in
[LISP 1.5 Programmer's Manual](http://www.softwarepreservation.org/projects/LISP/book/LISP%201.5%20Programmers%20Manual.pdf/view)
except compiler, array, and floating point number.
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
- STARTREAD
- SUB1
- SUBLIS
- SUBST
- TERPRI
- UNCOUNT
- UNPACK
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
- COMMON
- COMPILE
- CP1
- ERROR1
- EXCISE
- LAP
- LOAD
- PAUSE
- PLB
- READLAP
- SPECIAL
- TEMPUS-FUGIT
- UNCOMMON
- UNSPECIAL

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

## Known Issues
### `READ` cannot read expressions interactively
`READ` (and `ADVANCE` and `STARTREAD`) reads characters only from the program
text. For example `(READ)non-program-word`'s value is `non-program-word`.
Just evaluating `(READ)` throws an error (`<R4: EOF ON READ-IN>`).
