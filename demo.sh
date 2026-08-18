#!/bin/sh
# See the failure and the repair.
cd "$(dirname "$0")"
. ./db.sh
run schema.sql

echo
echo "=============================================================="
echo " 1. ONE CONTRACT, VERSIONED.  Amended once, in the normal way."
echo "=============================================================="
echo "  $(val "SELECT broken.amend('$DOC', 4300.00, 'discount agreed')")"
q "SELECT version, supersedes, amount, note FROM broken.revisions ORDER BY version"
echo "  A clean line: version 2 corrects version 1. This is what everyone tests."

run schema.sql
echo
echo "=============================================================="
echo " 2. TWO PEOPLE AMEND IT AT THE SAME TIME"
echo "=============================================================="
concurrent_amendments broken
echo
q "SELECT version, supersedes, amount, note FROM broken.revisions ORDER BY version, id"
echo "  Two version 2s. Both correct version 1. The history has forked."
echo
echo "  What the screen shows:"
q "SELECT version, amount, note FROM broken.current"
echo "  One number. The other amendment is in the table, it is current too,"
echo "  and nothing on any screen will ever mention it."
echo
echo "  Rows at the highest version: $(val "SELECT count(*) FROM broken.revisions WHERE version = (SELECT max(version) FROM broken.revisions)")"

echo
echo "=============================================================="
echo " 3. THE SAME TWO PEOPLE, ON THE TABLE THAT HAS A SHAPE"
echo "=============================================================="
concurrent_amendments safe
echo
q "SELECT version, supersedes, amount, note FROM safe.revisions ORDER BY version, id"
echo "  One line. The amendment that lost was refused, wrote nothing, and"
echo "  was told to re-read the document — not silently filed alongside."

echo
echo "=============================================================="
echo " 4. THE OTHER WAY A HISTORY BREAKS:  two beginnings"
echo "=============================================================="
echo "  An import runs twice, or a retry creates the document again."
q "INSERT INTO broken.revisions (doc_id, version, supersedes, amount, note)
   VALUES ('$DOC', 1, NULL, 9999.00, 'imported again')"
echo "  broken: accepted. Rows claiming to be version 1: $(val "SELECT count(*) FROM broken.revisions WHERE version = 1")"
echo
echo "  safe:   $(val "SELECT safe.try_second_root('$DOC', 9999.00)")"
echo
