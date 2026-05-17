-- ============================================================================
-- 17 — Free cash flow (CFO - CapEx) and FCF / Revenue ratio
-- ============================================================================
-- Question: Which large companies generate the most FCF relative to revenue?
-- Pattern:  Multi-tag pivot, derived metric, sector context.
-- Insight:  FCF/Revenue is a quality metric — high & stable = capital-light
--           cash machine. Pre-work for DCF.
-- ============================================================================

WITH most_recent_filing AS (
    SELECT s.cik, s.name, s.sic, EXTRACT(YEAR FROM n.ddate)::int AS fy, n.tag, n.value,
           ROW_NUMBER() OVER (
               PARTITION BY s.cik, EXTRACT(YEAR FROM n.ddate), n.tag
               ORDER BY s.filed DESC, s.adsh DESC
           ) AS rn
    FROM sub s JOIN num n ON s.adsh = n.adsh
    WHERE s.form IN ('10-K','10-K/A')
      AND n.tag IN (
          'Revenues','RevenueFromContractWithCustomerExcludingAssessedTax',
          'NetCashProvidedByUsedInOperatingActivities',
          'NetCashProvidedByUsedInOperatingActivitiesContinuingOperations',
          'PaymentsToAcquirePropertyPlantAndEquipment',
          'PaymentsToAcquireProductiveAssets'
      )
      AND n.qtrs=4 AND n.uom='USD' AND n.segments='' AND n.coreg=''
),
deduped AS (SELECT cik, name, sic, fy, tag, value FROM most_recent_filing WHERE rn=1),
pivoted AS (
    SELECT
        cik, MAX(name) AS name, MAX(sic) AS sic, fy,
        MAX(value) FILTER (WHERE tag IN ('Revenues','RevenueFromContractWithCustomerExcludingAssessedTax')) AS revenue,
        MAX(value) FILTER (WHERE tag IN ('NetCashProvidedByUsedInOperatingActivities','NetCashProvidedByUsedInOperatingActivitiesContinuingOperations')) AS cfo,
        MAX(value) FILTER (WHERE tag IN ('PaymentsToAcquirePropertyPlantAndEquipment','PaymentsToAcquireProductiveAssets')) AS capex
    FROM deduped
    GROUP BY cik, fy
)
SELECT
    cik, name, sic, fy,
    revenue::numeric(28,0)         AS revenue,
    cfo::numeric(28,0)             AS cfo,
    capex::numeric(28,0)           AS capex,
    (cfo - capex)::numeric(28,0)   AS fcf,
    ((cfo - capex) / NULLIF(revenue, 0))::numeric(10,4) AS fcf_margin
FROM pivoted
WHERE fy = 2024
  AND revenue   > 10000000000        -- $10B+ revenue
  AND cfo       IS NOT NULL
  AND capex     IS NOT NULL
  AND revenue   IS NOT NULL
ORDER BY fcf_margin DESC NULLS LAST
LIMIT 25;