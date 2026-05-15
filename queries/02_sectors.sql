-- ============================================================================
-- 02 — Distinct companies by SIC sector
-- ============================================================================
-- Question: Which SIC sectors are most represented in the dataset?
-- Pattern:  COUNT(DISTINCT) aggregation, ranking with LIMIT.
-- Insight:  Reveals which industries dominate public reporting; guides
--           sector-level analytical strategy for downstream queries.
-- ============================================================================

SELECT
    sic,
    COUNT(DISTINCT cik) AS companies,
    COUNT(*)            AS filings
FROM sub
WHERE sic IS NOT NULL
GROUP BY sic
ORDER BY companies DESC
LIMIT 25;