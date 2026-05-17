-- ============================================================================
-- 11 — Original-vs-amended filing pairs (restatement candidates)
-- ============================================================================
-- Question: For each amended 10-K (10-K/A), can we identify the original
--           10-K it replaced, and how do the key reported figures differ?
-- Pattern:  Self-join on (cik, period). The amended filing shares the
--           reporting period with the original; pairs are matched on that.
-- Insight:  Restatements signal data quality issues, accounting changes,
--           or material misstatements — all relevant for credit and Deals
--           diligence. The frequency and magnitude of restatement is a
--           risk signal.
-- ============================================================================

WITH originals AS (
    SELECT
        cik,
        period,
        adsh   AS adsh_original,
        filed  AS filed_original,
        name
    FROM sub
    WHERE form = '10-K'
      AND period IS NOT NULL
),
amendments AS (
    SELECT
        cik,
        period,
        adsh  AS adsh_amended,
        filed AS filed_amended
    FROM sub
    WHERE form = '10-K/A'
      AND period IS NOT NULL
),
pairs AS (
    SELECT
        o.cik,
        o.name,
        o.period,
        o.adsh_original,
        o.filed_original,
        a.adsh_amended,
        a.filed_amended,
        (a.filed_amended - o.filed_original) AS days_between
    FROM originals o
    JOIN amendments a
      ON o.cik = a.cik
     AND o.period = a.period
     AND a.filed_amended > o.filed_original   -- amendment must postdate original
)
SELECT
    cik,
    name,
    period,
    filed_original,
    filed_amended,
    days_between,
    adsh_original,
    adsh_amended
FROM pairs
WHERE days_between BETWEEN 1 AND 1095          -- amendments within 3 years
ORDER BY days_between DESC
LIMIT 25;