-- ============================================================================
-- SEC EDGAR Financial Statement Data Sets — PostgreSQL Schema
-- ============================================================================
-- Tables: sub, tag, num, pre
-- Source: SEC quarterly Financial Statement Data Sets (sub.txt, tag.txt,
--         num.txt, pre.txt) from 5 years / 20 quarters.
--
-- Design decisions:
--   - Composite natural PKs (no surrogate keys) — enforces correctness.
--   - No FK constraints — validated post-load via integrity queries.
--   - segments and coreg in num are NOT NULL DEFAULT ''
--     (NULL replaced with '' at load time so they can participate in PK).
--   - All text columns are `text`; documented max lengths in comments.
--   - Booleans stored as smallint (0/1) to match source format.
--   - YYYYMMDD strings cast to DATE at load time.
--
-- Re-running this script drops and recreates all tables. Data is reloaded
-- by the loader (src/load.py), not by this script.
-- ============================================================================

-- Drop in reverse dependency order. CASCADE not strictly needed without FKs,
-- but harmless and future-proof if FKs are added later.
DROP TABLE IF EXISTS pre CASCADE;
DROP TABLE IF EXISTS num CASCADE;
DROP TABLE IF EXISTS tag CASCADE;
DROP TABLE IF EXISTS sub CASCADE;


-- ============================================================================
-- sub — Submissions (one row per filing)
-- ============================================================================
-- Source: data/<quarter>/sub.txt
-- Natural PK: adsh
-- Expected row count per quarter: ~8,000
-- ============================================================================
CREATE TABLE sub (
    adsh          text        NOT NULL,             -- max 20, accession number
    cik           bigint      NOT NULL,             -- SEC company identifier
    name          text        NOT NULL,             -- max 150, registrant name
    sic           integer,                          -- max 4, industry code
    countryba     text,                             -- max 2, business country
    stprba        text,                             -- max 2, business state
    cityba        text,                             -- max 30
    zipba         text,                             -- max 10
    bas1          text,                             -- max 40, street 1
    bas2          text,                             -- max 40, street 2
    baph          text,                             -- max 20, phone
    countryma     text,                             -- max 2, mailing country
    stprma        text,                             -- max 2, mailing state
    cityma        text,                             -- max 30
    zipma         text,                             -- max 10
    mas1          text,                             -- max 40
    mas2          text,                             -- max 40
    countryinc    text,                             -- max 3, incorp country
    stprinc       text,                             -- max 2, incorp state
    ein           text,                             -- max 10, tax ID
    former        text,                             -- max 150, prior name
    changed       date,                             -- date of name change
    afs           text,                             -- max 5, filer status
    wksi          smallint    NOT NULL,             -- 0/1 well-known issuer
    fye           text,                             -- max 4, fiscal yr end MMDD
    form          text        NOT NULL,             -- max 10, e.g. 10-K
    period        date        NOT NULL,             -- balance sheet date
    fy            smallint,                         -- fiscal year
    fp            text,                             -- max 2, FY or Q1-Q4
    filed         date        NOT NULL,             -- filing date
    accepted      timestamp   NOT NULL,             -- acceptance timestamp
    prevrpt       smallint    NOT NULL,             -- 0/1 amended subsequently
    detail        smallint    NOT NULL,             -- 0/1 has detail tags
    instance      text        NOT NULL,             -- max 40, XBRL filename
    nciks         integer     NOT NULL,             -- count of CIKs in filing
    aciks         text,                             -- max 120, additional CIKs

    CONSTRAINT pk_sub PRIMARY KEY (adsh)
);


-- ============================================================================
-- tag — Tag dictionary (one row per concept per taxonomy version)
-- ============================================================================
-- Source: data/<quarter>/tag.txt
-- Natural PK: (tag, version)
-- Expected row count per quarter: ~30,000
-- Note: same (tag, version) appears in many quarters. Loader uses
--       ON CONFLICT DO NOTHING.
-- ============================================================================
CREATE TABLE tag (
    tag           text        NOT NULL,             -- max 256, concept name
    version       text        NOT NULL,             -- max 20, taxonomy or adsh
    custom        smallint    NOT NULL,             -- 0/1 filer extension
    abstract      smallint    NOT NULL,             -- 0/1 abstract (header)
    datatype      text,                             -- max 20, NULL if abstract
    iord          text        NOT NULL,             -- 1 char, I/D, NULL if abstract
    crdr          text,                             -- 1 char, C/D, NULL if not monetary
    tlabel        text,                             -- max 512, standard label
    doc           text,                             -- no max, long definition

    CONSTRAINT pk_tag PRIMARY KEY (tag, version)
);


-- ============================================================================
-- num — Numeric facts (one row per reported value)
-- ============================================================================
-- Source: data/<quarter>/num.txt
-- Natural PK: (adsh, tag, version, ddate, qtrs, uom, segments, coreg)
-- Expected row count per quarter: 3–5 million
-- Note: segments and coreg are NOT NULL DEFAULT '' so they can participate
--       in the composite PK. NULL→'' substitution happens in load.py.
-- ============================================================================
CREATE TABLE num (
    adsh          text             NOT NULL,        -- max 20, FK to sub.adsh
    tag           text             NOT NULL,        -- max 256
    version       text             NOT NULL,        -- max 20
    ddate         date             NOT NULL,        -- period end for this fact
    qtrs          smallint         NOT NULL,        -- 0=instant, 1-4=duration
    uom           text             NOT NULL,        -- max 20, USD/shares/etc
    segments      text             NOT NULL DEFAULT '',  -- max 1024
    coreg         text             NOT NULL DEFAULT '',  -- max 256
    value         numeric(28,4),                    -- reported value
    footnote      text,                             -- max 512

    CONSTRAINT pk_num PRIMARY KEY
        (adsh, tag, version, ddate, qtrs, uom, segments, coreg)
);


-- ============================================================================
-- pre — Presentation lines (one row per rendered statement line)
-- ============================================================================
-- Source: data/<quarter>/pre.txt
-- Natural PK: (adsh, report, line)
-- Expected row count per quarter: ~1 million
-- ============================================================================
CREATE TABLE pre (
    adsh          text        NOT NULL,             -- max 20, FK to sub.adsh
    report        smallint    NOT NULL,             -- report grouping number
    line          smallint    NOT NULL,             -- line order within report
    stmt          text        NOT NULL,             -- max 2, BS/IS/CF/EQ/CI/SI/UN
    inpth         smallint    NOT NULL,             -- 0/1 parenthetical
    rfile         text        NOT NULL,             -- 1 char, H/X
    tag           text        NOT NULL,             -- max 256
    version       text        NOT NULL,             -- max 20
    plabel        text        NOT NULL,             -- max 512, filer label
    negating      smallint    NOT NULL,             -- 0/1 display sign flipped

    CONSTRAINT pk_pre PRIMARY KEY (adsh, report, line)
);


-- ============================================================================
-- Indexes
-- ============================================================================
-- Composite PKs already serve as indexes on their leading edges. These add
-- coverage for common analytical access patterns the PKs don't address.
-- Add more after running EXPLAIN ANALYZE on real queries; don't pre-index
-- everything.
-- ============================================================================

-- sub: track a company across periods
CREATE INDEX idx_sub_cik_period   ON sub (cik, period);

-- sub: filter to annual reports vs quarterly
CREATE INDEX idx_sub_form         ON sub (form);

-- sub: sector-level grouping
CREATE INDEX idx_sub_sic          ON sub (sic);

-- num: find all values of a given concept across filings
-- (PK leading edge is adsh, so this is the complement)
CREATE INDEX idx_num_tag_version  ON num (tag, version);

-- num: time-series queries by reporting date
CREATE INDEX idx_num_ddate        ON num (ddate);

-- pre: filter statement lines by statement type within a filing
CREATE INDEX idx_pre_adsh_stmt    ON pre (adsh, stmt);

-- pre: find statement lines by concept
CREATE INDEX idx_pre_tag_version  ON pre (tag, version);