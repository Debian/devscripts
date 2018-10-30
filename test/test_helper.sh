setUp() {
    tmpdir=$(mktemp -d)
    log="$tmpdir/log"
}

tearDown() {
    rm -rf "$tmpdir"
}

assertPasses() {
    local rc=0
    "$@" > "$log" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
        cat "$log"
        fail "command failed: «$*» (expected pass)"
    fi
}

assertFails() {
    local rc=0
    "$@" > "$log" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
        cat "$log"
        fail "command passed: «$*» (expected fail)"
    fi
}
