#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../scripts/test-lib.sh"

# The commands of TEXT, one per line: argv joined by a space, then " > target" for each redirect.
commands() {
  printf '%s' "$1" | node "$here/command.mjs" | jq -r '
    if .ok then .commands[] | (.argv | join(" ")) + (.redirects | map(" " + .op + " " + .target) | join(""))
    else "not ok" end'
}
reads() { # NAME TEXT EXPECTED — EXPECTED has " | " between commands
  eq "$1" "$(commands "$2" | awk 'NR > 1 { printf " | " } { printf "%s", $0 }')" "$3"
}

echo "# splitting"
reads "one command"                 'git status --short'                 'git status --short'
reads "the operators"               'a && b || c; d | e & f'             'a | b | c | d | e | f'
reads "a newline"                   $'a\nb'                              'a | b'
reads "an operator in quotes"       'git commit -m "x; y && z | w"'      'git commit -m x; y && z | w'
reads "single quotes"               "echo 'a; b'"                        'echo a; b'
reads "a backslash"                 'echo a\;b \| c'                     'echo a;b | c'
reads "a comment"                   'ls # git push'                      'ls'
reads "a # inside a word"           'echo a#b'                           'echo a#b'
reads "a line continuation"         $'git \\\n  status'                  'git status'

echo "# what runs inside"
reads "a subshell"                  '(a; b)'                             'a | b'
reads "a group"                     '{ a; b; }'                          'a | b'
reads "a substitution"              'echo $(a b)'                        'echo $(a b) | a b'
reads "a substitution in quotes"    'echo "x $(a b) y"'                  'echo x $(a b) y | a b'
reads "one inside another"          'echo $(a $(b))'                     'echo $(a $(b)) | a $(b) | b'
reads "backticks"                   'echo `a b`'                         'echo `a b` | a b'
reads "a process substitution"      'diff <(a) <(b)'                     'diff <(a) <(b) | a | b'
reads "single quotes hide one"      "echo '\$(a b)'"                     'echo $(a b)'
reads "the keywords"                'if a; then b; else c; fi'           'a | b | c'
reads "a loop"                      'for f in x y; do a "$f"; done'      'for f in x y | a $f'
reads "a function"                  'f() { a; }; f'                      'f | a | f'
reads "an array is not a command"   'xs=(a b); c'                        'c'

echo "# wrappers"
reads "an assignment before"        'A=1 B="2 3" git push'               'git push'
reads "only an assignment"          'A=1'                                ''
reads "command"                     'command git push'                   'git push'
reads "command -v is a lookup"      'command -v git'                     'command -v git'
reads "env with its options"        'env -i -u HOME A=1 git push'        'git push'
reads "sudo with a user"            'sudo -u dev git push'               'git push'
reads "exec, nohup, time"           'exec git a; nohup git b; time -p git c' 'git a | git b | git c'
reads "timeout and its duration"    'timeout -s KILL 30 git push'        'git push'
reads "a path before the name"      '/usr/bin/git push'                  'git push'
reads "a backslash before the name" '\git push'                          'git push'
reads "quotes around the name"      "\"git\" push; g'i't tag"            'git push | git tag'
reads "one wrapper in another"      'sudo env A=1 nohup command git push' 'git push'
reads "xargs"                       'ls | xargs -n 1 -I {} git add {}'   'ls | git add {}'
reads "find -exec"                  'find . -name x -exec git rm {} \; -print' 'find . -name x -exec git rm {} ; -print | git rm {}'
reads "bash -c"                     "bash -c 'a && b'"                   'a | b'
reads "sh with a flag cluster"      "sh -euc 'a; b'"                     'a | b'
reads "bash -c in bash -c"          "bash -c \"bash -c 'git push'\""     'git push'
reads "bash with a file"            'bash scripts/x.sh a'                'bash scripts/x.sh a'
reads "eval"                        'eval "git push" origin'             'git push origin'
reads "a name built at run time"    '$GIT push; `which git` tag'         '? push | ? tag | which git'

echo "# git before its subcommand"
reads "-C and -c"                   'git -C /r -c a.b=c commit -m x'     'git commit -m x'
reads "-c that sets an alias"       'git -c alias.st=!rm status'         'git config-that-runs-a-command'
reads "-c that sets a pager"        'git -c core.pager=sh log'           'git config-that-runs-a-command'
reads "--git-dir=x"                 'git --git-dir=.git --no-pager log'  'git log'
reads "--git-dir x"                 'git --git-dir .git status'          'git status'
reads "only a flag"                 'git --version'                      'git --version'
reads "nothing"                     'git'                                'git'

echo "# redirects"
reads "to a file"                   'a > out.txt'                        'a > out.txt'
reads "append, with an fd"          'a 2>> err.log'                      'a >> err.log'
reads "both streams"                'a &> all.log'                       'a &> all.log'
reads "an fd copy is not a file"    'a > /dev/null 2>&1'                 'a > /dev/null'
reads "input"                       'a < in.txt'                         'a < in.txt'
reads "a here-string"               'a <<< "x y"'                        'a <<< x y'
reads "a > in quotes"               'node -e "x => y > 1"'               'node -e x => y > 1'
reads "inside bash -c, with the outer one" "bash -c 'a > in.txt' > out.txt" 'a > in.txt > out.txt'
reads "a heredoc and a redirect"    $'cat > f.txt <<EOF\nbody; git push\nEOF\nb' 'cat > f.txt | b'
reads "a heredoc runs its \$( )"    $'cat <<EOF\n$(git stash)\nEOF'      'cat | git stash'
reads "a quoted heredoc does not"   $'cat <<\'EOF\'\n$(git stash)\nEOF'  'cat'
reads "a heredoc with no end"       "cat > probe.cjs <<'EOF'"            'cat > probe.cjs'

echo "# text it cannot read"
reads "an open double quote"        'echo "abc'                          'not ok'
reads "an open single quote"        "echo 'abc"                          'not ok'
reads "an open substitution"        'echo $(git stash'                   'not ok'
reads "a redirect with no target"   'a >'                                'not ok'
reads "the same inside bash -c"     "bash -c 'echo \"abc'"               'not ok'

echo "# the form guard.sh reads"
lines() { printf '%s' "$1" | node "$here/command.mjs" --lines | tr '\037' '^'; }
eq "a command and its redirect"     "$(lines 'a "b c" > out')"           $'C^a^b c\nR^>^out'
eq "a newline in an argument"       "$(lines $'echo "a\nb"')"            'C^echo^a b'
eq "an empty argument is kept"      "$(lines 'a "" b')"                  'C^a^^b'
eq "not parsed"                     "$(lines 'echo "abc')"               'X'

finish
