

SHOW server_version \gset
SELECT CASE
           WHEN substring(current_setting('server_version'), '\d+')::int >= 17 THEN '17+'
           WHEN substring(current_setting('server_version'), '\d+')::int IN (15, 16) THEN '15_16'
           WHEN substring(current_setting('server_version'), '\d+')::int = 14 THEN '14'
           ELSE 'Unsupported version'
       END AS version_category;
SELECT substring(:'server_version', '\d+')::int >= 15 AS server_version_ge_15
\gset
\if :server_version_ge_15
\else
\q
\endif

--
-- MERGE test from PG community (adapted to Citus by converting all tables to Citus local)
--
DROP SCHEMA IF EXISTS pgmerge_schema CASCADE;
CREATE SCHEMA pgmerge_schema;
SET search_path TO pgmerge_schema;

SET citus.use_citus_managed_tables to true;

CREATE TABLE target (tid integer, balance integer)
  WITH (autovacuum_enabled=off);
CREATE TABLE source (sid integer, delta integer) -- no index
  WITH (autovacuum_enabled=off);

\set SHOW_CONTEXT errors
-- used in a CTE
WITH foo AS (
  MERGE INTO target USING source ON (true)
  WHEN MATCHED THEN DELETE
) SELECT * FROM foo;
-- used in COPY
COPY (
  MERGE INTO target USING source ON (true)
  WHEN MATCHED THEN DELETE
) TO stdout;
-- used in a CTE with RETURNING
WITH foo AS (
  MERGE INTO target USING source ON (true)
  WHEN MATCHED THEN DELETE RETURNING target.*
) SELECT * FROM foo;
-- used in COPY with RETURNING
COPY (
  MERGE INTO target USING source ON (true)
  WHEN MATCHED THEN DELETE RETURNING target.*
) TO stdout;

-- unsupported relation types
-- view
CREATE VIEW tv AS SELECT count(tid) AS tid FROM target;
MERGE INTO tv t
USING source s
ON t.tid = s.sid
WHEN NOT MATCHED THEN
	INSERT DEFAULT VALUES;
DROP VIEW tv;

CREATE TABLE sq_target (tid integer NOT NULL, balance integer)
  WITH (autovacuum_enabled=off);
CREATE TABLE sq_source (delta integer, sid integer, balance integer DEFAULT 0)
  WITH (autovacuum_enabled=off);

SELECT citus_add_local_table_to_metadata('sq_target');
SELECT citus_add_local_table_to_metadata('sq_source');

INSERT INTO sq_target(tid, balance) VALUES (1,100), (2,200), (3,300);
INSERT INTO sq_source(sid, delta) VALUES (1,10), (2,20), (4,40);

CREATE VIEW v AS SELECT * FROM sq_source WHERE sid < 2;

-- RETURNING
BEGIN;
INSERT INTO sq_source (sid, balance, delta) VALUES (-1, -1, -10);
MERGE INTO sq_target t
USING v
ON tid = sid
WHEN MATCHED AND tid > 2 THEN
    UPDATE SET balance = t.balance + delta
WHEN NOT MATCHED THEN
        INSERT (balance, tid) VALUES (balance + delta, sid)
WHEN MATCHED AND tid < 2 THEN
        DELETE
RETURNING *;
ROLLBACK;
