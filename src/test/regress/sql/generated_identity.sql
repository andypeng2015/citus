CREATE SCHEMA generated_identities;
SET search_path TO generated_identities;
SET client_min_messages to ERROR;
SET citus.shard_replication_factor TO 1;

SELECT 1 from citus_add_node('localhost', :master_port, groupId=>0);

CREATE TABLE smallint_identity_column (
    a smallint GENERATED BY DEFAULT AS IDENTITY
);

CREATE VIEW verify_smallint_identity_column AS
SELECT attidentity, attgenerated FROM pg_attribute WHERE attrelid = 'smallint_identity_column'::regclass AND attname = 'a';

BEGIN;
    SELECT create_distributed_table('smallint_identity_column', 'a');
    SELECT * FROM verify_smallint_identity_column;
ROLLBACK;

BEGIN;
    SELECT create_reference_table('smallint_identity_column');
    SELECT * FROM verify_smallint_identity_column;
ROLLBACK;

BEGIN;
    SELECT citus_add_local_table_to_metadata('smallint_identity_column');
    SELECT * FROM verify_smallint_identity_column;
ROLLBACK;

SELECT create_distributed_table_concurrently('smallint_identity_column', 'a');
SELECT * FROM verify_smallint_identity_column;
SELECT result FROM run_command_on_workers('INSERT INTO generated_identities.smallint_identity_column (a) VALUES (DEFAULT);');

DROP TABLE smallint_identity_column CASCADE;

CREATE TABLE int_identity_column (
    a int GENERATED BY DEFAULT AS IDENTITY
);

CREATE VIEW verify_int_identity_column AS
SELECT attidentity, attgenerated FROM pg_attribute WHERE attrelid = 'int_identity_column'::regclass AND attname = 'a';

BEGIN;
    SELECT create_distributed_table('int_identity_column', 'a');
    SELECT * FROM verify_int_identity_column;
ROLLBACK;

BEGIN;
    SELECT create_reference_table('int_identity_column');
    SELECT * FROM verify_int_identity_column;
ROLLBACK;

BEGIN;
    SELECT citus_add_local_table_to_metadata('int_identity_column');
    SELECT * FROM verify_int_identity_column;
ROLLBACK;

SELECT create_distributed_table_concurrently('int_identity_column', 'a');
SELECT * FROM verify_int_identity_column;
SELECT result FROM run_command_on_workers('INSERT INTO generated_identities.int_identity_column (a) VALUES (DEFAULT);');

DROP TABLE int_identity_column CASCADE;

CREATE TABLE reference_int_identity_column (
    a int GENERATED BY DEFAULT AS IDENTITY
);
SELECT create_reference_table('reference_int_identity_column');
INSERT INTO generated_identities.reference_int_identity_column (a) VALUES (DEFAULT) RETURNING a;
SELECT result FROM run_command_on_workers('INSERT INTO generated_identities.reference_int_identity_column (a) VALUES (DEFAULT);');

CREATE TABLE citus_local_int_identity_column (
    a int GENERATED BY DEFAULT AS IDENTITY
);
SELECT citus_add_local_table_to_metadata('citus_local_int_identity_column');
INSERT INTO generated_identities.citus_local_int_identity_column (a) VALUES (DEFAULT) RETURNING a;
SELECT result FROM run_command_on_workers('INSERT INTO generated_identities.citus_local_int_identity_column (a) VALUES (DEFAULT);');

DROP TABLE reference_int_identity_column, citus_local_int_identity_column;

RESET citus.shard_replication_factor;


CREATE TABLE bigint_identity_column (
    a bigint GENERATED BY DEFAULT AS IDENTITY,
    b int
);
SELECT citus_add_local_table_to_metadata('bigint_identity_column');
DROP TABLE bigint_identity_column;

CREATE TABLE bigint_identity_column (
    a bigint GENERATED BY DEFAULT AS IDENTITY,
    b int
);
SELECT create_distributed_table('bigint_identity_column', 'a');

\d bigint_identity_column

\c - - - :worker_1_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

INSERT INTO bigint_identity_column (b)
SELECT s FROM generate_series(1,10) s;

\d generated_identities.bigint_identity_column

\c - - - :master_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

INSERT INTO bigint_identity_column (b)
SELECT s FROM generate_series(11,20) s;

SELECT * FROM bigint_identity_column ORDER BY B ASC;

-- table with identity column cannot be altered.
SELECT alter_distributed_table('bigint_identity_column', 'b');

-- table with identity column cannot be undistributed.
SELECT undistribute_table('bigint_identity_column');

DROP TABLE bigint_identity_column;

-- create a partitioned table for testing.
CREATE TABLE partitioned_table (
    a bigint CONSTRAINT myconname GENERATED BY DEFAULT AS IDENTITY (START WITH 10 INCREMENT BY 10),
    b bigint GENERATED ALWAYS AS IDENTITY (START WITH 10 INCREMENT BY 10),
    c int
)
PARTITION BY RANGE (c);
CREATE TABLE partitioned_table_1_50 PARTITION OF partitioned_table FOR VALUES FROM (1) TO (50);
CREATE TABLE partitioned_table_50_500 PARTITION OF partitioned_table FOR VALUES FROM (50) TO (1000);

SELECT create_distributed_table('partitioned_table', 'a');

\d partitioned_table

\c - - - :worker_1_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

\d generated_identities.partitioned_table

insert into partitioned_table (c) values (1);

insert into partitioned_table (c) SELECT 2;

INSERT INTO partitioned_table (c)
SELECT s FROM generate_series(3,7) s;

\c - - - :master_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

INSERT INTO partitioned_table (c)
SELECT s FROM generate_series(10,20) s;

INSERT INTO partitioned_table (a,c) VALUES (998,998);

INSERT INTO partitioned_table (a,b,c) OVERRIDING SYSTEM VALUE VALUES (999,999,999);

SELECT * FROM partitioned_table ORDER BY c ASC;

-- alter table .. alter column .. add is unsupported
ALTER TABLE partitioned_table ALTER COLUMN g ADD GENERATED ALWAYS AS IDENTITY;

-- alter table .. alter column is unsupported
ALTER TABLE partitioned_table ALTER COLUMN b TYPE int;

DROP TABLE partitioned_table;

-- create a table for reference table testing.
CREATE TABLE reference_table (
    a bigint CONSTRAINT myconname GENERATED BY DEFAULT AS IDENTITY (START WITH 10 INCREMENT BY 10),
    b bigint GENERATED ALWAYS AS IDENTITY (START WITH 10 INCREMENT BY 10) UNIQUE,
    c int
);

SELECT create_reference_table('reference_table');

\d reference_table

\c - - - :worker_1_port
SET search_path TO generated_identities;

\d generated_identities.reference_table

INSERT INTO reference_table (c)
SELECT s FROM generate_series(1,10) s;

--on master
select * from reference_table;

\c - - - :master_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

INSERT INTO reference_table (c)
SELECT s FROM generate_series(11,20) s;

SELECT * FROM reference_table ORDER BY c ASC;

DROP TABLE reference_table;

CREATE TABLE color (
    color_id BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE,
    color_name VARCHAR NOT NULL
);

-- https://github.com/citusdata/citus/issues/6694
CREATE USER identity_test_user;
GRANT INSERT ON color TO identity_test_user;
GRANT USAGE ON SCHEMA generated_identities TO identity_test_user;

SET ROLE identity_test_user;
SELECT create_distributed_table('color', 'color_id');

SET ROLE postgres;
SET citus.shard_replication_factor TO 1;
SELECT create_distributed_table_concurrently('color', 'color_id');
RESET citus.shard_replication_factor;

\c - identity_test_user - :worker_1_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

INSERT INTO color(color_name) VALUES ('Blue');

\c - postgres - :master_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;
SET citus.next_shard_id TO 12400000;

DROP TABLE Color;
CREATE TABLE color (
    color_id BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE,
    color_name VARCHAR NOT NULL
) USING columnar;
SELECT create_distributed_table('color', 'color_id');
INSERT INTO color(color_name) VALUES ('Blue');
\d+ color

\c - - - :worker_1_port
SET search_path TO generated_identities;
\d+ color
INSERT INTO color(color_name) VALUES ('Red');
-- alter sequence .. restart
ALTER SEQUENCE color_color_id_seq RESTART WITH 1000;
-- override system value
INSERT INTO color(color_id, color_name) VALUES (1, 'Red');
INSERT INTO color(color_id, color_name) VALUES (NULL, 'Red');
INSERT INTO color(color_id, color_name) OVERRIDING SYSTEM VALUE VALUES (1, 'Red');
-- update null or custom value
UPDATE color SET color_id = NULL;
UPDATE color SET color_id = 1;

\c - postgres - :master_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;


-- alter table .. add column .. GENERATED .. AS IDENTITY
ALTER TABLE color ADD COLUMN color_id BIGINT GENERATED ALWAYS AS IDENTITY;

-- alter sequence .. restart
ALTER SEQUENCE color_color_id_seq RESTART WITH 1000;
-- override system value
INSERT INTO color(color_id, color_name) VALUES (1, 'Red');
INSERT INTO color(color_id, color_name) VALUES (NULL, 'Red');
INSERT INTO color(color_id, color_name) OVERRIDING SYSTEM VALUE VALUES (1, 'Red');
-- update null or custom value
UPDATE color SET color_id = NULL;
UPDATE color SET color_id = 1;

DROP TABLE IF EXISTS test;
CREATE TABLE test (x int, y int, z bigint generated by default as identity);
SELECT create_distributed_table('test', 'x', colocate_with := 'none');
INSERT INTO test VALUES (1,2);
INSERT INTO test SELECT x, y FROM test WHERE x = 1;
SELECT * FROM test;


-- Test for issue #7887 Fix insert select planner to exclude identity columns from target list on partial inserts
-- https://github.com/citusdata/citus/pull/7911
CREATE TABLE local1 (
    id text not null primary key
);

CREATE TABLE reference1 (
    id int not null primary key,
    reference_col1 text not null
);
SELECT create_reference_table('reference1');

CREATE TABLE local2 (
    id int not null generated always as identity,
    local1fk text not null,
    reference1fk int not null,
    constraint loc1fk foreign key (local1fk) references local1(id),
    constraint reference1fk foreign key (reference1fk) references reference1(id),
    constraint testlocpk primary key (id)
);

INSERT INTO local1(id) VALUES ('aaaaa'), ('bbbbb'), ('ccccc');
INSERT INTO reference1(id, reference_col1) VALUES (1, 'test'), (2, 'test2'), (3, 'test3');

--
-- Partial insert: omit the identity column
-- This triggers the known bug in older code paths if not fixed.
--
INSERT INTO local2(local1fk, reference1fk)
    SELECT id, 1
    FROM local1;

-- Check inserted rows in local2
SELECT * FROM local2;


-- We do a "INSERT INTO local2(id, local1fk, reference1fk) SELECT 9999, id, 2" which
-- should fail under normal PG rules if no OVERRIDING clause is used.

INSERT INTO local2(id, local1fk, reference1fk)
    SELECT 9999, id, 2 FROM local1 LIMIT 1;

-- Using OVERRIDING SYSTEM VALUE to override ALWAYS identity
INSERT INTO local2(id, local1fk, reference1fk)
    OVERRIDING SYSTEM VALUE
    SELECT 9999, id, 2 FROM local1 LIMIT 1;

-- Create a second table with BY DEFAULT identity to test different identity mode
CREATE TABLE local2_bydefault (
    id int NOT NULL GENERATED BY DEFAULT AS IDENTITY,
    local1fk text NOT NULL,
    reference1fk int NOT NULL,
    CONSTRAINT loc1fk_bd FOREIGN KEY (local1fk) REFERENCES local1(id),
    CONSTRAINT reference1fk_bd FOREIGN KEY (reference1fk) REFERENCES reference1(id),
    CONSTRAINT testlocpk_bd PRIMARY KEY (id)
);

INSERT INTO local1(id) VALUES ('xxxxx'), ('yyyyy'), ('ddddd'), ('zzzzz');

INSERT INTO local2_bydefault(local1fk, reference1fk)
    SELECT 'xxxxx', 1;

-- Show inserted row in local2_bydefault
SELECT * FROM local2_bydefault;

--
-- Overriding a BY DEFAULT identity with user value
-- (which is allowed even without OVERRIDING clause).
--
-- Provide explicit id for BY DEFAULT identity => no special OVERRIDING needed
INSERT INTO local2_bydefault(id, local1fk, reference1fk)
    VALUES (5000, 'yyyyy', 2);

-- Show rows (we expect id=5000 and one with auto-generated ID)
SELECT * FROM local2_bydefault ORDER BY id;

-- Insert referencing reference1fk=3 => partial insert on both tables
INSERT INTO local2(local1fk, reference1fk)
    VALUES ('ddddd', 3);

INSERT INTO local2_bydefault(local1fk, reference1fk)
    SELECT 'zzzzz', 3;

-- Show final state of local2 and local2_bydefault
SELECT 'local2' as table_name, * FROM local2
UNION ALL
SELECT 'local2_bydefault', * FROM local2_bydefault
ORDER BY table_name, id;

-- End of test for issue #7887

-- Cleanup
SET client_min_messages TO WARNING;
DROP SCHEMA generated_identities CASCADE;
DROP USER identity_test_user;
