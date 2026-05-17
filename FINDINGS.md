# Findings from the SEC EDGAR Financial Statement Data Sets

Empirical findings from 5 years (20 quarters, 2021q1–2025q4) of SEC EDGAR
Financial Statement & Notes Data Sets loaded into PostgreSQL. Total scope:
141K filings, 68M numeric facts, 16M presentation lines, 1.7M tag-version
pairs.

Each finding references the SQL file in `queries/` that produced it.
Numbers are from the loaded data; any limitations are documented in
`README.md`.

---

## 1. The data is dominated by amendments, restatements, and comparative-year leakage — not by primary filings.

**Query: `07_revenue_yoy.sql`**

Apple's FY2024 revenue was reported in over 6 distinct rows in `num`
(original 10-K, amendments, comparative prior-year data in the FY2025
10-K, and segment slices). A naive `SUM(value) GROUP BY (cik, fiscal_year)`
double-counts and produced $782B — twice the real $391B.

The correct pattern is `ROW_NUMBER() OVER (PARTITION BY cik, fiscal_year
ORDER BY filed DESC, adsh DESC)` to pick the most-recently-filed value
per (company, fiscal year). Without this deduplication, any cross-company
financial analytic over EDGAR bulk data is wrong.

---

## 2. 94.5% of XBRL tags are filer-created custom extensions, not standard concepts.

**Query: `04_top_standard_tags.sql`**

Of 1.7M `(tag, version)` rows loaded, only 9,708 (5.5%) are standard
us-gaap or ifrs taxonomy concepts. The remaining 169,203 rows are
filer-specific custom extensions where `version` is the filing's
accession number.

Implication: any cross-company comparison must restrict to the standard
taxonomy or build a custom-to-standard mapping. Tag normalization is
the bottleneck for any peer-set analytical workflow at EDGAR scale.

---

## 3. The dominant revenue tag is `RevenueFromContractWithCustomerExcludingAssessedTax`, not the legacy `Revenues`.

**Query: `04_top_standard_tags.sql`, `05_revenue_10k.sql`**

Post-ASC 606 adoption (2018), filers progressively migrated from
`Revenues` (46K filings) to `RevenueFromContractWithCustomerExcludingAssessedTax`
(55K filings). Both are still used; any revenue query must `IN ()` both
or risk a 45% undercount on a randomly selected modern filer.

---

## 4. Sector revenue patterns show real economic cycles, not just data noise.

**Query: `05_revenue_10k.sql`, `09_top_by_sector.sql`**

Median 10-K revenue for non-trivial reporters: $447M (FY19), $384M
(FY20, COVID compression), $388M (FY21), $377M (FY22), $471M (FY23),
$490M (FY24). The dip-and-recover signal is real and reflects the
COVID-19 demand shock followed by post-pandemic normalization.

Sector-specific:
- **Oil & Gas (SIC 1311)**: revenue peaked in 2022 with Occidental at
  $36.6B, retracted to $26.7B by 2024 — the energy-price spike-and-cool cycle.
- **Pharma (SIC 2834)**: Pfizer FY22 revenue $101B (COVID vaccine
  windfall) declined to $59-63B by FY23-24 as vaccine demand normalized.

---

## 5. 2024 saw broad gross margin compression in commodity cyclicals and aerospace.

**Query: `10_margin_compression.sql`**

The top 20 most margin-compressed firms in 2024 (vs 2023) include:
- **Arcadium Lithium**: -32pp (lithium price collapse)
- **Spirit AeroSystems**: -25pp (Boeing 737 MAX issues, door-plug incident)
- **Boeing**: -13pp (production halts, machinist strike, 777X delays)
- **Albemarle**: -11pp (lithium, same story as Arcadium)
- **PBF Energy, PBF Holding, CVR Energy**: -7 to -11pp (refining margin collapse)
- **Intel**: -7pp (foundry costs, AMD/TSMC share gains)

The query identifies real-world industry inflection points from public
SEC data alone, without any external news source.

---

## 6. Effective tax rate dispersion is highest in utilities, pharma, and software-services.

**Query: `14_etr_dispersion.sql`**

Sectors with the widest interquartile range in 2024 effective tax rate:
- **SIC 2836 (Biologicals)**: IQR 24.3% — NOL carryforwards, IP-driven
  income shifting
- **SIC 4922 (Natural Gas Transmission)**: IQR 24.2% — MLP structures,
  bonus depreciation
- **SIC 4931 (Electric Utilities)**: IQR 21% with **median ETR 5.1%** —
  bonus depreciation and tax credits make this sector famously
  low-effective-rate
- **SIC 2834 (Pharma)**: IQR 20.7%, median 15.6% — transfer pricing,
  international income mix

High ETR dispersion within a sector signals that peer-based valuation
multiples are unreliable without tax-structure due diligence.

---

## 7. The top-of-list cash-conversion businesses are capital-intensive and depreciation-heavy, not high-margin tech.

**Query: `15_cash_conversion.sql`**

Companies with CFO consistently exceeding 3× net income (4-year average):
- **Equinix (4.08x)** and **Digital Realty (3.16x)**: data center REITs,
  massive PP&E depreciation
- **REITs broadly**: Realty Income, RLJ Lodging, Invitation Homes —
  the property-depreciation accounting story
- **Captive finance subs**: Honda Finance, Toyota Credit, GM Financial,
  Ally — accrued interest income recognized faster than cash
- **Airlines**: American Airlines, Alaska Air — aircraft depreciation

Pure-tech megacaps (Microsoft, Apple, Alphabet) are NOT in the top 25
— their CFO tracks net income closely because PP&E intensity is low.

---

## 8. FCF-margin leaders are toll-booth software-services businesses.

**Query: `17_fcf_margin.sql`**

Among companies with $10B+ revenue, 2024 FCF / Revenue ratios:
- **Visa: 52%**, **Mastercard: 51%** — payment networks
- **NVIDIA: 44%** — fabless semis, gen-AI boom
- **S&P Global: 39%** — ratings and data subscription
- **Adobe: 37%**, **Intuit: 29%**, **ServiceNow: 31%** — SaaS
- **Meta: 33%**, **Microsoft: 30%** — despite $37B and $44B AI-driven
  capex respectively

The list maps cleanly to "subscription / network / IP-light revenue"
business models. Capital-light cash-machine businesses are
identifiable directly from EDGAR.

---

## 9. Filing compliance varies dramatically by accelerated-filer status.

**Query: `18_filing_lag.sql`**

Median days from period end to 10-K filing, by filer status:
- **Large Accelerated Filers (LAF)**: median 54 days, P95 = 60 days
  (the SEC's 60-day rule). 3-8 late filings per year out of ~2,100.
- **Accelerated Filers (ACC)**: median 67 days, P95 = 75-90 days
  (75-day rule). 15-26 late per year.
- **Non-Accelerated Filers (NON)**: median 86-89 days, P95 = 110-158
  days, **800-1,090 late filings per year out of ~3,000** (90-day rule
  violations).

Non-accelerated filer compliance is materially weaker. Late filings
are a credit/distress signal; they appear in roughly 30% of
non-accelerated filings.

---

## 10. The SPAC wave was data-engineering reality, not a metaphor.

**Query: `02_sectors.sql`, `19_spac_lifecycle.sql`**

SIC 6770 ("Blank Checks" / SPACs) contains 1,230 distinct companies
across the 5-year window — more than any other SIC code — but only
8,881 total filings (7.2 filings/CIK average). Most lived 600-720
days from first filing to last filing, then either merged or
dissolved.

Notable SPAC graduates traceable in the data: WeWork (CIK 1813756)
went through 17 filings across 8 form types in 502 days during its
SPAC-merger cleanup.

---

## 11. Sector concentration is broadly increasing.

**Query: `13_hhi_concentration.sql`, `20_top5_share_shift.sql`**

2024 HHI values reveal:
- **SIC 5961 (Catalog/Mail-Order, $750B revenue, HHI 7,272)**:
  Amazon-dominated.
- **SIC 4812 (Wireless, $85B, HHI 9,123)**: Verizon + T-Mobile + AT&T.
- **SIC 3760 (Missiles, $73B, HHI 9,494)**: Lockheed, Northrop, Raytheon.
- **SIC 7990 (Amusement, $106B, HHI 7,472)**: Disney-dominated.

Top-5 sector share changed 2021→2024:
- Gaining concentration: Diagnostic Substances (+14pp), Natural Gas
  Transmission (+11pp), Telecom Equipment (+9pp).
- Losing concentration: Industrial Instruments (-12pp), Finance
  Services (-7pp), Surgical Instruments (-7pp).
- Tech sectors (semis, software): all gaining +4-5pp.

---

## Data quality findings (internal validation)

These are not insights about the U.S. economy; they are insights about
the dataset itself, documented in `README.md` limitations:

- **24 filings** across 68M rows had unparseable "year of 29XX" dates
  from filer typos. Dropped at clean time.
- **2 NULL tag rows in pre**, **4 NULL tag rows in num**, **~5-10 NULL
  PK rows per quarter** across all tables — all dropped, all logged
  during load.
- **1 filer (CIK 1918712, a fund manager) consistently emits PK
  duplicates** in derivatives-related segment rows due to malformed
  XBRL dimensions. Handled via ON CONFLICT DO NOTHING upsert.
- **SEC's documented NOT NULL** was empirically wrong on `sub.period`,
  `pre.stmt`, and `pre.plabel`. Schema relaxed for those three columns
  after scan.
- **Taxonomy version churn**: the same logical concept (e.g., "Assets")
  exists 5 times across us-gaap/2022, 2023, 2024, ifrs/2022, 2023.
  Cross-period queries must aggregate across versions.