-- citus--12.1-1--12.0-1


DROP FUNCTION pg_catalog.citus_pause_node_within_txn(int,bool,int);


-- we have modified the relevant upgrade script to include any_value changes
-- we don't need to upgrade this downgrade path for any_value changes
-- since if we are doing a Citus downgrade, not PG downgrade, then it would be no-op.

