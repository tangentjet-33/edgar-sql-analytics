-- ============================================================================
-- 20 — Top-5 sector revenue share shift, 2021 vs 2024
-- ============================================================================
-- Question: How has the top-5 firms' share of sector revenue changed
--           between 2021 and 2024 in the largest sectors?
-- Pattern:  Nested aggregation (top-5 within sector-year, then sector total).
--           Self-comparison across years.
-- Insight:  Rising top-5 share = consolidation / scale advantages.
--           Falling top-5 share = disruption / new entrants.
-- ============================================================================

WITH most_recent_filing AS (
    SELECT s.cik, s.sic, EXTRACT(YEAR FROM n.ddate)::int AS fy, n.value AS revenue,
           ROW_NUMBER() OVER (
               PARTITION BY s.cik, EXTRACT(YEAR FROM n.ddate)
               ORDER BY s.filed DESC, s.adsh DESC
           ) AS rn
    FROM sub s JOIN num n ON s.adsh = n.adsh
    WHERE s.form IN ('10-K','10-K/A')
      AND n.tag IN ('Revenues','RevenueFromContractWithCustomerExcludingAssessedTax')
      AND n.qtrs=4 AND n.uom='USD' AND n.segments='' AND n.coreg='' AND n.value>0
      AND s.sic IS NOT NULL
),
annual AS (SELECT cik, sic, fy, revenue FROM most_recent_filing WHERE rn=1),
ranked AS (
    SELECT
        sic, fy, cik, revenue,
        RANK() OVER (PARTITION BY sic, fy ORDER BY revenue DESC) AS sector_rank,
        SUM(revenue) OVER (PARTITION BY sic, fy) AS sector_total
    FROM annual
),
top5_share AS (
    SELECT
        sic, fy,
        SUM(CASE WHEN sector_rank <= 5 THEN revenue ELSE 0 END) / NULLIF(MAX(sector_total), 0) AS top5_share,
        COUNT(*) AS firms_in_sector,
        MAX(sector_total) AS sector_total
    FROM ranked
    GROUP BY sic, fy
    HAVING MAX(sector_total) > 10000000000   -- only sectors with $10B+ total
       AND COUNT(*) >= 10                    -- at least 10 firms
)
SELECT
    a.sic,
    a.firms_in_sector AS firms_2021,
    b.firms_in_sector AS firms_2024,
    a.sector_total::numeric(28,0)  AS total_2021,
    b.sector_total::numeric(28,0)  AS total_2024,
    a.top5_share::numeric(6,4)     AS top5_share_2021,
    b.top5_share::numeric(6,4)     AS top5_share_2024,
    (b.top5_share - a.top5_share)::numeric(6,4) AS share_change
FROM top5_share a
JOIN top5_share b ON a.sic = b.sic
WHERE a.fy = 2021 AND b.fy = 2024
ORDER BY ABS(b.top5_share - a.top5_share) DESC
LIMIT 25;