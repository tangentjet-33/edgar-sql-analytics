-- ============================================================================
-- 14 — Effective tax rate dispersion by sector
-- ============================================================================
-- Question: Which sectors show the widest spread in effective tax rates?
-- Pattern:  Computed ratio, statistical aggregates (PERCENTILE_CONT), sector grouping.
-- Insight:  High ETR dispersion within a sector flags tax-planning aggression,
--           foreign income mix, or one-off items distorting reported income.
-- ============================================================================

WITH most_recent_filing AS (
    SELECT s.cik, s.sic, EXTRACT(YEAR FROM n.ddate)::int AS fy, n.tag, n.value,
           ROW_NUMBER() OVER (
               PARTITION BY s.cik, EXTRACT(YEAR FROM n.ddate), n.tag
               ORDER BY s.filed DESC, s.adsh DESC
           ) AS rn
    FROM sub s JOIN num n ON s.adsh = n.adsh
    WHERE s.form IN ('10-K','10-K/A')
      AND n.tag IN (
          'IncomeLossFromContinuingOperationsBeforeIncomeTaxesExtraordinaryItemsNoncontrollingInterest',
          'IncomeLossFromContinuingOperationsBeforeIncomeTaxesMinorityInterestAndIncomeLossFromEquityMethodInvestments',
          'IncomeTaxExpenseBenefit'
      )
      AND n.qtrs=4 AND n.uom='USD' AND n.segments='' AND n.coreg=''
      AND s.sic IS NOT NULL
),
deduped AS (
    SELECT cik, sic, fy, tag, value FROM most_recent_filing WHERE rn=1
),
pivoted AS (
    SELECT
        cik, sic, fy,
        MAX(value) FILTER (WHERE tag IN (
            'IncomeLossFromContinuingOperationsBeforeIncomeTaxesExtraordinaryItemsNoncontrollingInterest',
            'IncomeLossFromContinuingOperationsBeforeIncomeTaxesMinorityInterestAndIncomeLossFromEquityMethodInvestments'
        )) AS pretax_income,
        MAX(value) FILTER (WHERE tag = 'IncomeTaxExpenseBenefit') AS tax_expense
    FROM deduped
    GROUP BY cik, sic, fy
),
etr AS (
    SELECT cik, sic, fy, tax_expense / NULLIF(pretax_income, 0) AS effective_rate
    FROM pivoted
    WHERE pretax_income > 1000000        -- $1M+ pretax to exclude noise
      AND tax_expense IS NOT NULL
)
SELECT
    sic,
    fy,
    COUNT(*) AS firms,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY effective_rate) AS p25_etr,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY effective_rate) AS median_etr,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY effective_rate) AS p75_etr,
    (PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY effective_rate)
     - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY effective_rate)) AS iqr
FROM etr
WHERE fy = 2024
  AND effective_rate BETWEEN -1 AND 1   -- trim insane outliers from data quality
GROUP BY sic, fy
HAVING COUNT(*) >= 10
ORDER BY iqr DESC
LIMIT 20;