#!/usr/bin/env python3
"""Build the aircraft database that Overhead reads.

Downloads the FAA's public aircraft registry, joins MASTER.txt with
ACFTREF.txt and writes a small SQLite file keyed by ICAO hex code to

    ~/Library/Application Support/Overhead/aircraft.db

Usage:
    python3 build_db.py                 download the latest file and build
    python3 build_db.py --zip FILE      build from a zip you already have
    python3 build_db.py --out FILE      write the database somewhere else

The FAA refreshes the file every night. Re-run this whenever you want
fresh data; Overhead picks up the new file without a restart.
Street addresses are never stored.
"""

import argparse
import csv
import io
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile

URL = "https://registry.faa.gov/database/ReleasableAircraft.zip"
DEFAULT_OUT = os.path.expanduser("~/Library/Application Support/Overhead/aircraft.db")

# The FAA server refuses requests that do not look like a browser.
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"
)

REGISTRANT_TYPES = {
    "1": "Individual",
    "2": "Partnership",
    "3": "Corporation",
    "4": "Co-owned",
    "5": "Government",
    "7": "LLC",
    "8": "Non-citizen corporation",
    "9": "Non-citizen co-owned",
}


def download(dest):
    req = urllib.request.Request(URL, headers={"User-Agent": USER_AGENT})
    print("Downloading", URL)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp, open(dest, "wb") as out:
            total = int(resp.headers.get("Content-Length") or 0)
            done = 0
            last = 0
            while True:
                chunk = resp.read(1 << 20)
                if not chunk:
                    break
                out.write(chunk)
                done += len(chunk)
                if time.time() - last > 1:
                    last = time.time()
                    if total:
                        print("  %d / %d MB" % (done >> 20, total >> 20))
                    else:
                        print("  %d MB" % (done >> 20))
    except urllib.error.URLError as e:
        # Python installed from python.org on a Mac often has no root
        # certificates, so HTTPS fails. curl uses the system ones.
        if not shutil.which("curl"):
            sys.exit("Download failed: %s" % e)
        print("Python could not connect (%s); using curl instead" % e.reason)
        result = subprocess.run(
            ["curl", "-fL", "--retry", "3", "-A", USER_AGENT, "-o", dest, URL]
        )
        if result.returncode != 0:
            sys.exit("Download failed (curl exit code %d)." % result.returncode)
    if not zipfile.is_zipfile(dest):
        sys.exit("Download failed: the FAA did not return a zip file. Try again later.")


def read_table(zf, name):
    """Yield each row of a file in the zip as a dict keyed by column name.

    The FAA files start with a byte order mark, pad every field with spaces
    and end every row with a trailing comma (an extra, unnamed column).
    """
    with zf.open(name) as raw:
        text = io.TextIOWrapper(raw, encoding="utf-8-sig", errors="replace", newline="")
        reader = csv.reader(text)
        header = [h.strip() for h in next(reader)]
        for row in reader:
            if not row:
                continue
            yield {h: v.strip() for h, v in zip(header, row) if h}


def need(row, name, *columns):
    missing = [c for c in columns if c not in row]
    if missing:
        sys.exit(
            "%s is missing expected columns: %s\nColumns found: %s"
            % (name, ", ".join(missing), ", ".join(row.keys()))
        )


def build(zip_path, out_path):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    tmp_db = out_path + ".new"
    if os.path.exists(tmp_db):
        os.remove(tmp_db)

    db = sqlite3.connect(tmp_db)
    db.executescript(
        """
        CREATE TABLE aircraft (
            mode_s_hex TEXT PRIMARY KEY,
            n_number TEXT NOT NULL,
            owner TEXT NOT NULL,
            registrant_type TEXT NOT NULL,
            city TEXT NOT NULL,
            state TEXT NOT NULL,
            manufacturer TEXT NOT NULL,
            model TEXT NOT NULL,
            year TEXT NOT NULL
        ) WITHOUT ROWID;
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
        """
    )

    with zipfile.ZipFile(zip_path) as zf:
        print("Reading ACFTREF.txt")
        models = {}
        checked = False
        for r in read_table(zf, "ACFTREF.txt"):
            if not checked:
                need(r, "ACFTREF.txt", "CODE", "MFR", "MODEL")
                checked = True
            models[r["CODE"]] = (r["MFR"], r["MODEL"])

        print("Reading MASTER.txt")
        rows = []
        count = 0
        skipped = 0
        checked = False
        insert = "INSERT OR REPLACE INTO aircraft VALUES (?,?,?,?,?,?,?,?,?)"
        for r in read_table(zf, "MASTER.txt"):
            if not checked:
                need(
                    r, "MASTER.txt", "N-NUMBER", "MFR MDL CODE", "YEAR MFR",
                    "TYPE REGISTRANT", "NAME", "CITY", "STATE", "MODE S CODE HEX",
                )
                checked = True
            hex_code = r["MODE S CODE HEX"].upper()
            if not hex_code:
                skipped += 1
                continue
            mfr, model = models.get(r["MFR MDL CODE"], ("", ""))
            rows.append((
                hex_code,
                "N" + r["N-NUMBER"],
                r["NAME"],
                REGISTRANT_TYPES.get(r["TYPE REGISTRANT"], ""),
                r["CITY"],
                r["STATE"],
                mfr,
                model,
                r["YEAR MFR"],
            ))
            if len(rows) >= 20000:
                db.executemany(insert, rows)
                count += len(rows)
                rows = []
        db.executemany(insert, rows)
        count += len(rows)

    built = time.strftime("%Y-%m-%d")
    db.execute("INSERT INTO meta VALUES ('built', ?)", (built,))
    db.execute("INSERT INTO meta VALUES ('count', ?)", (str(count),))
    db.commit()
    stored = db.execute("SELECT COUNT(*) FROM aircraft").fetchone()[0]
    db.close()
    os.replace(tmp_db, out_path)
    print("Wrote %d aircraft to %s" % (stored, out_path))
    if skipped:
        print("Skipped %d rows with no Mode S code" % skipped)


def main():
    parser = argparse.ArgumentParser(description="Build Overhead's FAA aircraft database.")
    parser.add_argument("--zip", help="use this ReleasableAircraft.zip instead of downloading")
    parser.add_argument("--out", default=DEFAULT_OUT, help="where to write aircraft.db")
    args = parser.parse_args()

    if args.zip:
        if not zipfile.is_zipfile(args.zip):
            sys.exit("%s is not a zip file." % args.zip)
        build(args.zip, args.out)
        return

    with tempfile.TemporaryDirectory() as tmp:
        zip_path = os.path.join(tmp, "ReleasableAircraft.zip")
        download(zip_path)
        build(zip_path, args.out)


if __name__ == "__main__":
    main()
