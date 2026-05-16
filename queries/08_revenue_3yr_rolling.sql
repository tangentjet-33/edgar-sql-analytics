-- ============================================================================
-- 08 — 3-year rolling revenue sum per company
-- ============================================================================
-- Question: For each company-year, what is the trailing 3-year revenue sum?
-- Pattern:  Window frame (ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) over
--           a deduplicated annual revenue series.
-- Insight:  Smooths annual volatility, useful for trend identification.
--           A common pattern in DCF preparation: 3-year trailing as a
--           sanity check on revenue scale and direction.
-- ============================================================================

WITH most_recent_filing AS (
    SELECT
        s.cik,
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
      AND n.qtrs    = 4
      AND n.uom     = 'USD'
      AND n.segments = ''
      AND n.coreg   = ''
      AND n.value   > 0
),
annual_revenue AS (
    SELECT cik, fiscal_year, revenue
    FROM most_recent_filing
    WHERE rn = 1
)
SELECT
    cik,
    fiscal_year,
    revenue,
    SUM(revenue) OVER (
        PARTITION BY cik
        ORDER BY fiscal_year
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS revenue_3yr_sum,
    COUNT(*) OVER (
        PARTITION BY cik
        ORDER BY fiscal_year
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS years_in_window
FROM annual_revenue
ORDER BY cik, fiscal_year
LIMIT 30;