-- Drop the four rules and change nothing else: same columns, same handler,
-- same application code.
--
-- Run the suite against this and the assertions about shape fail. That is
-- what tells you where the rule actually lives.
ALTER TABLE safe.revisions DROP CONSTRAINT one_row_per_version;
ALTER TABLE safe.revisions DROP CONSTRAINT no_branching;
ALTER TABLE safe.revisions DROP CONSTRAINT chain_is_linear;
DROP INDEX safe.one_root_per_doc;
