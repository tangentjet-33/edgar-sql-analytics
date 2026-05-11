# SEC EDGAR SQL Analytics

Production-grade SQL analytics over 5 years (20 quarters) of SEC EDGAR
Financial Statement & Notes Data Sets, loaded into PostgreSQL.

## Status

🚧 In active development.

## Stack

- PostgreSQL 16 (local, Homebrew)
- Python 3.11 (conda env `edgar`) for ingestion and validation
- SQL-first analytics; optional Jupyter notebook for visualization

## Structure

- `schema.sql` — table definitions and indexes
- `src/` — Python ingestion and utilities
  - `fetch.py` — downloads quarterly EDGAR ZIPs, validates, unzips
  - `load.py` — schema-validated, idempotent loader into Postgres
- `queries/` — analytical SQL files (15–20)
- `notebooks/` — optional visualization layer
- `data/` — raw downloads (gitignored)
- `outputs/` — generated CSVs / plots (gitignored)

## Reproduction

_To be filled in once ingestion is stable._

## Limitations

_Honest documentation of dataset quirks, restatement handling, tag
inconsistency, and known coverage gaps will live here._