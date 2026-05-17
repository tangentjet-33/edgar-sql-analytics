-- ============================================================================
-- 19 — SPAC lifecycle: companies that filed briefly and stopped
-- ============================================================================
-- Question: Which SIC=6770 (blank check) companies filed for fewer than
--           2 years before vanishing from the dataset?
-- Pattern:  Aggregate per CIK with date math, filter on time window.
-- Insight:  Quantifies the SPAC boom-bust. Most blank-check companies either
--           consummate a merger (re-incorporating under a different name/CIK)
--           or dissolve. Either way, their CIK exits.
-- ============================================================================

SELECT
    cik,
    MAX(name) AS name,
    MIN(filed) AS first_filing,
    MAX(filed) AS last_filing,
    (MAX(filed) - MIN(filed)) AS days_active,
    COUNT(*) AS filing_count,
    COUNT(DISTINCT form) AS form_types
FROM sub
WHERE sic = 6770
GROUP BY cik
HAVING (MAX(filed) - MIN(filed)) BETWEEN 30 AND 730   -- 1 month to 2 years
   AND MAX(filed) < '2025-01-01'                      -- has stopped filing
ORDER BY filing_count DESC, days_active DESC
LIMIT 25;