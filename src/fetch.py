"""
fetch.py — Download SEC EDGAR Financial Statement Data Sets quarterly ZIPs.

Fetches quarterly ZIP archives from SEC's bulk data endpoint, verifies each
download is a valid ZIP, and extracts the contents into per-quarter folders
under data/. Idempotent: skips quarters already downloaded and extracted.

Usage:
    python -m src.fetch --start 2021q1 --end 2025q4
"""

from __future__ import annotations

import argparse
import logging
import sys
import zipfile
from pathlib import Path

import requests
from tqdm import tqdm


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SEC_BASE_URL = "https://www.sec.gov/files/dera/data/financial-statement-data-sets"

# SEC requires a descriptive User-Agent identifying the requester.
# Format: "Name email@domain" — they block generic strings and python-requests/*.
USER_AGENT = "Ilya Sharif ilya.sh2809@gmail.com"

# Project paths. fetch.py lives in src/, so project root is one level up.
PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = PROJECT_ROOT / "data"

REQUEST_TIMEOUT = 60  # seconds
CHUNK_SIZE = 1024 * 1024  # 1 MB streaming chunks


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def parse_quarter(label: str) -> tuple[int, int]:
    """
    Parse a quarter label like '2024q1' into (year, quarter).

    Raises ValueError if the format is invalid or quarter is not in 1..4.
    """
    label = label.strip().lower()
    if len(label) != 6 or label[4] != "q":
        raise ValueError(f"Invalid quarter label: {label!r} (expected e.g. '2024q1')")
    try:
        year = int(label[:4])
        quarter = int(label[5])
    except ValueError as exc:
        raise ValueError(f"Invalid quarter label: {label!r}") from exc
    if quarter not in (1, 2, 3, 4):
        raise ValueError(f"Quarter must be 1-4, got {quarter} in {label!r}")
    return year, quarter


def quarters_in_range(start: str, end: str) -> list[str]:
    """
    Return all quarter labels from start to end inclusive, in chronological order.

    Example: ('2021q1', '2021q4') -> ['2021q1', '2021q2', '2021q3', '2021q4']
    """
    start_year, start_q = parse_quarter(start)
    end_year, end_q = parse_quarter(end)

    # Encode each quarter as a single integer for easy ordered iteration.
    start_idx = start_year * 4 + (start_q - 1)
    end_idx = end_year * 4 + (end_q - 1)

    if end_idx < start_idx:
        raise ValueError(f"end ({end}) is before start ({start})")

    labels = []
    for idx in range(start_idx, end_idx + 1):
        year, q_zero_indexed = divmod(idx, 4)
        labels.append(f"{year}q{q_zero_indexed + 1}")
    return labels


def quarter_url(quarter: str) -> str:
    """Build the SEC download URL for a given quarter label (e.g. '2024q1')."""
    parse_quarter(quarter)  # validate
    return f"{SEC_BASE_URL}/{quarter}.zip"


def quarter_paths(quarter: str) -> tuple[Path, Path]:
    """
    Return (zip_path, extract_dir) for a given quarter.

    zip_path is where the downloaded ZIP is stored.
    extract_dir is the folder the ZIP is unpacked into.
    """
    parse_quarter(quarter)  # validate
    zip_path = DATA_DIR / f"{quarter}.zip"
    extract_dir = DATA_DIR / quarter
    return zip_path, extract_dir


def is_already_extracted(extract_dir: Path) -> bool:
    """
    Return True if extract_dir exists and contains all four core files
    (sub.txt, num.txt, tag.txt, pre.txt). Used for idempotency.
    """
    required = ("sub.txt", "num.txt", "tag.txt", "pre.txt")
    if not extract_dir.is_dir():
        return False
    return all((extract_dir / name).is_file() for name in required)


# ---------------------------------------------------------------------------
# Core operations
# ---------------------------------------------------------------------------

def download_zip(quarter: str) -> Path:
    """
    Download the ZIP for a given quarter to data/<quarter>.zip.

    Streams in chunks with a tqdm progress bar. Sends the required SEC
    User-Agent header. Raises requests.HTTPError on non-200 responses.
    Returns the path to the downloaded ZIP.

    Skips the download if the ZIP already exists on disk.
    """
    zip_path, _ = quarter_paths(quarter)

    if zip_path.exists():
        logging.info("ZIP already on disk, skipping download: %s", zip_path.name)
        return zip_path

    DATA_DIR.mkdir(parents=True, exist_ok=True)

    url = quarter_url(quarter)
    headers = {"User-Agent": USER_AGENT}

    logging.info("Downloading %s", url)

    # Stream to a temp path so an interrupted download doesn't leave a
    # half-written file that future runs would treat as complete.
    tmp_path = zip_path.with_suffix(".zip.part")

    with requests.get(url, headers=headers, stream=True, timeout=REQUEST_TIMEOUT) as response:
        response.raise_for_status()
        total = int(response.headers.get("Content-Length", 0))

        with open(tmp_path, "wb") as fh, tqdm(
            total=total,
            unit="B",
            unit_scale=True,
            unit_divisor=1024,
            desc=quarter,
        ) as bar:
            for chunk in response.iter_content(chunk_size=CHUNK_SIZE):
                if chunk:
                    fh.write(chunk)
                    bar.update(len(chunk))

    tmp_path.rename(zip_path)
    return zip_path


def verify_zip(zip_path: Path) -> None:
    """
    Verify the downloaded file is a valid, non-corrupt ZIP archive.

    Uses zipfile.ZipFile.testzip(). Raises zipfile.BadZipFile or a more
    specific error if the archive is corrupt.
    """
    with zipfile.ZipFile(zip_path) as zf:
        bad = zf.testzip()
        if bad is not None:
            raise zipfile.BadZipFile(f"Corrupt entry in {zip_path.name}: {bad}")


def extract_zip(zip_path: Path, extract_dir: Path) -> None:
    """
    Extract zip_path into extract_dir. Creates extract_dir if needed.
    Overwrites existing files in extract_dir.
    """
    extract_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as zf:
        zf.extractall(extract_dir)


def fetch_quarter(quarter: str) -> None:
    """
    Full pipeline for one quarter: download -> verify -> extract.

    Idempotent: if the quarter is already fully extracted (all four core
    files present), logs a skip message and returns without re-downloading.
    """
    _, extract_dir = quarter_paths(quarter)

    if is_already_extracted(extract_dir):
        logging.info("Already extracted, skipping: %s", quarter)
        return

    zip_path = download_zip(quarter)
    verify_zip(zip_path)
    extract_zip(zip_path, extract_dir)
    logging.info("Completed: %s", quarter)


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
    Parse CLI args (--start, --end), then fetch each quarter in the range.

    Returns 0 on full success, 1 if any quarter fails. Continues past
    individual quarter failures (logs and moves on); does not abort.
    """
    setup_logging()

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start", required=True, help="Start quarter, e.g. 2021q1")
    parser.add_argument("--end", required=True, help="End quarter, e.g. 2025q4")
    args = parser.parse_args()

    quarters = quarters_in_range(args.start, args.end)
    logging.info("Fetching %d quarters: %s to %s", len(quarters), args.start, args.end)

    failures: list[str] = []
    for quarter in quarters:
        try:
            fetch_quarter(quarter)
        except Exception as exc:
            logging.error("Failed: %s — %s", quarter, exc)
            failures.append(quarter)

    if failures:
        logging.error("Done with %d failure(s): %s", len(failures), ", ".join(failures))
        return 1
    logging.info("Done. All %d quarters fetched successfully.", len(quarters))
    return 0


if __name__ == "__main__":
    sys.exit(main())