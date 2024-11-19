-- We create two sets of source and target tables, one set in Postgres and
-- the other in Citus distributed. We run the _exact_ MERGE SQL on both sets
-- and compare the final results of the target tables in Postgres and Citus.
-- The results should match. This process is repeated for various combinations
-- of MERGE SQL.

DROP SCHEMA IF EXISTS merge_repartition2_schema CASCADE;
CREATE SCHEMA merge_repartition2_schema;
SET search_path TO merge_repartition2_schema;
SET citus.shard_count TO 4;
SET citus.next_shard_id TO 6000000;
SET citus.explain_all_tasks TO true;
SET citus.shard_replication_factor TO 1;
SET citus.max_adaptive_executor_pool_size TO 1;
SET client_min_messages = warning;
SELECT 1 FROM master_add_node('localhost', :master_port, groupid => 0);
RESET client_min_messages;


CREATE TABLE pg_target(id int, val int);
CREATE TABLE pg_source(id int, val int, const int);
CREATE TABLE citus_target(id int, val int);
CREATE TABLE citus_source(id int, val int, const int);
SELECT citus_add_local_table_to_metadata('citus_target');
SELECT citus_add_local_table_to_metadata('citus_source');

CREATE OR REPLACE FUNCTION cleanup_data() RETURNS VOID SET search_path TO merge_repartition2_schema AS $$
    TRUNCATE pg_target;
    TRUNCATE pg_source;
    TRUNCATE citus_target;
    TRUNCATE citus_source;
    SELECT undistribute_table('citus_target');
    SELECT undistribute_table('citus_source');
$$
LANGUAGE SQL;
--
-- Load same set of data to both Postgres and Citus tables
--
CREATE OR REPLACE FUNCTION setup_data() RETURNS VOID SET search_path TO merge_repartition2_schema AS $$
    INSERT INTO pg_source SELECT i, i+1, 1 FROM generate_series(1, 100000) i;
    INSERT INTO pg_target SELECT i, 1 FROM generate_series(50001, 100000) i;
    INSERT INTO citus_source SELECT i, i+1, 1 FROM generate_series(1, 100000) i;
    INSERT INTO citus_target SELECT i, 1 FROM generate_series(50001, 100000) i;
$$
LANGUAGE SQL;

--
-- Compares the final target tables, merge-modified data, of both Postgres and Citus tables
--
CREATE OR REPLACE FUNCTION check_data(table1_name text, column1_name text, table2_name text, column2_name text)
RETURNS VOID SET search_path TO merge_repartition2_schema AS $$
DECLARE
    table1_avg numeric;
    table2_avg numeric;
BEGIN
    EXECUTE format('SELECT COALESCE(AVG(%I), 0) FROM %I', column1_name, table1_name) INTO table1_avg;
    EXECUTE format('SELECT COALESCE(AVG(%I), 0) FROM %I', column2_name, table2_name) INTO table2_avg;

    IF table1_avg > table2_avg THEN
        RAISE EXCEPTION 'The average of %.% is greater than %.%', table1_name, column1_name, table2_name, column2_name;
    ELSIF table1_avg < table2_avg THEN
        RAISE EXCEPTION 'The average of %.% is less than %.%', table1_name, column1_name, table2_name, column2_name;
    ELSE
        RAISE NOTICE 'The average of %.% is equal to %.%', table1_name, column1_name, table2_name, column2_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION compare_data() RETURNS VOID SET search_path TO merge_repartition2_schema AS $$
    SELECT check_data('pg_target', 'id', 'citus_target', 'id');
    SELECT check_data('pg_target', 'val', 'citus_target', 'val');
$$
LANGUAGE SQL;

-- Test nested cte
SELECT cleanup_data();
SELECT setup_data();
SELECT create_distributed_table('citus_target', 'id');
SELECT create_distributed_table('citus_source', 'id', colocate_with=>'none');

WITH cte_top AS(WITH cte_1 AS (WITH cte_2 AS (SELECT id, val FROM pg_source) SELECT * FROM cte_2) SELECT * FROM cte_1)
MERGE INTO pg_target t
USING (SELECT const, val, id FROM pg_source WHERE id IN (SELECT id FROM cte_top)) as s
ON (s.id = t.id)
WHEN MATCHED AND t.id <= 75000 THEN
	UPDATE SET val = (s.val::int8+1)
WHEN MATCHED THEN
	DELETE
WHEN NOT MATCHED THEN
	INSERT VALUES (s.id, s.val);

WITH cte_top AS(WITH cte_1 AS (WITH cte_2 AS (SELECT id, val FROM citus_source) SELECT * FROM cte_2) SELECT * FROM cte_1)
MERGE INTO citus_target t
USING (SELECT const, val, id FROM citus_source WHERE id IN (SELECT id FROM cte_top)) as s
ON (s.id = t.id)
WHEN MATCHED AND t.id <= 75000 THEN
	UPDATE SET val = (s.val::int8+1)
WHEN MATCHED THEN
	DELETE
WHEN NOT MATCHED THEN
	INSERT VALUES (s.id, s.val);

SELECT compare_data();

-- Test aggregate function in source query

MERGE INTO pg_target t
USING (SELECT count(id+1)::text as value, val as key FROM pg_source group by key) s
ON t.id = s.key
WHEN MATCHED AND t.id <= 75000 THEN
        UPDATE SET val = (s.value::int8+1)
WHEN MATCHED THEN
        DELETE
WHEN NOT MATCHED THEN
        INSERT VALUES(s.key, value::int4+10);

MERGE INTO citus_target t
USING (SELECT count(id+1)::text as value, val as key FROM citus_source group by key) s
ON t.id = s.key
WHEN MATCHED AND t.id <= 75000 THEN
        UPDATE SET val = (s.value::int8+1)
WHEN MATCHED THEN
        DELETE
WHEN NOT MATCHED THEN
        INSERT VALUES(s.key, value::int4+10);

SELECT compare_data();

DROP SCHEMA merge_repartition2_schema CASCADE;

