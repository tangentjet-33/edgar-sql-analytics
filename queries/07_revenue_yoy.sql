-- ============================================================================
-- 07 — Year-over-year revenue growth per company
-- ============================================================================
-- Question: For each company, how did revenue change from prior to current
--           fiscal year?
-- Pattern:  ROW_NUMBER + LAG to pick the latest filing per (cik, fiscal_year)
--           and compute YoY growth across the deduplicated time series.
-- Insight:  Surfaces growth leaders/laggards. Demonstrates handling of:
--             - tag duality (legacy Revenues vs ASC 606 tag)
--             - amendment-driven duplication (10-K plus 10-K/A)
--             - comparative-year data leaking from later filings
-- ============================================================================

WITH most_recent_filing AS (
    -- For each (cik, fiscal_year), rank filings by filed date (latest = 1).
    -- This deduplicates: original 10-K vs amendment 10-K/A vs comparative
    -- prior-year data inside a subsequent 10-K all map to the same
    -- (cik, fiscal_year). The most recently filed version wins.
    SELECT
        s.cik,
        s.adsh,
        EXTRACT(YEAR FROM n.ddate)::int AS fiscal_year,
        n.value                         AS revenue,
        ROW_NUMBER() OVER (
            PARTITION BY s.cik, EXTRACT(YEAR FROM n.ddate)
            ORDER BY s.filed DESC, s.adsh DESC
        ) AS rn
    FROM sub s
    JOIN num n ON s.adsh = n.adsh
    WHERE s.form IN ('10-K', '10-K/A')
      AND n.tag IN ('Revenues', 'RevenueFromContractWithCustomerExcludingAssessedTax')
      AND n.qtrs    = 4         -- annual flow only
      AND n.uom     = 'USD'
      AND n.segments = ''       -- consolidated, not segment slices
      AND n.coreg   = ''        -- main entity, not co-registrants
      AND n.value   > 0
),
annual_revenue AS (
    -- Keep only the winning row per (cik, fiscal_year).
    SELECT cik, fiscal_year, revenue
    FROM most_recent_filing
    WHERE rn = 1
)
SELECT
    cik,
    fiscal_year,
    revenue,
    LAG(revenue) OVER (PARTITION BY cik ORDER BY fiscal_year) AS prior_revenue,
    (revenue - LAG(revenue) OVER (PARTITION BY cik ORDER BY fiscal_year))
        / NULLIF(LAG(revenue) OVER (PARTITION BY cik ORDER BY fiscal_year), 0)
        AS yoy_growth
FROM annual_revenue
ORDER BY cik, fiscal_year
LIMIT 30;