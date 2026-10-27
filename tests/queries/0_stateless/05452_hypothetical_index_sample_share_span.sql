-- the sampled windows are exact, so the sampling error covers only the windows out of the sample
-- with half the windows in the sample the span is narrower than for a sample of a small share
-- the twin table has the index materialized and shows the real read

CREATE TABLE t_est (a UInt64, c UInt64) ENGINE = MergeTree ORDER BY a
    SETTINGS index_granularity = 100, index_granularity_bytes = 0, min_bytes_for_wide_part = 0, auto_statistics_types = '';
CREATE TABLE t_real (a UInt64, c UInt64, INDEX idx_c c TYPE minmax GRANULARITY 1) ENGINE = MergeTree ORDER BY a
    SETTINGS index_granularity = 100, index_granularity_bytes = 0, min_bytes_for_wide_part = 0, auto_statistics_types = '';
INSERT INTO t_est SELECT number, cityHash64(intDiv(number, 100)) % 3 FROM numbers(6000);
INSERT INTO t_real SELECT * FROM t_est;
CREATE HYPOTHETICAL INDEX idx_c ON t_est (c) TYPE minmax GRANULARITY 1;

-- 60 windows: a budget of 3000 rows reads one window of every 2
WITH
    (SELECT arrayStringConcat(groupArray(explain), '\n') FROM (EXPLAIN WHATIF index_scan_budget_rows = 3000 SELECT a FROM t_est WHERE c = 0)) AS report,
    (SELECT arrayStringConcat(groupArray(explain), '\n') FROM (EXPLAIN indexes = 1 SELECT a FROM t_real WHERE c = 0 SETTINGS use_skip_indexes_on_data_read = 0)) AS plan,
    extractGroups(report, 'With idx_c [^\\n]*\\n +status: +applicable\\n +marks: +(\\d+)\\n +marks_span: +(\\d+) to (\\d+)') AS estimate,
    toUInt64OrZero(arrayElement(extractAll(plan, 'Granules: (\\d+)/'), -1)) AS real
SELECT extract(report, 'sampled_marks: +(\\d+ / \\d+)') AS sampled_marks, estimate, real, real BETWEEN toUInt64(estimate[2]) AND toUInt64(estimate[3]) AS real_in_span;

DROP TABLE t_est;
DROP TABLE t_real;
