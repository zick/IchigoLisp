var test_data = [];
test_data.push([
    ["1", "1"],
    ["#x10", "16"],
    ["#x1f", "31"],
    ["0x20", "32"],
    ["0x2f", "47"],
    ["'a", "A"],
    ["'very-long-name", "VERY-LONG-NAME"],
    ["(car '(a b c))", "A"],
    ["(cdr '(a b c))", "(B C)"],
    ["(cons 'a 'b)", "(A . B)"],
    ["(cons (cdr '(a b c)) (car '(a b c)))", "((B C) . A)"],
    ["(atom (car '(a b c)))", "*T*"],
    ["(atom (cons 1 2))", "NIL"],
    ["(eq 'a 'a)", "*T*"],
    ["(eq 'a 'b)", "NIL"],
    ["(eq (cons 1 2) (cons 1 2))", "NIL"],
    ["(equal 1 1)", "*T*"],
    ["(equal 1 2)", "NIL"],
    ["(equal (cons 1 2) (cons 1 2))", "*T*"],
    ["(equal (cons 1 2) (cons 1 3))", "NIL"],
    ["(equal (cons 1 (cons 2 3)) (cons 1 (cons 2 3)))", "*T*"],
    ["(list)", "NIL"],
    ["(list (car '(a b c)))", "(A)"],
    ["(list 1 2 3 4 5)", "(1 2 3 4 5)"],
    ["(if nil 1 2)", "2"],
    ["(if t 1 2)", "1"],
    ["(if (atom (cons 1 2)) (car '(a b)) (cdr '(a b)))", "(B)"],
    ["(if (eq 1 1) (car '(a b)) (cdr '(a b)))", "A"],
    ["((lambda(x) x) 1)", "1"],
    ["((lambda(x y) (cons y x)) 1 2)", "(2 . 1)"],
    ["((lambda(x) ((lambda(y) (cons x y)) 2)) 1)", "(1 . 2)"],
    ["((lambda(f) (f 1)) '(lambda (x) (cons x x)))", "(1 . 1)"],
    ["((lambda(f)(f 1 2)) 'cons)", "(1 . 2)"],
    ["(define '((kaar (lambda(x) (car (car x))))" +
     "(kadr (lambda(x) (car (cdr x))))))", "(KAAR KADR)"],
    ["(kaar '((a b) (c d)))", "A"],
    ["(kadr '((a b) (c d)))", "(C D)"],
    ["(+)", "0"],
    ["(+ 1)", "1"],
    ["(+ 1 2 3)", "6"],
    ["(plus 1 2 3 4)", "10"],
    ["(define '((add-from-0-to-n (lambda(n)(if (eq n 0) 0 " +
     "(+ n (add-from-0-to-n (+ n -1)))))))))", "(ADD-FROM-0-TO-N)"],
    ["(add-from-0-to-n 10)", "55"],
    ["(prog () 1 2 3)", "NIL"],
    ["(prog () (list 1) (return 2) (list 3))", "2"],
    ["(prog () (list 1) (list (return 2)) (list 3))", "2"],
    ["(prog () (list 1) ((lambda(n) (return n)) 2) (list 3))", "2"],
    ["(prog () (go l1) (return 1) l1 (return 2))", "2"],
    ["(prog () (go l3) l1 (return 1) l2 (return 2) l3 (go l1))", "1"],
    ["(prog (a b) (setq a 'b) (set a 99) (return (cons a b)))",
     "(B . 99)"],
    ["(prog (i acc) (setq i 1) (setq acc 0) " +
     "l1 (if (eq i 11) (return acc)) " +
     "(setq acc (+ acc i)) (setq i (+ i 1)) (go l1))", "55"],
    ["(prog2 1 2)", "2"],
    ["(*)", "1"],
    ["(* 2)", "2"],
    ["(* 2 3 4)", "24"],
    ["(times 2 3 4 5)", "120"],
    ["(minus 1)", "-1"],
    ["(-  2 7)", "-5"],
    ["(difference  9 1)", "8"],
    ["(/  9 4)", "2"],
    ["(divide  17 3)", "(5 2)"],
    ["(quotient  13 5)", "2"],
    ["(remainder  11 7)", "4"],
    ["(1+ 1)", "2"],
    ["(add1 2)", "3"],
    ["(1- 3)", "2"],
    ["(sub1 4)", "3"],
    ["(< 1 2)", "*T*"],
    ["(< 2 2)", "NIL"],
    ["(lessp 3 2)", "NIL"],
    ["(> 3 2)", "*T*"],
    ["(> 2 2)", "NIL"],
    ["(greaterp 1 2)", "NIL"],
    ["(zerop 0)", "*T*"],
    ["(zerop 1)", "NIL"],
    ["(onep 0)", "NIL"],
    ["(onep 1)", "*T*"],
    ["(minusp 0)", "NIL"],
    ["(minusp -1)", "*T*"],
    ["(numberp -2)", "*T*"],
    ["(numberp 'number)", "NIL"],
    ["(cond)", "NIL"],
    ["(cond ((< 2 1) 0) ((> 3 2) (* 4 5)) (t 10))", "20"],
    ["((label f (lambda (x) (if (zerop x) 1 (* x (f (1- x)))))) 10)",
     "3628800"],
    ["(((lambda(x)(function(lambda(y)(cons x y)))) 1) 2)", "(1 . 2)"],
    ["(define '((call(lambda(f x)(f x)))))", "(CALL)"],
    ["((lambda(x)(call(quote(lambda(y)(cons x y)))2))1)", "(2 . 2)"],
    ["((lambda(x)(call(function(lambda(y)(cons x y)))2))1)", "(1 . 2)"],
    ["(null nil)", "*T*"],
    ["(null 0)", "NIL"],
    ["(null 'a)", "NIL"],
    ["(null (null 'a))", "*T*"],
    ["(prog (a) (setq a (cons 1 2)) (rplaca a 99) (return a))",
     "(99 . 2)"],
    ["(prog (a) (setq a (cons 1 2)) (rplacd a 99) (return a))",
     "(1 . 99)"],
    ["(flag '(a) 'f1)", "NIL"],
    ["(null (get 'a 'f1))", "NIL"],
    ["(remflag '(a) 'f1)", "NIL"],
    ["(null (get 'a 'f1))", "*T*"],
    ["(trace '(a))", "NIL"],
    ["(null (get 'a 'trace))", "NIL"],
    ["(untrace '(a))", "NIL"],
    ["(null (get 'a 'trace))", "*T*"],
    ["(eval '(car '(a b c)) nil)", "A"],
    ["(eval '(+ 1 2) '((a . 1) (b . 2)))", "3"],
    ["(apply 'cons '(a b) nil)", "(A . B)"],
    ["(apply 'apply '(cons (a b)) nil)", "(A . B)"],
    ["(apply '+ '(1 2) nil)", "3"],
    ["(apply 'add-from-0-to-n '(5) nil)", "15"],
    ["(apply '(lambda(x)(+ x y)) '(1) '((y . 2)))", "3"],
    ["(deflist '((consq (lambda (args a) (cons (car args) " +
     "(eval (car (cdr args)) a))))) 'fexpr)", "(CONSQ)"],
    ["(consq (+ 1 2) (+ 3 4)))", "((+ 1 2) . 7)"],
    ["(cset 'ichigo 'strawberry)", "(STRAWBERRY)"],
    ["ichigo", "STRAWBERRY"],
    ["(csetq ichigo 15)", "(15)"],
    ["ichigo", "15"],
    ["'$$|AllYourBase|", "AllYourBase"],
    ["'$$|(Kari)|", "(Kari)"],
    ["(atom '$$|(Kari)|)", "*T*"],
    ["'$", "$"],
    ["'$a", "$A"],
    ["(advance)", "$EOF$"],
    ["(advance)Non-S-exp text", "N"],
    ["(endread)", "$EOF$"],
    ["(select 2 (2 'b) ((- 4 1) 'c) 'd)", "B"],
    ["(select (+ 1 2) (2 'b) ((- 4 1) 'c) 'd)", "C"],
    ["(select t (2 'b) ((- 4 1) 'c) 'd)", "D"],
    ["(and)", "*T*"],
    ["(and t)", "*T*"],
    ["(and f)", "NIL"],
    ["(and t t)", "*T*"],
    ["(and t f t)", "NIL"],
    ["(or)", "NIL"],
    ["(or t)", "*T*"],
    ["(or f)", "NIL"],
    ["(or f f)", "NIL"],
    ["(csetq ichigo 'matsuri)", "(MATSURI)"],
    ["(or ichigo t)", "MATSURI"],
    ["(logand)", "-1"],
    ["(logand 3)", "3"],
    ["(logand 3 -1 1)", "1"],
    ["(logor)", "0"],
    ["(logor 3)", "3"],
    ["(logor 3 0 4)", "7"],
    ["(logxor)", "0"],
    ["(logxor 3)", "3"],
    ["(logxor 3 0 1)", "2"],
    ["(max -1234567)", "-1234567"],
    ["(max 55 22 88 33)", "88"],
    ["(min 1234567)", "1234567"],
    ["(min 55 22 88 33)", "22"],
    ["(nconc nil 2)", "2"],
    ["(nconc (list 1) 2)", "(1 . 2)"],
    ["(nconc (list 1) (list 2))", "(1 2)"],
    ["(conc)", "NIL"],
    ["(conc 1)", "1"],
    ["(conc (list (cons 1 2)) (list 3) (list (list 4 5)))",
     "((1 . 2) 3 (4 5))"],
    ["(traceset '(a))", "NIL"],
    ["(null (get 'a 'traceset))", "NIL"],
    ["(untraceset '(a))", "NIL"],
    ["(null (get 'a 'traceset))", "*T*"],
    ["(clearbuff)", "NIL"],
    ["(pack 'z)", "NIL"],
    ["(atom (mknam))", "NIL"],
    ["(prog()(pack 'z)(pack 'i)(pack 'c)(pack 'k))", "NIL"],
    ["(intern (mknam))", "ZICK"],
    ["(prog () (pack dash)(pack 1)(pack 2)(pack 3))", "NIL"],
    ["(* (numob) 10)", "-1230"],
    ["(unpack (car (get 'hoge 'pname)))", "(H O G)"],
    ["(unpack (car (cdr (get 'hoge 'pname))))", "(E)"],
    ["(unpack 'hoge)", "(H O G E)"],
    ["(liter 'a)", "*T*"],
    ["(liter 'z)", "*T*"],
    ["(liter '$$|a|)", "*T*"],
    ["(liter '$$|z|)", "*T*"],
    ["(liter '+)", "NIL"],
    ["(liter '$$|0|)", "NIL"],
    ["(digit '$$|0|)", "*T*"],
    ["(digit '$$|9|)", "*T*"],
    ["(digit 'a)", "NIL"],
    ["(digit '+)", "NIL"],
    ["(opchar '+)", "*T*"],
    ["(opchar '-)", "*T*"],
    ["(opchar '*)", "*T*"],
    ["(opchar '/)", "*T*"],
    ["(opchar '=)", "*T*"],
    ["(opchar '_)", "NIL"],
    ["(opchar 'a)", "NIL"],
    ["(opchar '$$|0|)", "NIL"],
    ["(dash '-)", "*T*"],
    ["(dash '+)", "NIL"],
    ["(dash 'a)", "NIL"],
    ["(dash '$$|0|)", "NIL"],
    ["(append '() '(d e f))", "(D E F)"],
    ["(append '(a) '(d e f))", "(A D E F)"],
    ["(append '(a b c) '(d e f))", "(A B C D E F)"],
    ["(attrib 'konst '(apval (42))))", "(APVAL (42))"],
    ["konst", "42"],
    ["(copy '(a (b) c))", "(A (B) C)"],
    ["(prog (x y) (setq x '(a (b) c)) (setq y (copy x)) (rplaca x 'z)" +
     "(return (list x y)))", "((Z (B) C) (A (B) C))"],
    ["(not t)", "NIL"],
    ["(not f)", "*T*"],
    ["(prop 't 'apval '+)", /T/],
    ["(prop 't 'fsubr '+)", "0"],
    ["(prop 't 'fsubr '(lambda()'noval))", "NOVAL"],
    ["(remprop 'ichigo 'apval)", "NIL"],
    ["(get 'ichigo 'apval)", "NIL"],
    ["(pair nil nil)", "NIL"],
    ["(pair '(a b) '(1 2))", "((B . 2) (A . 1))"],
    ["(sassoc 'b '((a 1)(b 2)(c 3)) '+)", "(B 2)"],
    ["(sassoc 'd '((a 1)(b 2)(c 3)) '+)", "0"],
    ["(subst 'ichigo 15 '(14 (15 15) 14 . 15))",
     "(14 (ICHIGO ICHIGO) 14 . ICHIGO)"],
    ["(sublis '((x . ichigo) (y . 15)) '(x is y))", "(ICHIGO IS 15)"],
    ["(reverse '(a (b . d) c))", "(C (B . D) A)"],
    ["(member 'b '(a b c))", "(B C)"],
    ["(member 'd '(a b c))", "NIL"],
    ["(length nil)", "0"],
    ["(length '(a (b c) d))", "3"],
    ["(efface 0 '(1 2 3))", "(1 2 3)"],
    ["(efface 2 '(2 2 3 2 2 4 2))", "(3 4)"],
    ["(maplist '(1 2 3) 'length)", "(3 2 1)"],
    ["(maplist '(1 2 3) '(lambda(x)(1+ (car x))))", "(2 3 4)"],
    ["(mapcon '(1 2 3) '(lambda(x)(list (car x) (car x))))",
     "(1 1 2 2 3 3)"],
    ["(map '(1 2 3) 'length)", "NIL"],
    ["(search '(a b 3 d) '(lambda(x) (numberp (car x))) " +
     "'(lambda(x) (1+ (car x))) '(lambda (x) x))", "4"],
    ["(search '(a b c d) '(lambda(x) (numberp (car x))) " +
     "'(lambda(x) (1+ (car x))) '(lambda (x) x))", "NIL"],
    ["(recip 1)", "0"],
    ["(expt 2 0)", "1"],
    ["(expt 2 1)", "2"],
    ["(expt 2 8)", "256"],
    ["(fixp 1)", "*T*"],
    ["(fixp t)", "NIL"],
    ["(floatp 1)", "NIL"],
    ["(floatp t)", "NIL"],
    ["(leftshift 3 2)", "12"],
    ["(leftshift 12 -1)", "6"],
    ["(read)(This is a pen)", "(THIS IS A PEN)"],
    ["(length (read))(This is a pen)", "4"],
    ["(atom (gensym))", "*T*"],
    ["(eq (gensym) (gensym))", "NIL"],
    ["(prog () (csetq gomi 'kasu) (return (remob 'kasu)))", "KASU"],
    ["(eq gomi 'kasu)", "NIL"],
    ["(evlis '(t f (+ 1 2)) nil)", "(*T* NIL 3)"],
    ["(common '(a))", "NIL"],
    ["(null (get 'a 'common))", "NIL"],
    ["(uncommon '(a))", "NIL"],
    ["(get 'a 'common)", "NIL"],
    ["(special '(a))", "NIL"],
    ["(null (get 'a 'special))", "NIL"],
    ["(unspecial '(a))", "NIL"],
    ["(get 'a 'special)", "NIL"],

    // APVALs
    ["blank", " "],
    ["(numberp charcount)", "*T*"],
    ["comma", ","],
    ["(atom curchar)", "*T*"],
    ["dollar", "$"],
    ["eof", "$EOF$"],
    ["eor", "$EOR$"],
    ["eqsign", "="],
    ["f", "NIL"],
    ["lpar", "("],
    ["nil", "NIL"],
    ["(atom oblist)", "NIL"],
    ["(atom (car oblist))", "*T*"],
    ["period", "."],
    ["pluss", "+"],
    ["rpar", ")"],
    ["slash", "/"],
    ["star", "*"],
    ["t", "*T*"],
    ["*t*", "*T*"],

    // Errors
    ["", /R4/],
    ["(", /R4/],
    ["((", /R4/],
    ["(a b .", /R4/],
    ["))))", /R1/],
    ["(a .)", /R1/],
    ["(a . b c)", /R1/],
    ["ub", /A8/],
    ["#x", /A8/],
    ["#xfg", /A8/],
    ["0x", /A8/],
    ["0xfh", /A8/],
    ["(cons 1 ub)", /A8/],
    ["(if ub 1 2)", /A8/],
    ["(if t ub 2)", /A8/],
    ["(if f ub 2)", "2"],
    ["(list 1 2 3 4 5 ub 6)", /A8/],
    ["(+ 1 2 3 4 5 ub 6)", /A8/],
    ["(1 2)", /A2/],
    ["(ub 2)", /A2/],
    ["((lambda(a)(a 1)) 'a)", /A2/],
    ["(car 'a)", /P1/],
    ["(prog () (list 1) (list ub) (list 3))", /A8/],
    ["(prog () (go label) (return 0))", /A6/],
    ["(prog2 ub 2)", /A8/],
    ["(+ 1 'one)", /I3/],
    ["(- 1 'one)", /I3/],
    ["(cond ((< 2 1) 0) ((> 3 2) (list ub)) (t 10))", /A8/],
    ["(cond ((< 2 1) 0) ((> 3 'a) (* 4 5)) (t 10))", /I3/],
    ["(eval 'ub)", /A8/],
    ["$$", /R4/],
    ["$$|", /R4/],
    ["$$|foo", /R4/],
    ["(select ub (2 'b) (3 'c) 'd)", /A8/],
    ["(select t (2 'b) (ub 'c) 'd)", /A8/],
    ["(and t ub t)", /A8/],
    ["(or f ub t)", /A8/],
    ["(logand 1 ub 3)", /A8/],
    ["(logand 1 'a 3)", /I3/],
    ["(max 1 ub 3)", /A8/],
    ["(max 1 'a 3)", /I3/],
    ["(conc (list 1) ub (list 3))", /A8/],
    ["(maplist '(1 2 3) '(lambda(x) ub))", /A8/],
    ["(mapcon '(1 2 3) '(lambda(x) ub))", /A8/],
]);
test_data.push([
    ["(de nilfn () nil)", "NILFN"],
    ["(nilfn)", "NIL"],
    ["(compile '(nilfn))", "NIL"],
    ["(nilfn)", "NIL"],

    ["(de numfn () 42)", "NUMFN"],
    ["(numfn)", "42"],
    ["(compile '(numfn))", "NIL"],
    ["(numfn)", "42"],

    ["(de argfn (x) x)", "ARGFN"],
    ["(argfn 15)", "15"],
    ["(compile '(argfn))", "NIL"],
    ["(argfn 15)", "15"],

    ["(de argfn2 (x y) y)", "ARGFN2"],
    ["(argfn2 15 16)", "16"],
    ["(compile '(argfn2))", "NIL"],
    ["(argfn2 15 16)", "16"],

    ["(de subrfn (x) (1+ x))", "SUBRFN"],
    ["(subrfn 1)", "2"],
    ["(compile '(subrfn))", "NIL"],
    ["(subrfn 1)", "2"],

    ["(de subrfn2 (x y) (cons x (cons y nil)))", "SUBRFN2"],
    ["(subrfn2 1 2)", "(1 2)"],
    ["(compile '(subrfn2))", "NIL"],
    ["(subrfn2 1 2)", "(1 2)"],

    ["(de tasu1 (x) (1+ x))", "TASU1"],
    ["(de exprfn (x) (tasu1 x))", "EXPRFN"],
    ["(exprfn 1)", "2"],
    ["(compile '(exprfn))", "NIL"],
    ["(exprfn 1)", "2"],
    ["(compile '(tasu1))", "NIL"],
    ["(exprfn 1)", "2"],
    ["(de tasu1 (x) (cons x x))", "TASU1"],
    ["(exprfn 1)", "(1 . 1)"],

    ["(de produce-a (a) (alistfn))", "PRODUCE-A"],
    ["(de consume-a () (cons a a))", "CONSUME-A"],
    ["(de alistfn () (consume-a))", "ALISTFN"],
    ["(produce-a 15)", "(15 . 15)"],
    ["(compile '(alistfn))", "NIL"],
    ["(produce-a 15)", "(15 . 15)"],

    ["(de errorfn () (cons nil (1+ nil)))", "ERRORFN"],
    ["(errorfn)", /I3/],
    ["(compile '(errorfn))", "NIL"],
    ["(errorfn)", /I3/],

    ["(de errorfn2 () (trace (1+ nil)))", "ERRORFN2"],
    ["(errorfn2)", /I3/],
    ["(compile '(errorfn2))", "NIL"],
    ["(errorfn2)", /I3/],

    ["(de errorfn3 () (no-def 1 5))", "ERRORFN3"],
    ["(errorfn3)", /A2/],
    ["(compile '(errorfn3))", "NIL"],
    ["(errorfn3)", /A2/],

    ["(de fsubrfn (x) (+ x (if (zerop x) 256 (* x x))))", "FSUBRFN"],
    ["(fsubrfn 0)", "256"],
    ["(fsubrfn 3)", "12"],
    ["(compile '(fsubrfn))", "NIL"],
    ["(fsubrfn 0)", "256"],
    ["(fsubrfn 3)", "12"],

    ["(de iffn (x) (if x 2 3))", "IFFN"],
    ["(iffn t)", "2"],
    ["(iffn nil)", "3"],
    ["(compile '(iffn))", "NIL"],
    ["(iffn t)", "2"],
    ["(iffn nil)", "3"],

    ["(de condfn (x) (cond ((null x) 0) (t 1)))", "CONDFN"],
    ["(condfn nil)", "0"],
    ["(condfn t)", "1"],
    ["(compile '(condfn))", "NIL"],
    ["(condfn nil)", "0"],
    ["(condfn t)", "1"],

    ["(defun andfn (x y) (and (print x) (print y) 99))", "ANDFN"],
    ["(andfn 1 2)", "99"],
    ["(andfn nil 2)", "NIL"],
    ["(compile '(andfn))", "NIL"],
    ["(andfn 1 2)", "99"],
    ["(andfn nil 2)", "NIL"],

    ["(defun quotefn () (cons 'a 'b))", "QUOTEFN"],
    ["(quotefn)", "(A . B)"],
    ["(compile '(quotefn))", "NIL"],
    ["(quotefn)", "(A . B)"],

    ["(defun quotefn2 () (cons 'a '(b c)))", "QUOTEFN2"],
    ["(quotefn2)", "(A B C)"],
    ["(compile '(quotefn2))", "NIL"],
    ["(quotefn2)", "(A B C)"],

    ["(defun logandfn () (logand 0xff 0x7f 0x3f))", "LOGANDFN"],
    ["(logandfn)", "63"],
    ["(compile '(logandfn))", "NIL"],
    ["(logandfn)", "63"],

    ["(defun logorfn () (logor 0xff 0x7f 0x3f))", "LOGORFN"],
    ["(logorfn)", "255"],
    ["(compile '(logorfn))", "NIL"],
    ["(logorfn)", "255"],

    ["(defun logxorfn () (logxor 0xff 0x7f 0x3f))", "LOGXORFN"],
    ["(logxorfn)", "191"],
    ["(compile '(logxorfn))", "NIL"],
    ["(logxorfn)", "191"],

    ["(defun maxfn () (max 7 3 9))", "MAXFN"],
    ["(maxfn)", "9"],
    ["(compile '(maxfn))", "NIL"],
    ["(maxfn)", "9"],

    ["(defun minfn () (min 7 3 9))", "MINFN"],
    ["(minfn)", "3"],
    ["(compile '(minfn))", "NIL"],
    ["(minfn)", "3"],

    ["(defun plusfn () (+ 2 3 4))", "PLUSFN"],
    ["(plusfn)", "9"],
    ["(compile '(plusfn))", "NIL"],
    ["(plusfn)", "9"],

    ["(defun timesfn () (* 2 3 4))", "TIMESFN"],
    ["(timesfn)", "24"],
    ["(compile '(timesfn))", "NIL"],
    ["(timesfn)", "24"],

    ["(defun factfn (n) (cond ((zerop n) 1) (t (* n (factfn (1- n))))))",
     "FACTFN"],
    ["(factfn 10)", "3628800"],
    ["(compile '(factfn))", "NIL"],
    ["(factfn 10)", "3628800"],

    ["(defun lambdafn () ((lambda(x)(cons x x)) 1))", "LAMBDAFN"],
    ["(lambdafn)", "(1 . 1)"],
    ["(compile '(lambdafn))", "NIL"],
    ["(lambdafn)", "(1 . 1)"],

    ["(defun compfn () ((car '((lambda(x)(cons x x)))) 'a))", "COMPFN"],
    ["(compfn)", "(A . A)"],
    ["(compile '(compfn))", "NIL"],
    ["(compfn)", "(A . A)"],

    ["(defun fargfn (f) (f 99))", "FARGFN"],
    ["(fargfn '(lambda(x) (1+ x)))", "100"],
    ["(fargfn '1-)", "98"],
    ["(compile '(fargfn))", "NIL"],
    ["(fargfn '(lambda(x) (1+ x)))", "100"],
    ["(fargfn '1-)", "98"],

    ["(defun listfn () (list 1 (+ 2 3) 4))", "LISTFN"],
    ["(listfn)", "(1 5 4)"],
    ["(compile '(listfn))", "NIL"],
    ["(listfn)", "(1 5 4)"],

    ["(defun lambdacfn (x y) (list ((lambda(x) (list x y)) 99) x y))",
     "LAMBDACFN"],
    ["(lambdacfn 1 2)", "((99 2) 1 2)"],
    ["(compile '(lambdacfn))", "NIL"],
    ["(lambdacfn 1 2)", "((99 2) 1 2)"],

    ["(defun funcfn (x) (function (lambda (y) (+ x y))))", "FUNCFN"],
    ["((funcfn 1) 99)", "100"],
    ["(compile '(funcfn))", "NIL"],
    ["((funcfn 1) 99)", "100"],

    ["(defun funcfn2 (x y) (maplist y (function " +
     "(lambda (z) (cons x (car z))))))", "FUNCFN2"],
    ["(funcfn2 'z '(a b c))", "((Z . A) (Z . B) (Z . C))"],
    ["(compile '(funcfn2))", "NIL"],
    ["(funcfn2 'z '(a b c))", "((Z . A) (Z . B) (Z . C))"],

    ["(defun funcfn3 (x) (maplist x 'car))", "FUNCFN3"],
    ["(funcfn3 '(a b c))", "(A B C)"],
    ["(compile '(funcfn3))", "NIL"],
    ["(funcfn3 '(a b c))", "(A B C)"],

    ["(defun labelfn (x) ((label rec (lambda (n) " +
     "(if (zerop n) 0 (+ n (rec (1- n)))))) x))", "LABELFN"],
    ["(LABELFN 10)", "55"],
    ["(compile '(labelfn))", "NIL"],
    ["(LABELFN 10)", "55"],

    ["(defun orfn (x y) (or (print x) (print y) (print 3)))", "ORFN"],
    ["(orfn 1 nil)", "1"],
    ["(orfn nil nil)", "3"],
    ["(compile '(orfn))", "NIL"],
    ["(orfn 1 nil)", "1"],
    ["(orfn nil nil)", "3"],

    ["(defun setqfn (x) (list (setq x (1+ x)) (setq x (1+ x)) x))", "SETQFN"],
    ["(setqfn 1)", "(2 3 3)"],
    ["(compile '(setqfn)))", "NIL"],
    ["(setqfn 1)", "(2 3 3)"],

    ["(defun gen (n) (function (lambda (m) (setq n (+ n m)))))", "GEN"],
    ["(prog (x) (setq x (gen 100)) (return (list (x 10) (x 90) (x 300))))",
     "(110 200 500)"],
    ["(compile '(gen))", "NIL"],
    ["(prog (x) (setq x (gen 100)) (return (list (x 10) (x 90) (x 300))))",
     "(110 200 500)"],

    ["(defun hsetqfn (x) (list (function (lambda()x)) (setq x (+ x 1)) x))",
     "HSETQFN"],
    ["(cdr (hsetqfn 99))", "(100 100)"],
    ["(compile '(hsetqfn)))", "NIL"],
    ["(cdr (hsetqfn 99))", "(100 100)"],

    ["(defun concfn () (conc (list (cons 1 2)) (list 3) (list (list 4 5))))",
     "CONCFN"],
    ["(concfn)", "((1 . 2) 3 (4 5))"],
    ["(compile '(concfn))", "NIL"],
    ["(concfn)", "((1 . 2) 3 (4 5))"],

    ["(defun selectfn (x) (select x (1 'a) (2 'b) (3 'c) 'd))", "SELECTFN"],
    ["(selectfn 2)", "B"],
    ["(selectfn 99)", "D"],
    ["(compile '(selectfn))", "NIL"],
    ["(selectfn 2)", "B"],
    ["(selectfn 99)", "D"],

    ["(defun progfn() (prog () (list 1) (return 2) (list 3)))", "PROGFN"],
    ["(progfn)", "2"],
    ["(compile '(progfn))", "NIL"],
    ["(progfn)", "2"],

    ["(defun returnfn() (prog () (+ 1 2 (return 3))))", "RETURNFN"],
    ["(returnfn)", "3"],
    ["(compile '(returnfn))", "NIL"],
    ["(returnfn)", "3"],

    ["(defun gofn() (prog () (go l3) l1 (return 1) l2 (return 2) l3 (go l1)))",
     "GOFN"],
    ["(gofn)", "1"],
    ["(compile '(gofn))", "NIL"],
    ["(gofn)", "1"],

    ["(defun loopfn (n) (prog (i acc) (setq i 1) (setq acc 0) " +
     "l1 (if (> i n) (return acc)) " +
     "(setq acc (+ acc i)) (setq i (+ i 1)) (go l1))))", "LOOPFN"],
    ["(loopfn 10)", "55"],
    ["(compile '(loopfn))", "NIL"],
    ["(loopfn 10)", "55"],

    ["(defun arg8fn (a b c d e x y z) (list z y x e d c b a))", "ARG8FN"],
    ["(arg8fn 1 2 3 4 5 6 7 8)", "(8 7 6 5 4 3 2 1)"],
    ["(compile '(arg8fn))", "NIL"],
    ["(arg8fn 1 2 3 4 5 6 7 8)", "(8 7 6 5 4 3 2 1)"],

    ["(defun var8fn() (prog (a b c d e x y z) (setq a 1) (setq c 2) " +
     "(setq e 3) (setq y 4) (setq b 5) (setq d 6) (setq x 7) (setq z 8) " +
     "(return (list a b c d e x y z))))", "VAR8FN"],
    ["(var8fn)", "(1 5 2 6 3 7 4 8)"],
    ["(compile '(var8fn))", "NIL"],
    ["(var8fn)", "(1 5 2 6 3 7 4 8)"],

    ["(common '(cov1))", "NIL"],
    ["(defun commonfn () (* cov1 2))", "COMMONFN"],
    ["((lambda (cov1) (commonfn)) 9)", "18"],
    ["(compile '(commonfn))", "NIL"],
    ["((lambda (cov1) (commonfn)) 9)", "18"],

    ["(defun commonfn2 (cov1 f) (f))", "COMMONFN2"],
    ["(commonfn2 99 '(lambda() (1+ cov1)))", "100"],
    ["(compile '(commonfn2))", "NIL"],
    ["(commonfn2 99 '(lambda() (1+ cov1)))", "100"],

    ["(defun commonfn3 () (setq cov1 (+ cov1 2)))", "COMMONFN3"],
    ["((lambda (cov1) (cons (commonfn3) cov1)) 9)", "(11 . 11)"],
    ["(compile '(commonfn3))", "NIL"],
    ["((lambda (cov1) (cons (commonfn3) cov1)) 9)", "(11 . 11)"],

    ["(special '(sv1))", "NIL"],
    ["(defun specialfn () (* sv1 2))", "SPECIALFN"],
    ["(defun specialfn2 (sv1) (specialfn))", "SPECIALFN2"],
    ["(defun specialfn3 (sv1) (list (specialfn) (specialfn2 (1+ sv1)) sv1))",
     "SPECIALFN3"],
    ["(compile '(specialfn specialfn2 specialfn3))", "NIL"],
    ["(specialfn3 2)", "(4 6 2)"],

    ["(defun spprogfn () (prog () (return (* sv1 2))))", "SPPROGFN"],
    ["(defun spprogfn2 (x) (prog (sv1) (setq sv1 x) (return (spprogfn))))",
     "SPPROGFN2"],
    ["(defun spprogfn3 (x) (prog (sv1) (setq sv1 x) " +
     "(return (list (spprogfn) (spprogfn2 (1+ sv1)) sv1))))",
     "SPPROGFN3"],
    ["(compile '(spprogfn spprogfn2 spprogfn3))", "NIL"],
    ["(spprogfn3 2)", "(4 6 2)"],

    ["(df quoteff (s a) (car s)) ", "QUOTEFF"],
    ["(compile '(quoteff))", "NIL"],
    ["(quoteff (a b c))", "(A B C)"],

    ["(df evalff (s a) (eval (car s) a)) ", "EVALFF"],
    ["(compile '(evalff))", "NIL"],
    ["(evalff (+ 1 2))", "3"],

    ["(df ifff (s a) (if (eval (car s) a) (eval (cadr s) a) " +
     "(eval (car (cddr s)) a))) ", "IFFF"],
    ["(compile '(ifff))", "NIL"],
    ["((lambda (x) (ifff (onep (setq x (1+ x))) (setq x (* x 8)) x)) 0)", "8"],
    ["((lambda (x) (ifff (onep (setq x (1+ x))) (setq x (* x 2)) x)) 1)", "2"],
]);
