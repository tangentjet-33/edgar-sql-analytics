-- ============================================================================
-- 16 — Wide income statement summary for selected companies, 2024
-- ============================================================================
-- Question: Side-by-side income statement comparison for peer companies.
-- Pattern:  Conditional aggregation (FILTER) to pivot tag-rows into columns.
-- Insight:  Demonstrates the canonical "long-to-wide" SQL pattern. The
--           output is the kind of table you'd hand to a Deals VP.
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
          'Revenues','RevenueFromContractWithCustomerExcludingAssessedTax',
          'CostOfRevenue','CostOfGoodsAndServicesSold','CostOfGoodsSold',
          'GrossProfit',
          'ResearchAndDevelopmentExpense',
          'SellingGeneralAndAdministrativeExpense','GeneralAndAdministrativeExpense',
          'OperatingIncomeLoss',
          'NetIncomeLoss','ProfitLoss'
      )
      AND n.qtrs=4 AND n.uom='USD' AND n.segments='' AND n.coreg='' AND n.value IS NOT NULL
      AND s.cik IN (320193, 789019, 1652044, 1018724, 1326801, 1067983)   -- AAPL, MSFT, GOOG, AMZN, META, BRK
),
deduped AS (SELECT cik, name, fy, tag, value FROM most_recent_filing WHERE rn=1)
SELECT
    MAX(name) AS name,
    fy,
    MAX(value) FILTER (WHERE tag IN ('Revenues','RevenueFromContractWithCustomerExcludingAssessedTax'))::numeric(28,0) AS revenue,
    MAX(value) FILTER (WHERE tag IN ('CostOfRevenue','CostOfGoodsAndServicesSold','CostOfGoodsSold'))::numeric(28,0) AS cogs,
    MAX(value) FILTER (WHERE tag = 'GrossProfit')::numeric(28,0) AS gross_profit,
    MAX(value) FILTER (WHERE tag = 'ResearchAndDevelopmentExpense')::numeric(28,0) AS rd,
    MAX(value) FILTER (WHERE tag IN ('SellingGeneralAndAdministrativeExpense','GeneralAndAdministrativeExpense'))::numeric(28,0) AS sga,
    MAX(value) FILTER (WHERE tag = 'OperatingIncomeLoss')::numeric(28,0) AS op_income,
    MAX(value) FILTER (WHERE tag IN ('NetIncomeLoss','ProfitLoss'))::numeric(28,0) AS net_income
FROM deduped
WHERE fy = 2024
GROUP BY cik, fy
ORDER BY revenue DESC;