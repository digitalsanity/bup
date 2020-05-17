#!/usr/bin/env bash
. wvtest-bup.sh || exit $?
. t/lib.sh || exit $?

set -o pipefail

TOP="$(WVPASS pwd)" || exit $?
tmpdir="$(WVPASS wvmktempdir)" || exit $?
export BUP_DIR="$tmpdir/bup"

bup()
{
    "$TOP/bup" "$@"
}

wait-for-server-start()
{
    curl --unix-socket ./socket http://localhost/
    curl_status=$?
    while test $curl_status -eq 7; do
        sleep 0.2
        curl --unix-socket ./socket http://localhost/
        curl_status=$?
    done
    WVPASSEQ $curl_status 0
}

WVPASS cd "$tmpdir"

# FIXME: add WVSKIP
if test -z "$(type -p curl)"; then
    WVSTART 'curl does not appear to be installed; skipping  test'
    exit 0
fi
    
WVPASS bup-python -c "import socket as s; s.socket(s.AF_UNIX).bind('socket')"
curl -s --unix-socket ./socket http://localhost/foo
if test $? -ne 7; then
    WVSTART 'curl does not appear to support --unix-socket; skipping test'
    exit 0
fi

if ! bup-python -c 'import tornado' 2> /dev/null; then
    WVSTART 'unable to import tornado; skipping test'
    exit 0
fi

WVSTART 'web'
WVPASS bup init
WVPASS mkdir src
WVPASS echo '¡excitement!' > src/data
WVPASS echo -e 'whee \x80\x90\xff' > "$(echo -ne 'src/whee \x80\x90\xff')"
WVPASS bup index src
WVPASS bup save -n '¡excitement!' --strip src

"$TOP/bup" web unix://socket &
web_pid=$!
wait-for-server-start

WVPASS curl --unix-socket ./socket \
       'http://localhost/%C2%A1excitement%21/latest/data' > result
WVPASS curl --unix-socket ./socket \
       'http://localhost/%C2%A1excitement%21/latest/whee%20%80%90%ff' > result2
WVPASSEQ "$(curl --unix-socket ./socket http://localhost/static/styles.css)" \
         "$(cat "$TOP/lib/web/static/styles.css")"

WVPASSEQ '¡excitement!' "$(cat result)"
WVPASS cmp "$(echo -ne 'src/whee \x80\x90\xff')" result2
WVPASS kill -s TERM "$web_pid"
WVPASS wait "$web_pid"

WVPASS rm -r "$tmpdir"
