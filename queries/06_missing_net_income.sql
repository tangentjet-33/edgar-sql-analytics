-- ============================================================================
-- 06 — 10-K filings missing core income statement tags
-- ============================================================================
-- Question: Which 10-K filings report no recognizable net income tag?
--           These are candidates for data quality investigation.
-- Pattern:  Anti-join via NOT EXISTS. Demonstrates how to find absence in
--           a many-to-many relationship.
-- Insight:  Quantifies how many filings would be invisible to a naive
--           cross-company net income query, and surfaces the data hygiene
--           required for downstream analytics.
-- ============================================================================

SELECT
    EXTRACT(YEAR FROM s.period)::int AS fiscal_year,
    COUNT(*)                         AS filings_missing_ni
FROM sub s
WHERE s.form = '10-K'
  AND s.period IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM num n
      WHERE n.adsh = s.adsh
        AND n.tag IN ('NetIncomeLoss', 'ProfitLoss', 'NetIncomeLossAvailableToCommonStockholdersBasic')
        AND n.qtrs = 4
        AND n.uom = 'USD'
        AND n.segments = ''
        AND n.coreg = ''
  )
GROUP BY fiscal_year
ORDER BY fiscal_year;