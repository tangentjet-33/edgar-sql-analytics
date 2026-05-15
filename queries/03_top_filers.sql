-- ============================================================================
-- 03 — Top filers by submission count
-- ============================================================================
-- Question: Which companies file most frequently across the 20-quarter window?
-- Pattern:  GROUP BY with ranking, surfacing the heaviest reporters.
-- Insight:  High filing counts indicate: (a) operating subsidiaries with
--           separate SEC reporting, (b) frequent amendments, or (c) complex
--           registrants. Useful for understanding dataset skew.
-- ============================================================================

SELECT
    cik,
    MAX(name)            AS latest_name,
    COUNT(*)             AS filings,
    COUNT(DISTINCT form) AS form_types,
    MIN(filed)           AS first_filed,
    MAX(filed)           AS last_filed
FROM sub
GROUP BY cik
ORDER BY filings DESC
LIMIT 20;