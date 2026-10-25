#!/usr/bin/env bash
# Downloads the public inputs for Ann Arbor into data/ann_arbor/raw/ (gitignored)
# and records where each came from in sources.json (committed).
#
#   ./fetch.sh            download what's missing
#   ./fetch.sh --force    re-download everything
#
# Needs: curl, python3. Optional: osmium (clips the Michigan OSM extract to the
# config bbox; strongly recommended before routing).
set -euo pipefail

cd "$(dirname "$0")"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

THERIDE_URL="https://www.theride.org/sites/default/files/google/google_transit.zip"
UMICH_URL="https://webapps.fo.umich.edu/transit_uploads/google_transit.zip"
OSM_URL="https://download.geofabrik.de/north-america/us/michigan-latest.osm.pbf"

THERIDE_ZIP="raw/gtfs/theride/google_transit.zip"
UMICH_ZIP="raw/gtfs/umich/google_transit.zip"
OSM_FULL="raw/michigan-latest.osm.pbf"
OSM_CLIPPED="raw/osm.pbf" # the file config.json's "osm" points at

fetch() { # name url dest
  local name=$1 url=$2 dest=$3
  mkdir -p "$(dirname "$dest")"
  if [[ -s "$dest" && $FORCE -eq 0 ]]; then
    echo "have $name ($dest), skipping (use --force to re-download)"
    return
  fi
  echo "downloading $name ..."
  curl -fsSL --retry 3 --retry-delay 5 -o "$dest.part" -D "$dest.headers" "$url"
  mv "$dest.part" "$dest"
}

fetch theride "$THERIDE_URL" "$THERIDE_ZIP"
fetch umich "$UMICH_URL" "$UMICH_ZIP"
fetch osm_michigan "$OSM_URL" "$OSM_FULL"

# Clip to the bbox in config.json so r5py loads Ann Arbor, not all of Michigan.
if command -v osmium >/dev/null; then
  if [[ ! -s "$OSM_CLIPPED" || $FORCE -eq 1 || "$OSM_FULL" -nt "$OSM_CLIPPED" ]]; then
    BBOX=$(python3 -I -c 'import json;print(",".join(str(x) for x in json.load(open("config.json"))["bbox"]))')
    echo "clipping OSM to bbox $BBOX ..."
    osmium extract --bbox "$BBOX" --strategy complete_ways --overwrite -o "$OSM_CLIPPED" "$OSM_FULL"
  fi
else
  echo "WARNING: osmium not found, $OSM_CLIPPED not created."
  echo "  Install it (Arch: sudo pacman -S osmium-tool) and re-run ./fetch.sh."
fi

# Provenance: when, from where, which bytes.
python3 -I - "$THERIDE_URL" "$THERIDE_ZIP" "$UMICH_URL" "$UMICH_ZIP" "$OSM_URL" "$OSM_FULL" "$OSM_CLIPPED" <<'PY'
import hashlib, json, os, sys, datetime

def info(url, path):
    if not os.path.exists(path):
        return None
    last_modified = None
    try:
        for line in open(path + ".headers", errors="replace"):
            if line.lower().startswith("last-modified:"):
                last_modified = line.split(":", 1)[1].strip()  # keeps the final response's value
    except FileNotFoundError:
        pass
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return {
        "url": url,
        "file": path,
        "bytes": os.path.getsize(path),
        "sha256": h.hexdigest(),
        "last_modified": last_modified,
        "recorded_at": datetime.datetime.fromtimestamp(os.path.getmtime(path), datetime.timezone.utc).isoformat(timespec="seconds"),
    }

a = sys.argv[1:]
out = {
    "theride_gtfs": info(a[0], a[1]),
    "umich_gtfs": info(a[2], a[3]),
    "osm_michigan_geofabrik": info(a[4], a[5]),
    "osm_clipped": ({"file": a[6], "derived_from": a[5]} if os.path.exists(a[6]) else None),
}
json.dump(out, open("sources.json", "w"), indent=2)
open("sources.json", "a").write("\n")
print("wrote sources.json")
PY

echo
python3 -I check_gtfs_coverage.py config.json "$THERIDE_ZIP" "$UMICH_ZIP"
