CREATE SCHEMA generated_identities;
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

SELECT 1 from citus_add_node('localhost', :master_port, groupId=>0);

-- smallint identity column can not be distributed
CREATE TABLE smallint_identity_column (
    a smallint GENERATED BY DEFAULT AS IDENTITY
);
SELECT create_distributed_table('smallint_identity_column', 'a');
SELECT create_reference_table('smallint_identity_column');
SELECT citus_add_local_table_to_metadata('smallint_identity_column');

DROP TABLE smallint_identity_column;

-- int identity column can not be distributed
CREATE TABLE int_identity_column (
    a int GENERATED BY DEFAULT AS IDENTITY
);
SELECT create_distributed_table('int_identity_column', 'a');
SELECT create_reference_table('int_identity_column');
SELECT citus_add_local_table_to_metadata('int_identity_column');
DROP TABLE int_identity_column;

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

INSERT INTO partitioned_table (a,b,c) VALUES (997,997,997);

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

-- https://github.com/citusdata/citus/issues/6694
CREATE TABLE color (
    color_id BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE,
    color_name VARCHAR NOT NULL
);
SELECT create_distributed_table('color', 'color_id');

CREATE USER identity_test_user;
GRANT INSERT ON color TO identity_test_user;
GRANT USAGE ON SCHEMA generated_identities TO identity_test_user;

\c - identity_test_user - :worker_1_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

INSERT INTO color(color_name) VALUES ('Blue');

\c - postgres - :master_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

DROP SCHEMA generated_identities CASCADE;
DROP USER identity_test_user;
