-- ============================================================================
-- 05 — Annual revenue from 10-K filings, by year
-- ============================================================================
-- Question: Across all 10-K filings, what is the distribution of reported
--           annual revenue by fiscal year?
-- Pattern:  3-table JOIN (sub + num + tag) with filtering on form, tag,
--           and period type. Demonstrates how to extract a single GAAP
--           concept across the universe.
-- Insight:  Establishes the baseline for any cross-sectional revenue analysis.
--           Surfaces tag-version differences between us-gaap/2022, 2023, 2024.
-- ============================================================================

SELECT
    EXTRACT(YEAR FROM n.ddate)::int                AS fiscal_year,
    n.version                                       AS taxonomy_version,
    COUNT(*)                                        AS filings_reporting,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY n.value)  AS median_revenue,
    AVG(n.value)::numeric(28,2)                     AS mean_revenue,
    SUM(n.value)::numeric(28,0)                     AS total_revenue
FROM sub s
JOIN num n ON s.adsh = n.adsh
WHERE s.form = '10-K'
  AND n.tag IN ('Revenues', 'RevenueFromContractWithCustomerExcludingAssessedTax')
  AND n.qtrs = 4                  -- annual flows only
  AND n.uom = 'USD'
  AND n.segments = ''             -- consolidated only, no segment slices
  AND n.coreg = ''                -- main entity, not co-registrants
  AND n.value > 0                 -- exclude negative or zero (rare but possible)
GROUP BY fiscal_year, n.version
ORDER BY fiscal_year, n.version;