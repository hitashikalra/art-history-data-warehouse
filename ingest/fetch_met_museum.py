"""
Pull open-access artwork records from the Met Museum Collection API and
write them to a CSV ready for loading into Snowflake.

The API has two endpoints we use:
  /objects              -> every object ID in the collection
  /objects/{objectID}   -> full record for one object

The API asks clients to stay under 80 requests/second, so requests run in
a small thread pool with a simple rate limiter. Failed IDs are retried and
then logged, not silently dropped.

Usage:
  python ingest/fetch_met_museum.py --out data/artworks.csv --limit 100000
"""

import argparse
import csv
import logging
import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests

BASE_URL = "https://collectionapi.metmuseum.org/public/collection/v1"
MAX_REQ_PER_SEC = 60  # stay under the API's 80/sec ceiling
FIELDS = [
    "objectID",
    "isPublicDomain",
    "title",
    "department",
    "classification",
    "objectName",
    "medium",
    "culture",
    "period",
    "artistDisplayName",
    "artistNationality",
    "artistBeginDate",
    "artistEndDate",
    "objectDate",
    "objectBeginDate",
    "objectEndDate",
    "country",
    "creditLine",
    "metadataDate",
]

log = logging.getLogger("fetch_met")


class RateLimiter:
    """Allows at most `rate` calls per second across threads."""

    def __init__(self, rate: int):
        self.interval = 1.0 / rate
        self.lock = threading.Lock()
        self.next_slot = time.monotonic()

    def wait(self):
        with self.lock:
            now = time.monotonic()
            if now < self.next_slot:
                time.sleep(self.next_slot - now)
            self.next_slot = max(now, self.next_slot) + self.interval


limiter = RateLimiter(MAX_REQ_PER_SEC)
session = requests.Session()


def get_json(url: str, retries: int = 3):
    for attempt in range(1, retries + 1):
        limiter.wait()
        try:
            resp = session.get(url, timeout=15)
            if resp.status_code == 404:
                return None
            resp.raise_for_status()
            return resp.json()
        except requests.RequestException as exc:
            if attempt == retries:
                raise
            backoff = 2 ** attempt
            log.warning("retry %s for %s in %ss (%s)", attempt, url, backoff, exc)
            time.sleep(backoff)


def fetch_object_ids() -> list[int]:
    data = get_json(f"{BASE_URL}/objects")
    ids = data.get("objectIDs") or []
    log.info("collection has %s object IDs", len(ids))
    return ids


def fetch_object(object_id: int):
    record = get_json(f"{BASE_URL}/objects/{object_id}")
    if not record or not record.get("isPublicDomain"):
        return None
    return {f: record.get(f) for f in FIELDS}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="data/artworks.csv")
    parser.add_argument("--limit", type=int, default=100_000,
                        help="stop after this many public-domain records")
    parser.add_argument("--workers", type=int, default=8)
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)

    ids = fetch_object_ids()
    written, failed = 0, []

    with open(args.out, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()

        # Work through IDs in batches so we can stop cleanly at --limit
        batch_size = 2_000
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            for start in range(0, len(ids), batch_size):
                batch = ids[start:start + batch_size]
                futures = {pool.submit(fetch_object, oid): oid for oid in batch}
                for fut in as_completed(futures):
                    try:
                        row = fut.result()
                    except Exception as exc:  # noqa: BLE001
                        failed.append(futures[fut])
                        log.error("gave up on %s: %s", futures[fut], exc)
                        continue
                    if row and written < args.limit:
                        writer.writerow(row)
                        written += 1
                log.info("progress: %s records written", written)
                if written >= args.limit:
                    break

    if failed:
        with open(args.out + ".failed_ids.txt", "w") as f:
            f.write("\n".join(map(str, failed)))
    log.info("done: %s records, %s failed IDs", written, len(failed))


if __name__ == "__main__":
    main()
