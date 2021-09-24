SHOW server_version \gset
SELECT substring(:'server_version', '\d+')::int > 11 AS server_version_above_eleven
\gset
\if :server_version_above_eleven
\else
\q
\endif

CREATE SCHEMA upgrade_columnar;
CREATE TABLE less_common_data_types_table
(
	dist_key bigint PRIMARY KEY
) USING COLUMNAR;
