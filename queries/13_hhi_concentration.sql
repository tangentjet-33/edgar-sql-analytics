-- ============================================================================
-- 13 — Revenue concentration (Herfindahl-Hirschman Index) by sector
-- ============================================================================
-- Question: How concentrated is revenue within each sector?
-- Pattern:  Two-level aggregation in CTEs, share computation, sum of squares.
-- Insight:  HHI is the standard antitrust/competition metric. >2500 = highly
--           concentrated, 1500-2500 = moderately concentrated, <1500 = competitive.
-- ============================================================================

WITH most_recent_filing AS (
    SELECT
        s.cik, s.sic,
        EXTRACT(YEAR FROM n.ddate)::int AS fy,
        n.value AS revenue,
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
annual AS (
    SELECT cik, sic, fy, revenue FROM most_recent_filing WHERE rn=1
),
sector_totals AS (
    SELECT sic, fy, SUM(revenue) AS sector_revenue, COUNT(*) AS firm_count
    FROM annual
    GROUP BY sic, fy
    HAVING COUNT(*) >= 5         -- only sectors with >=5 firms reporting
       AND SUM(revenue) > 0
),
shares AS (
    SELECT
        a.sic, a.fy, a.cik, a.revenue,
        t.sector_revenue,
        t.firm_count,
        a.revenue / t.sector_revenue AS market_share
    FROM annual a
    JOIN sector_totals t ON a.sic = t.sic AND a.fy = t.fy
)
SELECT
    sic,
    fy,
    firm_count,
    sector_revenue,
    -- HHI = sum of squared market shares × 10000 (so it's on 0-10000 scale)
    SUM(POWER(market_share * 100, 2))::numeric(8,1) AS hhi,
    CASE
        WHEN SUM(POWER(market_share * 100, 2)) > 2500 THEN 'highly concentrated'
        WHEN SUM(POWER(market_share * 100, 2)) > 1500 THEN 'moderately concentrated'
        ELSE 'competitive'
    END AS concentration_label
FROM shares
WHERE fy = 2024
GROUP BY sic, fy, firm_count, sector_revenue
ORDER BY hhi DESC
LIMIT 25;