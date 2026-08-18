#!/bin/sh
# The rule, asserted.
#   ./test.sh                 the repair — 7 of 7 pass
#   ./test.sh --no-constraints  the same code without the four rules — 4 fail
cd "$(dirname "$0")"
. ./db.sh

GUARD=1
[ "${1:-}" = "--no-constraints" ] && { GUARD=0; echo "--- running WITHOUT the four rules ---"; }

FAILED=0
check() {   # actual expected label
    if [ "$1" = "$2" ]; then echo "PASS  $3"
    else echo "FAIL  $3  (expected $2, got $1)"; FAILED=1; fi
}

# Every reset must re-apply --no-constraints, or the suite quietly restores
# the rules it is supposed to be running without.
reset() {
    run schema.sql
    [ "$GUARD" = 0 ] && run no-constraints.sql
    return 0
}

heads() {   # rows sitting at the highest version — should always be 1
    val "SELECT count(*) FROM $1.revisions WHERE version = (SELECT max(version) FROM $1.revisions)"
}

# 1 --------------------------------------------------------------------
# The ordinary handler is not a strawman: amended one at a time, it builds
# a clean line.
reset
val "SELECT broken.amend('$DOC', 4300.00, 'discount agreed')" >/dev/null
val "SELECT broken.amend('$DOC', 4100.00, 'second discount')" >/dev/null
check "$(val "SELECT string_agg(version::text, ',' ORDER BY version) FROM broken.revisions")" "1,2,3" \
      "amended one at a time, the ordinary handler builds a clean line"

# 2 --------------------------------------------------------------------
# The failure, asserted. If this stops reproducing, the demo is lying.
reset
concurrent_amendments broken >/dev/null
check "$(heads broken)" "2" "two concurrent amendments fork the history into two version 2s"

# 3 --------------------------------------------------------------------
check "$(val "SELECT count(*) FROM broken.current")" "1" \
      "and the screen shows exactly one of them, with nothing to say the other exists"

# 4 --------------------------------------------------------------------
reset
concurrent_amendments safe >/dev/null
check "$(heads safe)" "1" "the same two amendments leave exactly one current version"

# 5 --------------------------------------------------------------------
check "$(val "SELECT count(*) FROM safe.revisions")" "2" \
      "the amendment that lost wrote nothing at all"

# 6 --------------------------------------------------------------------
check "$(val "SELECT safe.try_second_root('$DOC', 9999.00)")" "refused by the one-root index" \
      "a second beginning for the same document is refused"

# 7 --------------------------------------------------------------------
check "$(val "SELECT (SELECT count(*) FROM safe.revisions WHERE version > 1 AND supersedes <> version - 1)
                   + (SELECT count(*) FROM (SELECT doc_id, supersedes FROM safe.revisions
                        WHERE supersedes IS NOT NULL GROUP BY 1,2 HAVING count(*) > 1) forks)")" "0" \
      "the chain is a single line: every version corrects exactly the one before it"

echo
[ "$FAILED" = 0 ] && echo "7 of 7 assertions passed." || echo "FAILURES above."
exit $FAILED
