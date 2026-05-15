-- ============================================================================
-- 01 — Filings by year and form type
-- ============================================================================
-- Question: How many filings landed in each year, broken down by form type?
-- Pattern:  Basic aggregation with GROUP BY on two dimensions.
-- Insight:  Quantifies dataset coverage; surfaces seasonality and form-type mix.
-- ============================================================================

SELECT
    EXTRACT(YEAR FROM filed)::int AS filing_year,
    form,
    COUNT(*)                     AS filings
FROM sub
GROUP BY filing_year, form
ORDER BY filing_year, filings DESC;