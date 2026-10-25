# SCHEMA.md — psim data contract

This file is the contract between `psim-tools` (Rust), `psim-engine` (Python), and `psim-site` (TypeScript).
If a column changes here, all three projects must change. Draft v0.2 — expect revisions once real data is in hand (especially once `psim-engine` runs against real r5py output; `psim-tools` is built first, so treat the columns as provisional).

## Conventions

- **One folder per city:** `data/<city_slug>/` (e.g. `data/ann_arbor/`). Every city uses identical filenames and columns, so no city-specific code is needed.
- **Encoding:** UTF-8, `,` delimiter, header row, `\n` line endings.
- **IDs:** strings, unique within their file, stable across runs for the same seed (e.g. `h000123`, `w000045`, `p000789`).
- **Coordinates:** WGS84 decimal degrees, columns `lat`, `lon`. Six decimals is plenty.
- **Times:** `HH:MM` 24-hour local time in the city's timezone. Day of week is `mon`..`sun`.
- **Missing values:** empty field in CSV, `null` in JSON. Never `NA`, `-1`, or `0` as a sentinel.
- **Enums:** lowercase snake_case. Allowed values are listed below; unknown values are an error, not a silent pass-through.
- **Seeds:** every generated file is a function of `(inputs, seed)`. Replicate `i` uses seed `base_seed + i`. The base seed is resolved in this order: the `--base-seed` CLI flag, then `base_seed` in `config.json` (may be `null`), then a value derived from the clock (unix seconds). Whichever is used is **always** written to `manifest.json` (`base_seed` and `seed`), so any run can be reproduced exactly. Results reported in the paper must use one fixed, recorded base seed. Seeds are public and must not be personal data.

## Folder layout

```
data/<city_slug>/
  config.json            # human-written: city settings and simulation parameters
  raw/                   # downloaded sources (Census, parcels, OSM, GTFS); not committed if large
    gtfs/                # one subfolder per agency, e.g. theride/, umich/
    osm.pbf
  housing.csv            # human/tool-prepared inputs
  workplaces.csv
  campus_locations.csv   # study locations (subset of destinations)
  generated/<run_id>/    # outputs of psim-tools generate
    manifest.json
    personas.csv
    trips.csv
  results/<run_id>/      # outputs of psim-engine
    trip_results.parquet
  summaries/<scenario>/  # outputs of psim-tools analyze, consumed by psim-site
    ...
```

`run_id` is `<scenario>_s<seed>` (e.g. `baseline_s0042`). `scenario` is one of `baseline` or a named redesign (e.g. `redesign_v1`).

---

## 1. `config.json`

```json
{
  "city_slug": "ann_arbor",
  "display_name": "Ann Arbor, MI",
  "timezone": "America/Detroit",
  "bbox": [-83.85, 42.20, -83.62, 42.34],
  "population_size": 1000,
  "n_replicates": 100,
  "represented_population": 123851,
  "base_seed": null,
  "gtfs": {
    "baseline": ["raw/gtfs/theride", "raw/gtfs/umich"],
    "redesign_v1": ["raw/gtfs_redesign_v1/theride", "raw/gtfs/umich"]
  },
  "osm": "raw/osm.pbf",
  "service_date": "2026-03-10",
  "departure_window_minutes": 30,
  "max_walk_minutes": 20,
  "max_trip_minutes": 120,
  "group_shares": {
    "undergraduate": 0.0,
    "graduate": 0.0,
    "university_staff": 0.0,
    "resident_worker": 0.0,
    "shift_worker": 0.0,
    "retired": 0.0
  }
}
```

`represented_population` is the real population the personas stand in for; each persona gets `weight = represented_population / population_size` (see 3.2). `base_seed` may be `null` (resolve from the CLI or the clock, see Conventions). `group_shares` values above are placeholders; they are derived from Census/enrollment data per city and must sum to 1.0 (see persona groups below). `service_date` must be a normal school-in-session weekday covered by every GTFS feed used. Additional sensitivity dates (e.g. break week) may be run as separate scenarios.

---

## 2. Input tables (prepared by hand or by `psim-tools prepare`)

### 2.1 `housing.csv`

One row per housing unit *or* per small aggregated location (e.g. a parcel, building, or block centroid with a unit count).

| column | type | required | notes |
|---|---|---|---|
| `housing_id` | string | yes | unique |
| `lat`, `lon` | float | yes | |
| `tenure` | enum | yes | `own`, `rent`, `dorm`, `other_group` |
| `building_type` | enum | yes | `single_family`, `small_multi`, `large_multi`, `dorm`, `other` |
| `units` | int | yes | capacity (number of households/beds the row represents), ≥ 1 |
| `neighborhood` | string | yes | neighborhood slug; free-form per city, used for grouping in analysis |
| `tract_geoid` | string | yes | 11-digit Census tract GEOID, used to join demographic distributions |
| `median_income_band` | enum | no | `low`, `mid`, `high`; derived from tract data |

### 2.2 `workplaces.csv`

| column | type | required | notes |
|---|---|---|---|
| `workplace_id` | string | yes | unique |
| `lat`, `lon` | float | yes | |
| `name` | string | no | for human debugging |
| `sector` | enum | yes | `university`, `healthcare`, `retail_food`, `government`, `education_k12`, `industry_tech`, `other_service` |
| `jobs` | int | yes | capacity weight (approx. number of jobs at this location), ≥ 1 |
| `shift_pattern` | enum | yes | v1 uses only `standard_day` (09:00–17:00) and `night` (17:00–09:00 next day). `early`, `evening`, `rotating` are reserved for later versions |
| `is_university` | bool | yes | `true` if employer is the city's primary university |

### 2.3 `campus_locations.csv`

Study destinations for students. These are *also* valid work locations for university staff (reference them from `workplaces.csv` by `workplace_id` if so).

| column | type | required | notes |
|---|---|---|---|
| `campus_id` | string | yes | unique |
| `lat`, `lon` | float | yes | |
| `name` | string | no | |
| `campus_zone` | enum | yes | `central`, `north`, `medical`, `athletic`, `other` (city-specific zones should be mapped to these) |
| `capacity_weight` | float | yes | relative share of students attending classes here, > 0 |

---

## 3. Generated tables (`psim-tools generate`)

### 3.1 `manifest.json`

```json
{
  "schema_version": "0.1",
  "run_id": "baseline_s0042",
  "city_slug": "ann_arbor",
  "scenario": "baseline",
  "base_seed": 42,
  "seed": 42,
  "replicate": 0,
  "n_personas": 1000,
  "psim_tools_version": "0.1.0",
  "generated_at": "2026-10-25T14:03:00Z",
  "input_hashes": { "housing.csv": "sha256:...", "workplaces.csv": "sha256:...", "config.json": "sha256:..." }
}
```

`seed` is `base_seed + replicate`. Both are recorded because `base_seed` may have come from the clock. Each replicate is its own `run_id`.

### 3.2 `personas.csv`

One row per simulated person.

| column | type | notes |
|---|---|---|
| `persona_id` | string | unique within the run |
| `group` | enum | primary analysis group: `undergraduate`, `graduate`, `university_staff`, `resident_worker`, `shift_worker`, `retired` |
| `tenure` | enum | copied from home: `own`, `rent`, `dorm`, `other_group` |
| `age_band` | enum | `18_24`, `25_34`, `35_49`, `50_64`, `65_plus` |
| `income_band` | enum | `low`, `mid`, `high` |
| `has_car` | bool | drawn from income band and housing type (dorm residents rarely have cars). Not used by routing: all personas are routed, and the analysis reports both everyone and the no-car subset (see PLAN.md) |
| `weight` | float | real people this persona represents: `represented_population / n_personas`. Used to scale results, not by routing |
| `neighborhood` | string | copied from home |
| `home_id` | string | FK → `housing.csv` |
| `home_lat`, `home_lon` | float | denormalized for convenience |
| `anchor_id` | string | FK → `workplaces.csv` or `campus_locations.csv`; empty for `retired` |
| `anchor_type` | enum | `workplace`, `campus`, `none` |
| `anchor_lat`, `anchor_lon` | float | denormalized |
| `shift_pattern` | enum | v1: `standard_day`, `night`, `student`, `none` (`early`, `evening`, `rotating` are reserved) |

**Group assignment rules** (documented here so the analysis is reproducible):
- Groups are mutually exclusive for the primary `group` column. Cross-cutting attributes (`tenure`, `age_band`, `income_band`, `shift_pattern`) allow other comparisons (renters vs. homeowners, etc.).
- `shift_worker` means the anchor workplace has a non-`standard_day` `shift_pattern` (in v1, `night`).
- **Group draw:** each persona's group is drawn from `group_shares`. The group sets the anchor type (students: campus location; everyone else: a workplace) and which homes are allowed (undergraduates: dorm or rental; graduate students: rental; others: any non-dorm home). Homes are drawn weighted by `units`; anchors weighted by `jobs` / `capacity_weight`. `university_staff` draw only from `is_university` workplaces; `shift_worker` only from non-`standard_day` workplaces; `resident_worker` from non-university `standard_day` workplaces.
- **Age:** undergraduate `18_24`; graduate student `18_24` or `25_34` (22–34); retired `65_plus`; everyone else spread over `25_34`, `35_49`, `50_64`.
- **Income:** `income_band` comes from the home's `median_income_band` plus random noise (a high-income tract still holds some low-income people). Housing determines income, not the reverse.
- `university_staff` means the anchor workplace has `is_university = true` and is not a student role (this is the group that complicates the resident/student binary).

### 3.3 `trips.csv`

One row per trip a persona wants to make in a week. This is the input to the routing engine.

| column | type | notes |
|---|---|---|
| `trip_id` | string | unique within the run |
| `persona_id` | string | FK → `personas.csv` |
| `day` | enum | `mon`..`sun` |
| `depart_time` | `HH:MM` | desired *departure* time from origin |
| `purpose` | enum | `work`, `class`, `shopping`, `medical`, `social`, `return_home` |
| `origin_lat`, `origin_lon` | float | |
| `dest_lat`, `dest_lon` | float | |
| `dest_id` | string | FK → housing / workplace / campus / `poi_*` id |
| `required` | bool | `true` for work/class (a failure counts as a missed obligation) |

v1 departure times: `standard_day` workers leave to arrive by 09:00 and return after 17:00; `night` workers leave to arrive by 17:00 and return after 09:00 the next morning; students depart for class on a weekday schedule. Return trips are explicit rows (`purpose = return_home`), not implied, so evening and late-night service matter.

Discretionary destinations (`shopping`, `medical`, `social`) come from a `pois.csv` (optional v0.2: `poi_id, lat, lon, category, weight`). The v0.1 pipeline may generate only `work`, `class`, and `return_home` trips.

---

## 4. Result table (`psim-engine`)

### 4.1 `trip_results.parquet`

One row per trip per run. Parquet, snappy compression.

| column | type | notes |
|---|---|---|
| `run_id` | string | |
| `trip_id` | string | FK → `trips.csv` |
| `persona_id` | string | |
| `completed` | bool | `false` if no transit itinerary found within `max_trip_minutes` and `max_walk_minutes` |
| `total_minutes` | float | door-to-door; null if not completed |
| `wait_minutes` | float | initial wait + transfer waits; null if not completed |
| `in_vehicle_minutes` | float | null if not completed |
| `walk_minutes` | float | access + egress + transfer walking; null if not completed |
| `transfers` | int | null if not completed |
| `routing_percentile` | int | which travel-time percentile over the departure window was used (default 50) |
| `failure_reason` | enum | `none`, `no_service_at_time`, `no_route`, `walk_limit`, `time_limit`, `origin_unreachable`, `dest_unreachable` |

`failure_reason` may be coarser than listed depending on what r5py exposes; unsupported reasons collapse to `no_route`. This is a known limitation to document.

---

## 5. Summary outputs (`psim-tools analyze` → `psim-site`)

The site only ever reads these files; it never reads raw results. All files live in `summaries/<scenario>/` and are small JSON/GeoJSON (target: whole directory < 5 MB per city).

### 5.1 `group_metrics.json`

Aggregated over the 100 replicates. One entry per (group dimension, group value).

```json
{
  "schema_version": "0.1",
  "city_slug": "ann_arbor",
  "scenario": "baseline",
  "n_replicates": 100,
  "groups": [
    {
      "dimension": "group",
      "value": "graduate",
      "n_personas_mean": 142.3,
      "metrics": {
        "total_minutes":   { "mean": 41.2, "ci_low": 39.8, "ci_high": 42.7 },
        "wait_minutes":    { "mean": 9.1,  "ci_low": 8.6,  "ci_high": 9.7 },
        "transfers":       { "mean": 0.8,  "ci_low": 0.7,  "ci_high": 0.9 },
        "failure_rate":    { "mean": 0.07, "ci_low": 0.05, "ci_high": 0.09 }
      }
    }
  ]
}
```

- `dimension` ∈ `group`, `tenure`, `neighborhood`, `shift_pattern`, `age_band`, `income_band`.
- `ci_low`/`ci_high`: 95% interval across replicates (percentile bootstrap or empirical 2.5/97.5 percentiles; document which).
- Numbers above are illustrative placeholders, not results.

### 5.2 `time_of_day.json`

Failure rate and mean wait by group by hour of departure (0–23) and day type (`weekday`, `weekend`). Supports the "when they run" question.

### 5.3 `neighborhood_map.geojson`

One feature per neighborhood (polygon, or point if polygons are unavailable) with the same metrics as `group_metrics.json`'s `neighborhood` dimension in `properties`. Supports the "where routes go" question.

### 5.4 `routes.geojson`

Transit routes for the scenario, one LineString per route, with `route_id`, `route_short_name`, `agency`, and optionally `trips_per_weekday`. Supports before/after maps.

### 5.5 `comparison.json`

Pairwise differences between scenarios (e.g. `baseline` vs `redesign_v1`) or between cities, same metric structure as 5.1 with `delta` fields. Written by `psim-tools analyze --compare`.

---

## 6. Versioning

- `schema_version` follows `MAJOR.MINOR`. A breaking column change bumps MAJOR.
- Every generated or summary file carries the `schema_version` it was written with (in `manifest.json` or the JSON header; CSV/Parquet inherit the run's manifest).
- Readers must refuse a MAJOR version they don't know.

## 7. Open questions

- Source for housing locations: Washtenaw County parcels vs. OSM buildings vs. Census block centroids with unit counts. Decision depends on what's downloadable and how clean it is. Public sources only (no scraping of listing sites, which prohibit it in their terms). Candidates: OSM extract (also needed for routing), Census ACS tract tables, Census LEHD (LODES) for workplace counts, Washtenaw County open parcel data, U-M published enrollment and housing figures.
- Whether `u-m` GTFS exists publicly; if not, build one from published schedules (adds work to `psim-engine`, not to the schema).
- Whether `pois.csv` is in v0.1 or deferred.
- Whether results should record `routing_percentile` per trip or just once per run.
