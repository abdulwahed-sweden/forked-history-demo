# Find a Postgres to run against. Sourced by demo.sh and test.sh.
#
#   1. $DATABASE_URL, if you set one
#   2. a Postgres already running on this machine
#   3. Docker
#
# The demo creates a database called forked_history_demo and drops nothing else.

set -eu
DB_NAME=forked_history_demo
DOC="22222222-2222-2222-2222-222222222222"

if [ -n "${DATABASE_URL:-}" ]; then
    DB="$DATABASE_URL"
elif pg_isready -q 2>/dev/null; then
    psql -X -q -d postgres -c "CREATE DATABASE $DB_NAME" >/dev/null 2>&1 || true
    DB="postgres:///$DB_NAME"
elif docker info >/dev/null 2>&1; then
    echo "Starting Postgres in Docker (first run pulls the image)..."
    docker compose up -d --wait >/dev/null
    DB="postgres://postgres:demo@localhost:55436/postgres"
else
    echo "This demo needs Postgres. Any one of these works:"
    echo "  - a local Postgres running          (brew services start postgresql, etc.)"
    echo "  - Docker running, then re-run this  (docker compose is included)"
    echo "  - DATABASE_URL=postgres://... $0"
    exit 1
fi

run() { psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f "$1"; }
q()   { psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -c "$1"; }
val() { psql -X -q -t -A -v ON_ERROR_STOP=1 -d "$DB" -c "$1"; }

# Two people amend the same document at the same time. Sales is held for a
# second between reading the head and writing; Legal starts 0.4s later and
# gets there first. In production this gap is a form being submitted.
concurrent_amendments() {   # $1 = broken | safe
    val "SELECT $1.amend('$DOC', 500.00, 'penalty clause applied', 1)" \
        | sed 's/^/  Sales (started first, slower) : /' &
    sleep 0.4
    val "SELECT $1.amend('$DOC', 4300.00, 'discount agreed', 0)" \
        | sed 's/^/  Legal (started later, faster) : /'
    wait
}
