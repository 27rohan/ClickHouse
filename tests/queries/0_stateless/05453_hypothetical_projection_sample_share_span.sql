-- the sampled granules are read exactly, so the sampling error covers only the granules out of the sample
-- with half the granules in the sample the span is narrower than for a sample of a small share
-- the twin table has the projection materialized and shows the read that the optimizer selects

SET optimize_use_projections = 1, optimize_use_implicit_projections = 0, prefer_optimize_projection = 0, force_optimize_projection = 0,
    enable_parallel_replicas = 0;

CREATE TABLE t_est (a UInt64, b UInt64) ENGINE = MergeTree ORDER BY a
    SETTINGS index_granularity = 100, index_granularity_bytes = '10Mi', min_bytes_for_wide_part = 0, min_rows_for_wide_part = 0,
        ratio_of_defaults_for_sparse_serialization = 1, auto_statistics_types = '';
CREATE TABLE t_real AS t_est;
ALTER TABLE t_real ADD PROJECTION p (SELECT a, b ORDER BY b);
INSERT INTO t_est SELECT number, cityHash64(number) % 10000 FROM numbers(30000);
INSERT INTO t_real SELECT number, cityHash64(number) % 10000 FROM numbers(30000);
OPTIMIZE TABLE t_est FINAL;
OPTIMIZE TABLE t_real FINAL;
CREATE HYPOTHETICAL PROJECTION p ON t_est (SELECT a, b ORDER BY b);

-- 300 granules: a budget of 15000 rows reads one granule of every 2
SELECT replaceRegexpAll(trim(explain), '\\s+', ' ') AS line
FROM (EXPLAIN WHATIF projection_scan_budget_rows = 15000 SELECT a, b FROM t_est WHERE b < 3000)
WHERE match(line, '^(With |marks:|marks_span|sampled_marks)');
SELECT 'real: ' || toString(marks) || ' marks' FROM (EXPLAIN ESTIMATE SELECT a, b FROM t_real WHERE b < 3000);

DROP TABLE t_est;
DROP TABLE t_real;
