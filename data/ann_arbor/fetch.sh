#!/usr/bin/env bash
# Downloads the public inputs for Ann Arbor into data/ann_arbor/raw/ (gitignored)
# and records where each came from in sources.json (committed).
#
#   ./fetch.sh            download what's missing
#   ./fetch.sh --force    re-download everything
#
# Needs: curl, python3, osmium (clips the Michigan OSM extract to the config bbox
# and pulls out shops, clinics and U-M campuses). For the ACS tables, put
# CENSUS_API_KEY=... in psim-tools/.env (free key: api.census.gov/data/key_signup.html).
set -euo pipefail

cd "$(dirname "$0")"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

THERIDE_URL="https://www.theride.org/sites/default/files/google/google_transit.zip"
UMICH_URL="https://webapps.fo.umich.edu/transit_uploads/google_transit.zip"
OSM_URL="https://download.geofabrik.de/north-america/us/michigan-latest.osm.pbf"

THERIDE_ZIP="raw/gtfs/theride/google_transit.zip"
UMICH_ZIP="raw/gtfs/umich/google_transit.zip"
PL_URL="https://www2.census.gov/programs-surveys/decennial/2020/data/01-Redistricting_File--PL_94-171/Michigan/mi2020.pl.zip"
WAC_URL="https://lehd.ces.census.gov/data/lodes/LODES8/mi/wac/mi_wac_S000_JT00_2021.csv.gz"
PL_ZIP="raw/census/mi2020.pl.zip"
WAC_GZ="raw/census/mi_wac_S000_JT00_2021.csv.gz"
OSM_POIS="raw/osm_pois.geojson" # derived from osm.pbf
OSM_BUILDINGS="raw/osm_buildings.geojson" # derived from osm.pbf
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
fetch census_pl_2020 "$PL_URL" "$PL_ZIP"
fetch lodes_wac_2021 "$WAC_URL" "$WAC_GZ"

# ACS tables through the Census API (needs a key; skipped with a note if there is none).
ENV_FILE="../../psim-tools/.env"
if [[ -f "$ENV_FILE" ]]; then set -a; . "$ENV_FILE"; set +a; fi
if [[ -n "${CENSUS_API_KEY:-}" ]]; then
  if [[ ! -s raw/census/acs_tracts.json || $FORCE -eq 1 ]]; then
    echo "fetching ACS tables ..."
    python3 -I fetch_census.py 26 161 03000 raw/census
  else
    echo "have ACS tables, skipping (use --force to re-download)"
  fi
else
  echo "WARNING: CENSUS_API_KEY not set, ACS tables not fetched."
fi

# Clip to the bbox in config.json so r5py loads Ann Arbor, not all of Michigan.
if command -v osmium >/dev/null; then
  if [[ ! -s "$OSM_CLIPPED" || $FORCE -eq 1 || "$OSM_FULL" -nt "$OSM_CLIPPED" ]]; then
    BBOX=$(python3 -I -c 'import json;print(",".join(str(x) for x in json.load(open("config.json"))["bbox"]))')
    echo "clipping OSM to bbox $BBOX ..."
    osmium extract --bbox "$BBOX" --strategy complete_ways --overwrite -o "$OSM_CLIPPED" "$OSM_FULL"
  fi
  # Shops, health care and U-M campuses, as GeoJSON for `psim-tools prepare`.
  if [[ ! -s "$OSM_POIS" || $FORCE -eq 1 || "$OSM_CLIPPED" -nt "$OSM_POIS" ]]; then
    echo "extracting OSM points of interest ..."
    osmium tags-filter "$OSM_CLIPPED" \
      nwr/shop=supermarket,mall,department_store,convenience \
      nwr/amenity=hospital,clinic,doctors,university,college \
      nwr/healthcare=hospital,clinic,doctor nwr/landuse=education \
      -o "$OSM_POIS.pbf" --overwrite
    osmium export -f geojson --add-unique-id=type_id --geometry-types=point,polygon "$OSM_POIS.pbf" -o "$OSM_POIS" --overwrite
    rm -f "$OSM_POIS.pbf"
  fi
  # Building footprints, used to place university jobs and classes (LODES puts all of U-M's
  # jobs in one block).
  if [[ ! -s "$OSM_BUILDINGS" || $FORCE -eq 1 || "$OSM_CLIPPED" -nt "$OSM_BUILDINGS" ]]; then
    echo "extracting OSM buildings ..."
    osmium tags-filter "$OSM_CLIPPED" w/building r/building -o "$OSM_BUILDINGS.pbf" --overwrite
    osmium export -f geojson --add-unique-id=type_id --geometry-types=polygon "$OSM_BUILDINGS.pbf" -o "$OSM_BUILDINGS" --overwrite
    rm -f "$OSM_BUILDINGS.pbf"
  fi
else
  echo "WARNING: osmium not found, $OSM_CLIPPED not created."
  echo "  Install it (Arch: sudo pacman -S osmium-tool) and re-run ./fetch.sh."
fi

# Provenance: when, from where, which bytes.
python3 -I - "$THERIDE_URL" "$THERIDE_ZIP" "$UMICH_URL" "$UMICH_ZIP" "$OSM_URL" "$OSM_FULL" "$OSM_CLIPPED" "$PL_URL" "$PL_ZIP" "$WAC_URL" "$WAC_GZ" "$OSM_POIS" "$OSM_BUILDINGS" <<'PY'
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
    "census_pl_2020": info(a[7], a[8]),
    "lodes_wac_2021": info(a[9], a[10]),
    "osm_pois": ({"file": a[11], "derived_from": a[6], **{k: info("", a[11])[k] for k in ("bytes", "sha256")}} if os.path.exists(a[11]) else None),
}
if os.path.exists(a[12]):
    out["osm_buildings"] = {"file": a[12], "derived_from": a[6], **{k: info("", a[12])[k] for k in ("bytes", "sha256")}}
for name in ("acs_tracts", "acs_place"):
    path = f"raw/census/{name}.json"
    if os.path.exists(path):
        meta = json.load(open(path))
        entry = info("https://api.census.gov/data/2023/acs/acs5 (Census API)", path)
        entry["acs"] = meta.get("acs")
        entry["last_modified"] = None
        out[name] = entry
json.dump(out, open("sources.json", "w"), indent=2)
open("sources.json", "a").write("\n")
print("wrote sources.json")
PY

echo
python3 -I check_gtfs_coverage.py config.json "$THERIDE_ZIP" "$UMICH_ZIP"
