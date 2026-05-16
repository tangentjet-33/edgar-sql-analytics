-- ============================================================================
-- 10 — Gross margin compression year-over-year
-- ============================================================================
-- Question: Which companies experienced the largest gross margin compression
--           in the most recent year?
-- Pattern:  Multi-tag join (revenue + COGS), derived ratio, LAG on the ratio,
--           filter-after-window to compare same row's prior-year value.
-- Insight:  Margin compression is a leading signal for distress, pricing
--           pressure, or input cost shocks. Common screen in Deals/credit work.
-- ============================================================================

WITH most_recent_filing AS (
    -- For each (cik, fiscal_year, tag), keep only the most recently filed
    -- version. Handles 10-K + 10-K/A + comparative-year leakage.
    SELECT
        s.cik,
        s.name,
        EXTRACT(YEAR FROM n.ddate)::int AS fiscal_year,
        n.tag,
        n.value,
        ROW_NUMBER() OVER (
            PARTITION BY s.cik, EXTRACT(YEAR FROM n.ddate), n.tag
            ORDER BY s.filed DESC, s.adsh DESC
        ) AS rn
    FROM sub s
    JOIN num n ON s.adsh = n.adsh
    WHERE s.form IN ('10-K', '10-K/A')
      AND n.tag IN (
          'Revenues',
          'RevenueFromContractWithCustomerExcludingAssessedTax',
          'CostOfRevenue',
          'CostOfGoodsAndServicesSold',
          'CostOfGoodsSold'
      )
      AND n.qtrs    = 4
      AND n.uom     = 'USD'
      AND n.segments = ''
      AND n.coreg   = ''
      AND n.value   > 0
),
deduplicated AS (
    SELECT cik, name, fiscal_year, tag, value
    FROM most_recent_filing
    WHERE rn = 1
),
pivoted AS (
    -- Conditional aggregation: collapse multiple rows per (cik, fiscal_year)
    -- into one row with revenue and COGS as separate columns.
    -- MAX (not SUM) avoids double-counting if a filer reports under both
    -- legacy and ASC 606 revenue tags in the same year.
    SELECT
        cik,
        MAX(name) AS name,
        fiscal_year,
        MAX(value) FILTER (
            WHERE tag IN ('Revenues',
                          'RevenueFromContractWithCustomerExcludingAssessedTax')
        ) AS revenue,
        MAX(value) FILTER (
            WHERE tag IN ('CostOfRevenue',
                          'CostOfGoodsAndServicesSold',
                          'CostOfGoodsSold')
        ) AS cogs
    FROM deduplicated
    GROUP BY cik, fiscal_year
),
margins AS (
    SELECT
        cik,
        name,
        fiscal_year,
        revenue,
        cogs,
        (revenue - cogs) / NULLIF(revenue, 0) AS gross_margin
    FROM pivoted
    WHERE revenue IS NOT NULL
      AND cogs    IS NOT NULL
),
with_lag AS (
    -- Compute LAG over the full margins history (all years, all companies)
    -- so the 2024 row can see the 2023 row from the same partition.
    SELECT
        cik,
        name,
        fiscal_year,
        revenue,
        gross_margin,
        LAG(gross_margin) OVER (
            PARTITION BY cik
            ORDER BY fiscal_year
        ) AS prior_margin
    FROM margins
)
SELECT
    cik,
    name,
    fiscal_year,
    revenue,
    gross_margin,
    prior_margin,
    gross_margin - prior_margin AS margin_change_pp
FROM with_lag
WHERE fiscal_year = 2024
  AND prior_margin IS NOT NULL
  AND revenue > 1000000000   -- $1B+ companies for signal
ORDER BY margin_change_pp ASC
LIMIT 20;