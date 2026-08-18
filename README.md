# Your version history has two version 2s, and every screen shows one of them.

A contract is agreed at 4800.00. Sales applies a penalty clause; Legal applies a discount.
They submit within half a second of each other. Both read version 1, both write version 2,
and the document now has two current versions that disagree about the amount.

The screen shows 4300.00. The other amendment is in the table, it is equally current, and
nothing anywhere will ever mention it.

**This is a synthetic demonstration of a general data-integrity failure class**, not anyone's
production system and not a copy of one. Made-up contract, made-up amounts, one throwaway
database.

## Run it

```sh
./demo.sh                  # the fork, and the table that cannot hold one
./test.sh                  # the rule, asserted — 7 of 7 pass
./test.sh --no-constraints # the same code without the four rules — 4 assertions fail
```

Needs a Postgres. The scripts use a local one if they find it, honour `DATABASE_URL` if you
set one, and otherwise start one in Docker (`docker-compose.yml` included). About three
seconds, most of it the deliberate delay that makes the race reproducible.

## What you just saw

**Amended one at a time**, the ordinary handler is correct: read the head, write head + 1, a
clean line. The suite asserts that, because the code is not a strawman.

**Amended at the same time**, both writers read version 1 before either wrote version 2. No
error, no conflict, no constraint to violate. `ORDER BY version DESC LIMIT 1` returns one of
the two, consistently enough that nobody notices.

**A second beginning** is the other half. An import re-runs, a retry fires, and the document
now has two version 1s — two chains under one id, and which one you read is a matter of luck.

## The repair

Four rules, in [`schema.sql`](schema.sql):

```sql
CONSTRAINT one_row_per_version UNIQUE (doc_id, version),
CONSTRAINT no_branching        UNIQUE (doc_id, supersedes),
CONSTRAINT chain_is_linear     CHECK ((version = 1 AND supersedes IS NULL)
                                   OR (version > 1 AND supersedes = version - 1)),
CREATE UNIQUE INDEX one_root_per_doc ON safe.revisions (doc_id) WHERE supersedes IS NULL;
```

`no_branching` is what stops the race: two amendments that both correct version 1 are the
same row twice, and the second one loses. It is refused, it writes nothing, and it is told
the document moved — so the caller re-reads and applies its change to the real head, which
is what a person would have done had they known.

## Why not an `is_current` flag

Because moving the flag is an `UPDATE`, and it has the same race unless you also hold a
partial unique index on it — at which point the flag is doing nothing the index is not. On an
append-only table there is no `UPDATE` to be had at all
([why](https://github.com/abdulwahed-sweden/append-only-demo)), so the flag design is not
merely worse there, it is unavailable.

So the invariant is anchored at the **root** instead of the head: exactly one row per document
with no predecessor. One root, plus no branching, plus a linear chain, means the head is
unique too — and every one of those is checked at `INSERT`, without ever mutating a row.

That is the whole trick, and it is the part that is hard to arrive at while the flag still
looks like it works.

## The assertions

Seven, and two of them assert the *failure*: two concurrent amendments must fork the ordinary
table, and the screen must show exactly one of the two. If that stops reproducing, this demo
is lying about the problem.

> A document has one beginning, one line of corrections, and one current version.

`./test.sh --no-constraints` drops the four rules and changes nothing else. Four assertions
fail immediately, including the one that says the losing amendment wrote nothing.

## Scope

Synthetic data, plain SQL, no application framework. The stack changes; the shape does not —
document revisions, order status history, price versions, consent records, audit trails,
anything with a `version` column and a screen that reads the latest one.

I have built this properly in a production system on Rust and PostgreSQL, where corrections
and withdrawals had to be provable years later and the table could not be updated in place at
all. That system is private and none of its code appears here. This repository is an
independent reconstruction of the failure.

---

If two people can edit the same record at once, it is worth checking whether your history can
hold two answers at the same time.
**Abdulwahed Mansour** · abdulwahed.sweden@gmail.com

All five reproductions in one place: https://github.com/abdulwahed-sweden
