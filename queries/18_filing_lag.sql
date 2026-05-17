-- ============================================================================
-- 18 — Filing lag: how long after period end does each company file?
-- ============================================================================
-- Question: Distribution of days between fiscal period end and 10-K filing
--           by filer status (afs). Surfaces compliance discipline and
--           accelerated-filer rule effects.
-- Pattern:  Date arithmetic, percentile aggregates, multi-dimensional grouping.
-- Insight:  Large Accelerated Filers must file 10-K within 60 days of FYE,
--           Accelerated within 75, Non-Accelerated within 90. Outliers signal
--           late filings, NT 10-K extensions, or financial distress.
-- ============================================================================

SELECT
    afs,
    EXTRACT(YEAR FROM period)::int AS period_year,
    COUNT(*) AS filings,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY (filed - period)) AS p25_days,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY (filed - period)) AS median_days,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY (filed - period)) AS p75_days,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY (filed - period)) AS p95_days,
    SUM(CASE WHEN (filed - period) > 90 THEN 1 ELSE 0 END) AS late_filings
FROM sub
WHERE form = '10-K'
  AND period IS NOT NULL
  AND afs IS NOT NULL
  AND (filed - period) BETWEEN 1 AND 365
GROUP BY afs, period_year
ORDER BY afs, period_year;