-- removing coordinator from pg_dist_node should update pg_dist_colocation
SELECT master_remove_node('localhost', :master_port);

-- to silence -potentially flaky- "could not establish connection after" warnings in below test
SET client_min_messages TO ERROR;

-- to fail fast if the hostname is not resolvable
SET citus.node_connection_timeout to '1s';

BEGIN;
  SET application_name TO 'new_app_name';

  -- that should fail because of bad hostname & port
  SELECT citus_add_node('200.200.200.200', 1, 200);

  -- Since above command failed, now Postgres will need to revert the
  -- application_name change made in this transaction and this will
  -- happen within abort-transaction callback, so we won't be in a
  -- transaction block while Postgres does that.
  --
  -- And when the application_name changes, Citus tries to re-assign
  -- the global pid and doing so for Citus internal backends doesn't
  -- require being in a transaction block and is safe.
  --
  -- However, for the client external backends (like us here), Citus
  -- doesn't try to re-assign the global pid if doing so requires catalog
  -- access and we're outside of a transaction block. Note that in that
  -- case the catalog access may only be needed to retrive the local node
  -- id when the cached local node is invalidated like what just happened
  -- here because of the failed citus_add_node() call made above.
  --
  -- So by failing here (rather than crashing), we ensure this behavior.
ROLLBACK;

RESET client_min_messages;
RESET citus.node_connection_timeout;

-- restore coordinator for the rest of the tests
SELECT citus_set_coordinator_host('localhost', :master_port);
