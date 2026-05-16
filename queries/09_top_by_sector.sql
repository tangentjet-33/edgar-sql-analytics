-- ============================================================================
-- 09 — Top 5 companies by revenue, per sector and year
-- ============================================================================
-- Question: Within each SIC sector and fiscal year, who are the top 5
--           revenue earners?
-- Pattern:  RANK window function partitioned by (sector, year). The
--           filter-after-rank trick: rank in a subquery, filter outside.
-- Insight:  Sector leadership snapshot. Demonstrates the canonical
--           "top-N-per-group" SQL pattern that comes up in every analytics
--           interview.
-- ============================================================================

WITH most_recent_filing AS (
    SELECT
        s.cik,
        s.sic,
        s.name,
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
      AND s.sic IS NOT NULL
),
annual_revenue AS (
    SELECT cik, sic, name, fiscal_year, revenue
    FROM most_recent_filing
    WHERE rn = 1
),
ranked AS (
    SELECT
        sic,
        fiscal_year,
        cik,
        name,
        revenue,
        RANK() OVER (
            PARTITION BY sic, fiscal_year
            ORDER BY revenue DESC
        ) AS sector_rank
    FROM annual_revenue
)
SELECT sic, fiscal_year, sector_rank, cik, name, revenue
FROM ranked
WHERE sector_rank <= 5
  AND fiscal_year BETWEEN 2021 AND 2024
  AND sic IN (2834, 7372, 6022, 7370, 1311)  -- pharma, software, banks, services, oil&gas
ORDER BY sic, fiscal_year, sector_rank;