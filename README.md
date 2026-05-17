# SEC EDGAR SQL Analytics

Production-grade SQL analytics over 5 years (20 quarters, 2021q1–2025q4) of SEC EDGAR Financial Statement & Notes Data Sets, loaded into PostgreSQL with idempotent Python ingestion and validated against empirical data quality scans.

## Scope

- **141,401** filings (form types 10-K, 10-Q, 10-K/A, 10-Q/A, others)
- **1,743,086** unique tag-version pairs from XBRL taxonomies
- **68,349,478** numeric facts in `num`
- **15,719,411** presentation lines in `pre`
- **20 queries** in `queries/` covering aggregation, joins, anti-joins, window functions (LAG, RANK, rolling), CTEs, conditional aggregation, LATERAL, and percentile aggregates.

See [FINDINGS.md](FINDINGS.md) for 11 empirical findings drawn from the analytical queries.

## Stack

- **PostgreSQL 16** (local, Homebrew)
- **Python 3.11** in a conda environment (`edgar`)
- **psycopg3** for COPY-based bulk loading
- **pandas** for chunked file parsing and validation

No ORM, no migrations framework. The schema is one hand-written `schema.sql`; the loader is one Python script reading SEC's tab-delimited files in 100K-row chunks.

## Repository structure

```
edgar-sql-analytics/
├── README.md             # this file
├── FINDINGS.md           # empirical findings from the analytical queries
├── environment.yml       # conda environment specification
├── schema.sql            # PostgreSQL table and index definitions
├── src/
│   ├── fetch.py          # downloads quarterly EDGAR ZIPs, validates, unzips
│   └── load.py           # idempotent chunked loader into PostgreSQL
├── queries/              # 20 analytical SQL files (01-20)
├── data/                 # raw downloads (gitignored)
└── outputs/              # generated artifacts (gitignored)
```

## Schema

Four tables matching SEC's source file structure:

- **sub** — one row per filing submission (36 columns, PK `adsh`)
- **tag** — one row per concept-taxonomy pair (9 columns, PK `(tag, version)`)
- **num** — one row per numeric fact (10 columns, 8-column composite PK)
- **pre** — one row per rendered statement line (10 columns, 3-column composite PK)

No foreign key constraints — integrity is validated post-load via SQL anti-joins. No surrogate keys; composite natural PKs enforce correctness at the boundary.

One partial index supplements the PKs:

```sql
CREATE INDEX idx_tag_standard_concrete
ON tag (tag, version)
WHERE custom = 0 AND abstract = 0;
```

This index serves analytical queries that filter to the 37K standard concrete concepts (5.5% of tag rows). Without it, those queries sequential-scan the full tag table.

## Design decisions

### Natural PKs over surrogate keys

`num`'s 8-column composite PK catches duplicate fact rows at load time, including SEC's own intra-file duplicates (one filer, CIK 1918712, consistently emits malformed derivative-segment duplicates caught by the PK). Surrogate `bigserial` IDs would have silently masked these.

### Empty-string sentinel for nullable PK columns

`num.segments` and `num.coreg` are nullable in SEC's source but participate in the PK. They cannot be SQL NULL (Postgres forbids NULL in PK columns). The load script substitutes `''` at clean time; the schema declares `NOT NULL DEFAULT ''`.

### No FK constraints

For one-time bulk loads of 65M+ row tables, the FK-enforcement overhead is significant and yields no findings (SEC data is internally consistent at the file level). Integrity is validated once after load via:

```sql
SELECT COUNT(*) FROM num n
LEFT JOIN sub s ON n.adsh = s.adsh
WHERE s.adsh IS NULL;
-- Returns 0
```

### Chunked load with row-level error handling

`num.txt` files are ~500MB raw; loading whole-file into pandas balloons to 2-3GB RAM. The loader streams 100K-row chunks, validates types, drops rows with NULL in PK columns (with logging), and uses `COPY ... FROM STDIN` for bulk insert. Memory stays under 500MB.

### Idempotency per quarter

Each quarter's load wraps in a transaction:
1. Read sub.txt to get the list of accession numbers.
2. Delete those `adsh` from sub, num, pre (tag is never deleted).
3. Upsert tags via `INSERT ... ON CONFLICT DO NOTHING` through a staging temp table.
4. COPY-load sub, num, pre.
5. Commit.

Reruns produce identical row counts. Failed runs roll back to the previous quarter's state.

## Data quality findings during load

These were discovered empirically during ingestion and are documented both in the loader's runtime warnings and below:

| Issue | Impact | Resolution |
|---|---|---|
| SEC documented `NOT NULL` is wrong for `sub.period`, `pre.stmt`, `pre.plabel` | Non-standard form types (N-2, S-1, etc.) lack fiscal-period fields | Relaxed schema, documented in code comments |
| Filer typos producing year ≥ 2262 dates (overflow pandas Timestamp) | 24 rows across 68M | Dropped at clean time with logged warning |
| SEC writes `\N` as a NULL sentinel in some fields | Pandas reads as the literal string `"\\N"` | Added to `na_values` in `read_chunks` |
| Intra-file PK duplicates from one fund manager (CIK 1918712) | Same fact row appears twice in malformed segment dimensions | `INSERT ... ON CONFLICT DO NOTHING` via temp table |
| 94.5% of tag rows are filer-extension custom tags | Direct cross-company tag joins severely undercount | Documented; cross-company queries restrict to `custom = 0` |
| Taxonomy version churn across us-gaap/2022, 2023, 2024 | Same logical concept "Assets" exists 5 times | Queries `GROUP BY tag` (not version) to aggregate |
| ASC 606 revenue tag migration | Two different revenue tags (`Revenues` and `RevenueFromContractWithCustomerExcludingAssessedTax`) | All revenue queries `IN ()` both |
| Comparative-year leakage | Same `(cik, fiscal_year)` appears in multiple filings | `ROW_NUMBER() OVER (PARTITION BY cik, fy ORDER BY filed DESC)` pattern in every aggregation query |

## Query catalog

| # | File | Pattern | Question |
|---|---|---|---|
| 01 | `01_filings_by_year.sql` | GROUP BY | Filing volume by year and form |
| 02 | `02_sectors.sql` | COUNT DISTINCT | Companies by SIC sector |
| 03 | `03_top_filers.sql` | Aggregation | Top 20 most active CIKs |
| 04 | `04_top_standard_tags.sql` | JOIN with partial-index hint | Most-used standard tags |
| 05 | `05_revenue_10k.sql` | Multi-table JOIN + percentile | Revenue distribution by year |
| 06 | `06_missing_net_income.sql` | Anti-join (NOT EXISTS) | 10-Ks with no net income tag |
| 07 | `07_revenue_yoy.sql` | ROW_NUMBER dedup + LAG | YoY revenue growth |
| 08 | `08_revenue_3yr_rolling.sql` | Window frame (ROWS BETWEEN) | 3-year rolling revenue |
| 09 | `09_top_by_sector.sql` | RANK PARTITION BY | Top 5 per sector-year |
| 10 | `10_margin_compression.sql` | Multi-tag FILTER pivot + LAG | Gross margin compression |
| 11 | `11_restatements.sql` | Self-join | Original vs amended 10-K pairs |
| 12 | `12_top_expenses_lateral.sql` | LATERAL JOIN | Top 3 expenses per filing |
| 13 | `13_hhi_concentration.sql` | Two-level aggregation | Herfindahl by sector |
| 14 | `14_etr_dispersion.sql` | PERCENTILE_CONT | Effective tax rate spread |
| 15 | `15_cash_conversion.sql` | Multi-year ratio | CFO / Net Income |
| 16 | `16_pivot_income_statement.sql` | FILTER aggregation | Wide income-statement table |
| 17 | `17_fcf_margin.sql` | Multi-tag pivot | FCF / Revenue ranking |
| 18 | `18_filing_lag.sql` | Date arithmetic + percentile | Days from period end to filing |
| 19 | `19_spac_lifecycle.sql` | Aggregation with date math | SPACs that filed briefly |
| 20 | `20_top5_share_shift.sql` | Nested aggregation, self-comparison | Concentration trend 2021→2024 |

## Reproduction

### Prerequisites

- macOS or Linux
- Homebrew (macOS) or apt (Linux)
- ~12 GB free disk for `data/`
- ~80 minutes wall-clock for the full load

### Setup

```bash
# 1. Install PostgreSQL 16
brew install postgresql@16
brew services start postgresql@16

# 2. Create the database
createdb edgar

# 3. Create the conda environment
conda env create -f environment.yml
conda activate edgar

# 4. Configure the connection
echo "DATABASE_URL=postgresql:///edgar" > .env

# 5. Apply the schema
psql edgar -f schema.sql
```

### Load

```bash
# Download all 20 quarters (10-15 minutes on a fast connection)
python -m src.fetch --start 2021q1 --end 2025q4

# Load all 20 quarters into Postgres (60-80 minutes)
python -m src.load --start 2021q1 --end 2025q4 2>&1 | tee data/load.log

# Update planner statistics
psql edgar -c "ANALYZE;"
```

### Verify

```bash
psql edgar -c "
SELECT 'sub' AS t, COUNT(*) FROM sub UNION ALL
SELECT 'tag', COUNT(*) FROM tag UNION ALL
SELECT 'num', COUNT(*) FROM num UNION ALL
SELECT 'pre', COUNT(*) FROM pre
ORDER BY t;
"
```

Expected counts within ±0.5% of:

```
 t   |  count
-----+----------
 num | 68349478
 pre | 15719411
 sub |   141401
 tag |  1743086
```

### Run queries

```bash
psql edgar -f queries/07_revenue_yoy.sql        # individual query
time psql edgar -f queries/04_top_standard_tags.sql   # timed
```

## Limitations

1. **Tag normalization is not implemented.** Cross-company analysis is restricted to standard taxonomy concepts (`custom = 0`); custom tags are ignored. A production system would require explicit custom-to-standard mapping for ~94% of tag rows.

2. **No segment-level analysis.** Queries filter `segments = ''` to restrict to consolidated entity facts. Segment-level revenue, profitability, and geography analytics would require parsing the semicolon-separated `segments` field.

3. **No restatement-aware historical analysis.** The most-recently-filed value wins per `(cik, fiscal_year)`. This is correct for current-state analysis but discards restatement history. A separate query layer would be needed to study restatement magnitudes and frequencies.

4. **No equity market data.** This is a financial-statement project, not a trading or valuation project. Market cap, P/E, share counts for valuation come from CRSP/Compustat, not EDGAR.

5. **Foreign issuers underrepresented.** EDGAR's Financial Statement Data Sets are dominated by US domestic filers. Foreign private issuers (20-F) are included but in fewer numbers; meaningful foreign-vs-domestic comparisons require careful filtering.

6. **Filing-date cutoff.** Data through 2025q4 filing dates. 2025 fiscal-year-end 10-Ks filed in 2026q1 are not yet included.

## License & data source

SEC EDGAR Financial Statement Data Sets are public domain (SEC). Code in this repository is MIT-licensed. SEC's bulk-data terms of use require a descriptive User-Agent header on all programmatic requests; `src/fetch.py` requires the user to set this in the `USER_AGENT` constant before running.

## Contact

Built by Ilya Sharif. github.com/tangentjet-33