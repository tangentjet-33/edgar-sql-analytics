-- ============================================================================
-- 12 — Top 3 expense categories per 10-K filing (LATERAL join)
-- ============================================================================
-- Question: For each large 10-K filing, what are the three largest expense
--           categories reported for the current fiscal year?
-- Pattern:  LATERAL join — correlated subquery per outer row, with LIMIT
--           inside. ddate=period restricts to current-year facts so each
--           outer row pulls distinct expense categories, not multiple years
--           of the same tag.
-- Insight:  LATERAL is Postgres's idiomatic top-N-per-group when you can
--           stop scanning early at LIMIT. Comparable to ROW_NUMBER + filter
--           but cheaper when the inner set is large and the outer set small.
-- ============================================================================

WITH big_filings AS (
    -- Driver: handful of mega-cap 10-Ks so output stays readable.
    -- adsh and period are what the lateral subquery correlates against.
    SELECT
        s.adsh,
        s.cik,
        s.name,
        s.period,
        EXTRACT(YEAR FROM s.period)::int AS fy
    FROM sub s
    WHERE s.form = '10-K'
      AND s.period IS NOT NULL
      AND s.cik IN (
          320193,    -- Apple
          789019,    -- Microsoft
          1652044,   -- Alphabet
          1018724,   -- Amazon
          1326801    -- Meta / Facebook
      )
)
SELECT
    bf.name,
    bf.fy,
    x.tag,
    x.value
FROM big_filings bf
CROSS JOIN LATERAL (
    -- Re-evaluated per outer row of big_filings, using bf.adsh and bf.period.
    -- Returns up to 3 rows (top expenses by magnitude) for that filing.
    SELECT n.tag, n.value
    FROM num n
    WHERE n.adsh    = bf.adsh
      AND n.ddate   = bf.period            -- current-year only
      AND n.tag IN (
          'CostOfRevenue',
          'CostOfGoodsAndServicesSold',
          'ResearchAndDevelopmentExpense',
          'SellingGeneralAndAdministrativeExpense',
          'GeneralAndAdministrativeExpense',
          'SellingAndMarketingExpense',
          'OperatingExpenses',
          'OtherOperatingExpenses',
          'DepreciationAndAmortization',
          'MarketingExpense',
          'AdvertisingExpense'
      )
      AND n.qtrs    = 4
      AND n.uom     = 'USD'
      AND n.segments = ''
      AND n.coreg   = ''
      AND n.value   > 0
    ORDER BY n.value DESC
    LIMIT 3
) x
ORDER BY bf.name, bf.fy DESC, x.value DESC;