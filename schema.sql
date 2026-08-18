-- One versioned document, stored two ways.
--
--   broken.*  versions and a supersedes pointer, and nothing enforcing
--             that they form a single line.
--   safe.*    the same columns, plus the constraints that make a fork
--             impossible to write.
--
-- Re-running this file resets both.

SET client_min_messages TO warning;

DROP SCHEMA IF EXISTS broken CASCADE;
DROP SCHEMA IF EXISTS safe   CASCADE;

CREATE SCHEMA broken;
CREATE SCHEMA safe;

-- ---- The ordinary versioned table ------------------------------------

CREATE TABLE broken.revisions (
    id          BIGSERIAL PRIMARY KEY,
    doc_id      UUID NOT NULL,
    version     BIGINT NOT NULL,
    -- The version this one corrects. NULL for the first.
    supersedes  BIGINT,
    amount      NUMERIC(12,2) NOT NULL,
    note        TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Read the head, write head + 1. Every versioned table starts here, and
-- it is correct until two of these run at once.
CREATE FUNCTION broken.amend(p_doc UUID, p_amount NUMERIC, p_note TEXT, p_delay NUMERIC DEFAULT 0)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE head_version BIGINT;
BEGIN
    SELECT version INTO head_version
    FROM broken.revisions WHERE doc_id = p_doc ORDER BY version DESC LIMIT 1;

    PERFORM pg_sleep(p_delay);

    INSERT INTO broken.revisions (doc_id, version, supersedes, amount, note)
    VALUES (p_doc, head_version + 1, head_version, p_amount, p_note);

    RETURN 'wrote version ' || (head_version + 1);
END
$$;

-- ---- The same table, with the shape enforced --------------------------

CREATE TABLE safe.revisions (
    id          BIGSERIAL PRIMARY KEY,
    doc_id      UUID NOT NULL,
    version     BIGINT NOT NULL,
    supersedes  BIGINT,
    amount      NUMERIC(12,2) NOT NULL,
    note        TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- No two versions of a document share a number.
    CONSTRAINT one_row_per_version UNIQUE (doc_id, version),
    -- No two versions correct the same predecessor. This is the one that
    -- stops a fork at the head.
    CONSTRAINT no_branching UNIQUE (doc_id, supersedes),
    CONSTRAINT version_positive CHECK (version >= 1),
    -- Version 1 has no predecessor; every later version corrects exactly
    -- the one before it. With the two uniques above, the chain is a
    -- strict line.
    CONSTRAINT chain_is_linear CHECK (
        (version = 1 AND supersedes IS NULL)
        OR (version > 1 AND supersedes = version - 1)
    )
);

-- Exactly one start per document.
--
-- Note where this is anchored: at the ROOT, not at the head. The obvious
-- design is an `is_current` flag with a partial unique index on it — but
-- moving that flag is an UPDATE, and on an append-only table there is no
-- UPDATE to be had. Anchoring at the root needs no mutation: one root,
-- plus no branching, plus a linear chain, means the head is unique too.
CREATE UNIQUE INDEX one_root_per_doc
    ON safe.revisions (doc_id) WHERE supersedes IS NULL;

CREATE FUNCTION safe.amend(p_doc UUID, p_amount NUMERIC, p_note TEXT, p_delay NUMERIC DEFAULT 0)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE head_version BIGINT;
BEGIN
    SELECT version INTO head_version
    FROM safe.revisions WHERE doc_id = p_doc ORDER BY version DESC LIMIT 1;

    PERFORM pg_sleep(p_delay);

    INSERT INTO safe.revisions (doc_id, version, supersedes, amount, note)
    VALUES (p_doc, head_version + 1, head_version, p_amount, p_note);

    RETURN 'wrote version ' || (head_version + 1);
EXCEPTION WHEN unique_violation THEN
    -- Someone amended this document while we were working. Nothing was
    -- written, and the caller knows to re-read and try again.
    RETURN 'refused: the document moved while this amendment was being made';
END
$$;

-- Attempt a second beginning for a document that already has one, and
-- report what the table said. Used by the demo and the suite so the answer
-- is always a real one.
CREATE FUNCTION safe.try_second_root(p_doc UUID, p_amount NUMERIC)
RETURNS TEXT LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO safe.revisions (doc_id, version, supersedes, amount, note)
    VALUES (p_doc, 1, NULL, p_amount, 'imported again');
    RETURN 'accepted — the document now has two beginnings';
EXCEPTION WHEN unique_violation THEN
    RETURN 'refused by the one-root index';
END
$$;

-- ---- What the screen reads -------------------------------------------

CREATE VIEW broken.current AS
SELECT DISTINCT ON (doc_id) * FROM broken.revisions ORDER BY doc_id, version DESC;

CREATE VIEW safe.current AS
SELECT DISTINCT ON (doc_id) * FROM safe.revisions ORDER BY doc_id, version DESC;

-- One contract, agreed at 4800.00.
INSERT INTO broken.revisions (doc_id, version, supersedes, amount, note)
VALUES ('22222222-2222-2222-2222-222222222222', 1, NULL, 4800.00, 'signed');
INSERT INTO safe.revisions (doc_id, version, supersedes, amount, note)
VALUES ('22222222-2222-2222-2222-222222222222', 1, NULL, 4800.00, 'signed');
