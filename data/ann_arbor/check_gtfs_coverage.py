"""Check that GTFS feeds run service on the config's service dates.

usage: python3 -I check_gtfs_coverage.py <config.json> <feed.zip> [<feed.zip> ...]
Exit code 1 if any feed has no service on a date.
"""
import csv
import io
import json
import sys
import zipfile
from datetime import date, datetime

DAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]


def rows(zf, name):
    if name not in zf.namelist():
        return []
    with zf.open(name) as f:
        return list(csv.DictReader(io.TextIOWrapper(f, encoding="utf-8-sig")))


def parse(d):
    return datetime.strptime(d, "%Y%m%d").date()


def active_services(zf, day):
    active = set()
    for r in rows(zf, "calendar.txt"):
        if parse(r["start_date"]) <= day <= parse(r["end_date"]) and r[DAYS[day.weekday()]] == "1":
            active.add(r["service_id"])
    for r in rows(zf, "calendar_dates.txt"):
        if parse(r["date"]) == day:
            (active.add if r["exception_type"] == "1" else active.discard)(r["service_id"])
    return active


def feed_range(zf):
    starts, ends = [], []
    for r in rows(zf, "calendar.txt"):
        starts.append(parse(r["start_date"]))
        ends.append(parse(r["end_date"]))
    for r in rows(zf, "calendar_dates.txt"):
        starts.append(parse(r["date"]))
        ends.append(parse(r["date"]))
    return (min(starts), max(ends)) if starts else (None, None)


def main(argv):
    cfg = json.load(open(argv[1]))
    dates = {
        "service_date": date.fromisoformat(cfg["service_date"]),
        "weekend_service_date": date.fromisoformat(cfg["weekend_service_date"]),
    }
    ok = True
    for path in argv[2:]:
        with zipfile.ZipFile(path) as zf:
            lo, hi = feed_range(zf)
            trips = rows(zf, "trips.txt")
            print(f"{path}: service dates {lo} .. {hi}, {len(trips)} trips")
            for label, day in dates.items():
                services = active_services(zf, day)
                n = sum(1 for t in trips if t["service_id"] in services)
                status = "ok" if n else "NO SERVICE"
                ok &= bool(n)
                print(f"  {label} {day} ({day.strftime('%a')}): {n} trips  [{status}]")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
