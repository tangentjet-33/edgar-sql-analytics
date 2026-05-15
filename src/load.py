"""
load.py — Load SEC EDGAR quarterly text files into PostgreSQL.

Loads each quarter's sub.txt, tag.txt, num.txt, pre.txt into the
corresponding tables. Idempotent per quarter: re-running on the same
quarter deletes prior rows for that quarter's filings and reloads.

Usage:
    python -m src.load --start 2021q1 --end 2025q4
    python -m src.load --quarters 2024q1 2024q2
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path
from typing import Iterator

import pandas as pd
import psycopg
from dotenv import load_dotenv
from tqdm import tqdm

from src.fetch import (
    DATA_DIR,
    is_already_extracted,
    parse_quarter,
    quarter_paths,
    quarters_in_range,
)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# 100k rows of num.txt is ~50MB in pandas. Adjust if memory is tight.
CHUNK_SIZE = 100_000

# Fallback DSN if DATABASE_URL is not set in environment.
DEFAULT_DSN = "postgresql:///edgar"

# Column orders MUST match schema.sql so COPY FROM works without
# explicit column listing in the SQL.
SUB_COLUMNS = [
    "adsh", "cik", "name", "sic",
    "countryba", "stprba", "cityba", "zipba", "bas1", "bas2", "baph",
    "countryma", "stprma", "cityma", "zipma", "mas1", "mas2",
    "countryinc", "stprinc", "ein", "former", "changed",
    "afs", "wksi", "fye", "form", "period", "fy", "fp",
    "filed", "accepted", "prevrpt", "detail", "instance", "nciks", "aciks",
]
TAG_COLUMNS = ["tag", "version", "custom", "abstract", "datatype",
               "iord", "crdr", "tlabel", "doc"]
NUM_COLUMNS = ["adsh", "tag", "version", "ddate", "qtrs", "uom",
               "segments", "coreg", "value", "footnote"]
PRE_COLUMNS = ["adsh", "report", "line", "stmt", "inpth", "rfile",
               "tag", "version", "plabel", "negating"]


# ---------------------------------------------------------------------------
# Connection
# ---------------------------------------------------------------------------

def get_dsn() -> str:
    """
    Return the Postgres connection string.

    Loads .env if present, reads DATABASE_URL from environment,
    falls back to DEFAULT_DSN.
    """
    load_dotenv()
    return os.environ.get("DATABASE_URL", DEFAULT_DSN)


# ---------------------------------------------------------------------------
# Helpers: read source files
# ---------------------------------------------------------------------------

def read_chunks(path: Path, columns: list[str]) -> Iterator[pd.DataFrame]:
    """
    Yield chunks of a tab-separated SEC file as DataFrames.

    All columns read as strings; type casting happens in clean_* functions.
    Treats both empty fields and literal '\\N' as NaN.
    """
    reader = pd.read_csv(
        path,
        sep="\t",
        dtype=str,
        keep_default_na=True,
        na_values=["", "\\N"],          # both empty and SEC's \N sentinel
        usecols=columns,
        chunksize=CHUNK_SIZE,
        encoding="utf-8",
        encoding_errors="replace",
        on_bad_lines="warn",
    )
    yield from reader


# ---------------------------------------------------------------------------
# Helpers: data cleaning
# ---------------------------------------------------------------------------

def clean_sub(df: pd.DataFrame) -> pd.DataFrame:
    """Clean and type-cast a sub.txt DataFrame for insertion."""

    # Dates from YYYYMMDD strings to date objects; bad/missing -> NaT
    for col in ("changed", "period", "filed"):
        df[col] = pd.to_datetime(df[col], format="%Y%m%d", errors="coerce")

    # Timestamp from "YYYY-MM-DD HH:MM:SS.S"
    df["accepted"] = pd.to_datetime(df["accepted"], errors="coerce")

    # Integer columns. Use nullable Int64 so NaN stays NaN (not 0).
    for col in ("cik", "sic", "fy", "nciks"):
        df[col] = pd.to_numeric(df[col], errors="coerce").astype("Int64")

    # Boolean-flag columns (NOT NULL per schema, so no Int64 needed)
    for col in ("wksi", "prevrpt", "detail"):
        df[col] = pd.to_numeric(df[col], errors="coerce").astype("Int8")

    # Convert all remaining pandas NaN/NaT to Python None for psycopg
    df = df.astype(object).where(df.notna(), None)

    return df[SUB_COLUMNS]


def clean_tag(df: pd.DataFrame) -> pd.DataFrame:
    """Clean a tag.txt DataFrame for insertion."""

    for col in ("custom", "abstract"):
        df[col] = pd.to_numeric(df[col], errors="coerce").astype("Int8")

    # Drop rows where any PK column is NULL
    pk_cols = ["tag", "version"]
    before = len(df)
    df = df.dropna(subset=pk_cols).copy()
    dropped = before - len(df)
    if dropped:
        logging.warning("clean_tag: dropped %d rows with NULL in PK columns", dropped)

    df = df.astype(object).where(df.notna(), None)
    return df[TAG_COLUMNS]


def clean_num(df: pd.DataFrame) -> pd.DataFrame:
    """
    Clean a num.txt DataFrame for insertion.
    - Parse ddate; drop rows with unparseable or NaN PK columns.
    - Coerce qtrs to Int16.
    - Fill NULL segments and coreg with '' (required for PK).
    Cross-chunk deduplication happens in upsert_num via ON CONFLICT.
    """

    df["ddate"] = pd.to_datetime(df["ddate"], format="%Y%m%d", errors="coerce")

    df["qtrs"] = pd.to_numeric(df["qtrs"], errors="coerce").astype("Int16")
    df["value"] = pd.to_numeric(df["value"], errors="coerce")

    pk_cols = ["adsh", "tag", "version", "ddate", "qtrs", "uom"]
    before = len(df)
    df = df.dropna(subset=pk_cols).copy()
    dropped = before - len(df)
    if dropped:
        logging.warning("clean_num: dropped %d rows with NULL in PK columns", dropped)

    df["segments"] = df["segments"].fillna("")
    df["coreg"] = df["coreg"].fillna("")

    df = df.astype(object).where(df.notna(), None)
    return df[NUM_COLUMNS]


def clean_pre(df: pd.DataFrame) -> pd.DataFrame:
    """Clean a pre.txt DataFrame for insertion."""

    for col in ("report", "line"):
        df[col] = pd.to_numeric(df[col], errors="coerce").astype("Int16")
    for col in ("inpth", "negating"):
        df[col] = pd.to_numeric(df[col], errors="coerce").astype("Int8")

    pk_cols = ["adsh", "report", "line", "tag", "version"]
    before = len(df)
    df = df.dropna(subset=pk_cols).copy()      # <-- .copy() added
    dropped = before - len(df)
    if dropped:
        logging.warning("clean_pre: dropped %d rows with NULL in PK columns", dropped)

    df = df.astype(object).where(df.notna(), None)
    return df[PRE_COLUMNS]

# ---------------------------------------------------------------------------
# Helpers: COPY into Postgres
# ---------------------------------------------------------------------------

def copy_dataframe(
    conn: psycopg.Connection,
    df: pd.DataFrame,
    table: str,
    columns: list[str],
) -> int:
    """
    Bulk-insert a DataFrame into the given table using Postgres COPY.
    Returns the number of rows inserted.
    """
    if df.empty:
        return 0

    cols_sql = ", ".join(columns)
    copy_sql = f"COPY {table} ({cols_sql}) FROM STDIN"

    with conn.cursor() as cur:
        with cur.copy(copy_sql) as copy:
            for row in df.itertuples(index=False, name=None):
                copy.write_row(row)

    return len(df)


def upsert_tags(conn: psycopg.Connection, df: pd.DataFrame) -> int:
    """
    Insert tag rows with ON CONFLICT (tag, version) DO NOTHING.
    Uses TEMP TABLE + INSERT ... SELECT because COPY can't do ON CONFLICT.
    Returns rows actually inserted (excluding conflicts).
    """
    if df.empty:
        return 0

    cols_sql = ", ".join(TAG_COLUMNS)

    with conn.cursor() as cur:
        # Defensive: drop any leftover temp table from a previously
        # rolled-back load. ON COMMIT DROP fires on commit only.
        cur.execute("DROP TABLE IF EXISTS tag_stage")

        cur.execute(
            "CREATE TEMP TABLE tag_stage "
            "(LIKE tag INCLUDING DEFAULTS) "
            "ON COMMIT DROP"
        )

        with cur.copy(f"COPY tag_stage ({cols_sql}) FROM STDIN") as copy:
            for row in df.itertuples(index=False, name=None):
                copy.write_row(row)

        cur.execute(
            f"INSERT INTO tag ({cols_sql}) "
            f"SELECT {cols_sql} FROM tag_stage "
            f"ON CONFLICT (tag, version) DO NOTHING"
        )
        return cur.rowcount
    
def upsert_num(conn: psycopg.Connection, df: pd.DataFrame) -> int:
    """
    Insert num rows with ON CONFLICT on full PK DO NOTHING.
    Uses TEMP TABLE + INSERT ... SELECT to handle SEC's intra-file duplicates
    (observed in derivative/segment filings with malformed dimensional tags).
    Returns rows actually inserted (excluding conflicts).
    """
    if df.empty:
        return 0

    cols_sql = ", ".join(NUM_COLUMNS)

    with conn.cursor() as cur:
        cur.execute("DROP TABLE IF EXISTS num_stage")
        cur.execute(
            "CREATE TEMP TABLE num_stage "
            "(LIKE num INCLUDING DEFAULTS) "
            "ON COMMIT DROP"
        )

        with cur.copy(f"COPY num_stage ({cols_sql}) FROM STDIN") as copy:
            for row in df.itertuples(index=False, name=None):
                copy.write_row(row)

        cur.execute(
            f"INSERT INTO num ({cols_sql}) "
            f"SELECT {cols_sql} FROM num_stage "
            f"ON CONFLICT (adsh, tag, version, ddate, qtrs, uom, segments, coreg) "
            f"DO NOTHING"
        )
        return cur.rowcount

# ---------------------------------------------------------------------------
# Per-quarter loading
# ---------------------------------------------------------------------------

def delete_quarter_adsh(conn: psycopg.Connection, adsh_list: list[str]) -> None:
    """
    Delete rows from sub, num, pre where adsh is in adsh_list.
    Tag is NOT touched — tags are upserted, not deleted.
    """
    if not adsh_list:
        return

    with conn.cursor() as cur:
        # Order matters only if FKs are enforced — they aren't, but
        # deleting children before parents is good habit.
        cur.execute("DELETE FROM num WHERE adsh = ANY(%s)", (adsh_list,))
        cur.execute("DELETE FROM pre WHERE adsh = ANY(%s)", (adsh_list,))
        cur.execute("DELETE FROM sub WHERE adsh = ANY(%s)", (adsh_list,))

def load_quarter(conn: psycopg.Connection, quarter: str) -> None:
    """
    Load one quarter's four files into Postgres in a single transaction.
    Order: collect adsh -> delete -> tag (upsert) -> sub -> num (upsert) -> pre.
    """
    _, extract_dir = quarter_paths(quarter)

    if not is_already_extracted(extract_dir):
        raise FileNotFoundError(
            f"{quarter} not extracted. Run fetch.py first."
        )

    sub_path = extract_dir / "sub.txt"
    tag_path = extract_dir / "tag.txt"
    num_path = extract_dir / "num.txt"
    pre_path = extract_dir / "pre.txt"

    logging.info("Loading %s", quarter)

    # Step 1: collect the adsh values for this quarter so we know what to delete.
    adsh_list = (
        pd.read_csv(sub_path, sep="\t", usecols=["adsh"], dtype=str)["adsh"]
        .tolist()
    )
    logging.info("  %s: %d filings", quarter, len(adsh_list))

    # Step 2: clean slate for this quarter's filings
    delete_quarter_adsh(conn, adsh_list)

    # Step 3: tags (upsert — shared across quarters)
    tag_total = 0
    for chunk in read_chunks(tag_path, TAG_COLUMNS):
        clean = clean_tag(chunk)
        tag_total += upsert_tags(conn, clean)
    logging.info("  %s tag: %d new rows", quarter, tag_total)

    # Step 4: sub
    sub_total = 0
    for chunk in read_chunks(sub_path, SUB_COLUMNS):
        clean = clean_sub(chunk)
        sub_total += copy_dataframe(conn, clean, "sub", SUB_COLUMNS)
    logging.info("  %s sub: %d rows", quarter, sub_total)

    # Step 5: num (upsert — handles SEC's intra-file duplicate facts)
    num_total = 0
    for chunk in read_chunks(num_path, NUM_COLUMNS):
        clean = clean_num(chunk)
        num_total += upsert_num(conn, clean)
    logging.info("  %s num: %d rows", quarter, num_total)

    # Step 6: pre
    pre_total = 0
    for chunk in read_chunks(pre_path, PRE_COLUMNS):
        clean = clean_pre(chunk)
        pre_total += copy_dataframe(conn, clean, "pre", PRE_COLUMNS)
    logging.info("  %s pre: %d rows", quarter, pre_total)

    conn.commit()
    logging.info("  %s: committed", quarter)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def setup_logging() -> None:
    """Configure root logger: INFO level, timestamped, to stdout."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        stream=sys.stdout,
    )


def main() -> int:
    """
    Parse CLI args, load each quarter into Postgres.
    Returns 0 on full success, 1 if any quarter fails.
    """
    setup_logging()

    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--quarters", nargs="+", metavar="QUARTER",
        help="Specific quarters to load, e.g. 2024q1 2024q2",
    )
    group.add_argument(
        "--start", help="Start quarter for range, e.g. 2021q1",
    )
    parser.add_argument(
        "--end", help="End quarter (required with --start)",
    )
    args = parser.parse_args()

    if args.start and not args.end:
        parser.error("--start requires --end")

    if args.quarters:
        quarters = args.quarters
        for q in quarters:
            parse_quarter(q)  # validate format
    else:
        quarters = quarters_in_range(args.start, args.end)

    logging.info("Loading %d quarter(s) into Postgres", len(quarters))

    conn = psycopg.connect(get_dsn())
    failures: list[str] = []
    try:
        for quarter in quarters:
            try:
                load_quarter(conn, quarter)
            except Exception as exc:
                logging.error("Failed %s: %s", quarter, exc)
                conn.rollback()
                failures.append(quarter)
    finally:
        conn.close()

    if failures:
        logging.error("Done with %d failure(s): %s", len(failures), ", ".join(failures))
        return 1
    logging.info("Done. All %d quarter(s) loaded.", len(quarters))
    return 0


if __name__ == "__main__":
    sys.exit(main())