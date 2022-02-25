var ichigo = new Worker('ichigo.js');
var ichigo_lock = false;

function htmlEscape(str) {
    return str
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/  /g, '&nbsp;&nbsp;')
        .replace(/\n/g, '<br />');
}
function writeToTerminal(str) {
    var first = true;
    var lines = str.split('\n')
    for (var i in lines) {
        var line = lines[i];
        var comp = line.indexOf(';');
        var com = (comp < 0) ? '' : line.substr(comp);
        var out = ''
        if (first) {
            first = false;
        } else {
            out += '<br />';
        }
        out += htmlEscape(
            line.substr(0, (comp < 0) ? line.length : comp - 1));
        if (com.length > 0) {
            out += "<span class='comment'>" + htmlEscape(com) + "</span>";
        }
        document.getElementById('terminal').innerHTML += out;
    }
}

function startEval() {
    if (ichigo_lock) {
        console.log('startEval was called during ichigo_lock is true');
        return;
    } else {
        ichigo_lock = true;
    }

    var str = document.getElementById('input').value;
    writeToTerminal(str + '\n');
    document.getElementById('input').value = '';

    var sender = ['eval', str];
    ichigo.postMessage([sender, 'eval', str]);
}
function endEval(sender, out) {
    var sender_type = sender[0];
    if (sender_type == 'eval') {
        writeToTerminal('\n');
        writeToTerminal('> ');
        ichigo_lock = false;
    }
    if (sender_type == 'test') {
        var test_idx = sender[1];
        checkTest(test_idx, out);
        writeToTerminal('\n');
        writeToTerminal('> ');
        if (test_idx < test_data.length - 1) {
            doTest(test_idx + 1);
        } else {
            endTest();
            ichigo_lock = false;
        }
    }
}

function setDebugLevel() {
    var str = document.getElementById('input').value;
    document.getElementById('input').value = '';
    var level = Number(str);

    var sender = ['debug_level', level];
    ichigo.postMessage([sender, 'debug_level', level]);
}

var num_pass = 0;
var num_fail = 0;
function doTest(i) {
    var str = test_data[i][0];
    writeToTerminal(str + '\n');

    var sender = ['test', i];
    ichigo.postMessage([sender, 'eval', str]);
}
function checkTest(i, out) {
    var pass = false;
    if (test_data[i][1] instanceof RegExp) {
        pass = test_data[i][1].test(out);
    } else {
        pass = (test_data[i][1] == out);
    }

    if (pass) {
        writeToTerminal('  ;; OK');
        num_pass++;
    } else {
        writeToTerminal('  ;; Failed' + '\n' +
                        ';; Expected: ' + test_data[i][1] + '\n' +
                        ';; Actual: ' + out);
        num_fail++;
    }
}
function startTest() {
    if (ichigo_lock) {
        console.log('startTest was called during ichigo_lock is true');
        return;
    } else {
        ichigo_lock = true;
    }

    num_pass = 0;
    num_fail = 0;
    doTest(0);
}
function endTest() {
    document.getElementById('msg').innerText = 'pass: ' + num_pass +
        '  fail: ' + num_fail
}

window.onload = function() {
    writeToTerminal('> ');
};

ichigo.onmessage = function(e) {
    if (e.data.length < 2) {
        console.log('main received a wrong message');
        return;
    }
    var sender = e.data[0]
    var type = e.data[1];
    if (type == 'eval') {
        endEval(sender, e.data[2]);
    } else if (type == 'print') {
        writeToTerminal(e.data[2]);
    } else if (type == 'debug_level') {
    }
}
