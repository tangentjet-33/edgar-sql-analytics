-- ============================================================================
-- 04 — Most-used standard tags
-- ============================================================================
-- Question: Which standard US-GAAP tags appear most often in numeric facts?
-- Pattern:  Multi-table JOIN with filter on tag metadata.
-- Insight:  Reveals the "core vocabulary" of XBRL financial reporting.
-- ============================================================================

SELECT
    n.tag,
    COUNT(*)      AS occurrences,
    MAX(t.tlabel) AS sample_label
FROM num n
JOIN tag t ON n.tag = t.tag AND n.version = t.version
WHERE t.custom = 0 AND t.abstract = 0
GROUP BY n.tag
ORDER BY occurrences DESC
LIMIT 25;