-- ============================================================================
-- 15 — Cash conversion ratio (operating cash flow / net income) by company
-- ============================================================================
-- Question: Which companies consistently generate cash in excess of accrual
--           net income? This is a quality-of-earnings screen.
-- Pattern:  Multi-tag pivot, computed ratio, averaging across years.
-- Insight:  Cash conversion >1.0 over multiple years signals high earnings
--           quality (depreciation, working capital release). <1.0 persistently
--           signals working capital build, low-quality earnings, or growth
--           investment financed via accruals.
-- ============================================================================

WITH most_recent_filing AS (
    SELECT s.cik, s.name, EXTRACT(YEAR FROM n.ddate)::int AS fy, n.tag, n.value,
           ROW_NUMBER() OVER (
               PARTITION BY s.cik, EXTRACT(YEAR FROM n.ddate), n.tag
               ORDER BY s.filed DESC, s.adsh DESC
           ) AS rn
    FROM sub s JOIN num n ON s.adsh = n.adsh
    WHERE s.form IN ('10-K','10-K/A')
      AND n.tag IN (
          'NetCashProvidedByUsedInOperatingActivities',
          'NetCashProvidedByUsedInOperatingActivitiesContinuingOperations',
          'NetIncomeLoss',
          'ProfitLoss'
      )
      AND n.qtrs=4 AND n.uom='USD' AND n.segments='' AND n.coreg=''
),
deduped AS (
    SELECT cik, name, fy, tag, value FROM most_recent_filing WHERE rn=1
),
pivoted AS (
    SELECT
        cik,
        MAX(name) AS name,
        fy,
        MAX(value) FILTER (WHERE tag IN (
            'NetCashProvidedByUsedInOperatingActivities',
            'NetCashProvidedByUsedInOperatingActivitiesContinuingOperations'
        )) AS cfo,
        MAX(value) FILTER (WHERE tag IN ('NetIncomeLoss','ProfitLoss')) AS net_income
    FROM deduped
    GROUP BY cik, fy
),
ratios AS (
    SELECT
        cik, name, fy,
        cfo, net_income,
        cfo / NULLIF(net_income, 0) AS cash_conversion
    FROM pivoted
    WHERE cfo IS NOT NULL
      AND net_income IS NOT NULL
      AND net_income > 50000000           -- $50M+ NI to filter shells
),
multi_year AS (
    SELECT
        cik,
        MAX(name) AS name,
        COUNT(*) AS years_with_data,
        AVG(cash_conversion)::numeric(10,3) AS avg_conversion,
        MIN(cash_conversion)::numeric(10,3) AS min_conversion,
        MAX(cash_conversion)::numeric(10,3) AS max_conversion
    FROM ratios
    WHERE cash_conversion BETWEEN 0 AND 5   -- trim extremes from divide-by-tiny-NI
    GROUP BY cik
    HAVING COUNT(*) >= 4                     -- need at least 4 years of data
)
SELECT
    cik, name, years_with_data,
    avg_conversion, min_conversion, max_conversion
FROM multi_year
ORDER BY avg_conversion DESC
LIMIT 25;