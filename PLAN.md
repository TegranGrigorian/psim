# PLAN.md — Who Is the Bus For? (psim)

Class project: *Who Is the Bus For? Student and Resident Spatial Imaginaries in Ann Arbor's Transit System.*
Author: Tegran Grigorian. Draft v0.2, 2026-10-25.

Project root: `~/Documents/Projects/psim/`, containing `psim-engine/` (Python), `psim-tools/` (Rust) and `psim-site/` (TypeScript). Build order: `psim-tools` first, then `psim-engine`, then `psim-site`. Global seed: 42.

## 1. Goal

Test, rather than assume, whether Ann Arbor's transit (TheRide and the University of Michigan buses) serves students better than year-round residents, and whether the simple student/resident binary holds up. Use a transit simulation over synthetic personas, informed by fieldwork and archival work, and compare against a second university town. Then propose a revised network and re-run the simulation to see if access improves.

The simulation does not need to be precise. It needs to be **transparent, reproducible, and good enough to compare groups under the same assumptions**.

## 2. Components

| Project | Language | Role |
|---|---|---|
| `psim-tools` | Rust | CLI. `generate`: creates personas and trips from city data. `analyze`: aggregates results into summaries for the site. |
| `psim-engine` | Python | Simulation engine: routes every trip with **r5py** over GTFS + OSM, writes results. Also edits GTFS for redesign scenarios. |
| `psim-site` | TypeScript | Static website: interactive maps and charts over the summary files. No backend. |

Open-source building blocks:
- **r5py** (Conveyal R5) for routing, rather than building a router.
- **gtfs-kit** or **partridge** for GTFS editing (redesign scenarios).
- **geopandas / pandas / pyarrow** in `psim-engine`.
- Rust crates: `clap`, `serde`, `csv`, `rayon`, `rand` (+ `rand_chacha` for seeded reproducibility), `arrow`/`parquet`, `geo`/`geojson`.
- Site: Vite, **MapLibre GL JS**, optionally **deck.gl**, **Observable Plot** or **D3**. Svelte or React (pick one; Svelte is lighter).

## 3. Architecture / data flow

```
raw data (Census ACS/PUMS, parcels/OSM, enrollment, GTFS, OSM pbf)
        │
        ▼   (manual + scripts; produces housing.csv, workplaces.csv, campus_locations.csv)
 data/<city>/ inputs
        │
        ▼   psim-tools generate --city ann_arbor --scenario baseline --seed N
 generated/<run_id>/{manifest.json, personas.csv, trips.csv}
        │
        ▼   psim-engine run --city ann_arbor --run-id <run_id>
 results/<run_id>/trip_results.parquet
        │
        ▼   psim-tools analyze --city ann_arbor --scenario baseline
 summaries/<scenario>/{group_metrics, time_of_day, neighborhood_map, routes, comparison}
        │
        ▼
 psim-site (static build, reads summaries only)
```

The full file formats are specified in `SCHEMA.md`. That file is the contract: change it first, then the code.

## 4. Repo layout (monorepo)

```
~/Documents/Projects/psim/   # repo root
  README.md
  PLAN.md
  SCHEMA.md
  data/
    ann_arbor/
    <comparison_city>/
  psim-engine/             # Python package (pyproject.toml, src/, tests/)
  psim-tools/              # Rust crate (Cargo.toml, src/, tests/)
  psim-site/               # TypeScript app (package.json, src/)
  docs/                    # fieldwork notes, archival findings, methodology
```

Large raw files (OSM extracts, GTFS zips, Census downloads) should be gitignored, with a `data/<city>/README.md` and a download script documenting where each came from. Commit small prepared inputs and final summaries so the site can be built from a fresh clone.

## 5. Simulation design (v1)

**Personas.** 1,000 per replicate. Each persona has a group (undergraduate, graduate, university staff, resident worker, shift worker, retired) plus cross-cutting attributes (tenure, age band, income band, neighborhood, shift pattern). Group shares and attribute distributions come from Census ACS (tract-level), PUMS, and university enrollment and housing figures. Undergrads and grads are placed using enrollment and housing data, not Census alone (Census undercounts group quarters).

**Anchors and routines.** Each persona gets a home and an anchor (workplace or campus location), sampled in proportion to `jobs` / `capacity_weight`. A weekly routine is a set of trips: commute or class trips on weekdays, return trips, and (later) discretionary trips. Shift pattern sets departure times (night workers travel at night, which tests late service).

**Routing.** For each trip, r5py computes a door-to-door transit itinerary with a departure window (e.g. 30 minutes, median travel time) on the configured service date. Walk and total-time limits are in `config.json`. A trip that can't be completed is a *failure*, not dropped.

**Replication.** 100 replicates, each with its own seed (`base_seed + i`, with `base_seed = 42`, so seeds 42–141) and its own 1,000 personas. This gives uncertainty intervals on every group metric. Routing cost can be reduced by deduplicating identical origin–destination–time queries within and across replicates.

**Outcomes.** Total travel time, wait time, in-vehicle time, walk time, transfers, and failure rate, compared across groups (and by neighborhood, time of day, tenure).

**Scenarios.** `baseline` (current service), `redesign_v1` (edited GTFS), and the same pipeline for a comparison city. A scenario is just a different GTFS set in `config.json`.

**Analysis.** Group means with 95% intervals across replicates; pairwise differences with effect sizes; a regression (e.g. travel time or failure on group + neighborhood + hour) as a robustness check on whether group gaps survive controls.

## 6. Hypotheses to state up front

Write these down before running anything, so results can fail:

- H1: Undergraduates have lower travel time and lower failure rate than resident workers, for equivalent distances.
- H2: Shift workers have the highest failure rate, driven by evening/night service.
- H3: University staff sit closer to students than to other residents on the main metrics (complicating the binary).
- H4: Differences between neighborhoods are as large as differences between student and resident groups.
- H5: The comparison city shows a different gap, so Ann Arbor's arrangement is not inevitable.
- H6: A targeted redesign reduces failure rate among the worst-served groups without hurting others.

Any hypothesis that isn't supported is a finding, not a problem.

## 7. Milestones

Time estimates assume part-time work and are guesses; adjust to the class deadline.

**M0 — Foundations (week 1)**
- Create the repo, commit `PLAN.md` and `SCHEMA.md`.
- Collect Ann Arbor data: TheRide GTFS, U-M GTFS (or note how to build it), OSM extract, Census tract data, enrollment figures.
- Resolve the open questions in `SCHEMA.md` §7.

**M1 — `psim-tools generate` (week 1–3)**
- Rust CLI (`clap`, `serde`, `csv`, `rand_chacha` seeded with 42, `rayon`): reads inputs, samples personas and trips, writes `personas.csv`, `trips.csv`, `manifest.json`.
- Build in small steps: housing and workplace sampling first, then trips.
- Validate: distributions of groups, tenure, and neighborhood match the targets. Same seed gives byte-identical output.
- Since this comes before the engine exists, treat `SCHEMA.md` as provisional.

**M2 — Tiny end-to-end in `psim-engine` (week 3–4)**
- Route a small generated sample (10–20 personas) with r5py, results to Parquet.
- Goal: prove the toolchain works and see what r5py outputs look like. Fix the schema (and the generator) if reality disagrees.

**M3 — Full baseline run (week 4–5)**
- 1,000 personas × 100 replicates routed. Exploratory analysis in Python notebooks (pandas) to see what the data says.
- Fieldwork (ride-alongs) and archival reading happen in parallel and feed back into the persona routines and assumptions.

**M4 — `psim-tools analyze` (week 5–6)**
- Move the stable aggregations into Rust; write the summary JSON/GeoJSON files.

**M5 — `psim-site` (week 6–8)**
- Map of neighborhood metrics, group comparison charts, time-of-day view, scenario toggle.
- Static build; deploy to GitHub Pages or Vercel.

**M6 — Comparison city and redesign (week 8–10)**
- Pick the comparison town (needs a good GTFS feed and Census coverage; candidates: Madison WI, Ithaca NY, Champaign–Urbana IL).
- Identify worst-served groups and areas, edit GTFS for `redesign_v1`, re-run, compare.

**M7 — Write-up (final weeks)**
- Methodology, results, limitations, and the connection back to the spatial-imaginaries framing.

## 8. Risks and limitations

- **Garbage in, garbage out.** The simulation only reflects the assumptions in the persona routines and workplace and housing assignment. Document each assumption and tie it to fieldwork or data.
- **Student housing data is thin.** Dorm and off-campus locations may need manual compilation from university sources.
- **U-M GTFS availability.** If there is no public feed, building one from published schedules is real work and a source of error.
- **GTFS is scheduled service, not real service.** r5py uses timetables; your ride-alongs measure reliability and crowding, which the simulation does not model. Report this honestly, and use the fieldwork to qualify the results.
- **Transit-only.** Routing ignores cars, biking, and rideshare. `has_car` is recorded but unused in v1; note that "failure" means "no transit option," not "no way to travel."
- **Synthetic does not mean real.** Results show what the system's *design* does to a plausible population, not what actual residents experience.
- **Comparison-city fairness.** Different towns differ in size and density; compare patterns and gaps, not raw minutes.
- **Scope.** The abstract is ambitious. If time gets short, drop in this order: second web features (time-of-day view), discretionary trips, then the redesign loop. Keep baseline + comparison city.

## 9. Definition of done

1. Reproducible baseline results for Ann Arbor with confidence intervals across 100 replicates.
2. Comparison-city results using the same pipeline.
3. A redesigned network with before/after comparison.
4. A static site presenting the results interactively.
5. A write-up that states which hypotheses held and which did not, with limitations stated plainly.

## 10. Immediate next steps

1. Skim `SCHEMA.md` and push back on anything that doesn't fit your data.
2. Create the GitHub repo with the layout in §4.
3. Start the Rust crate skeleton in `psim-tools/` with `clap` subcommands `generate` and `analyze` stubbed out and the seed defaulting to 42.
4. Download TheRide GTFS and check whether U-M publishes one.
5. When `generate` produces output, install r5py (needs Java 21+ and a Python environment) in `psim-engine/` and route a single trip as a smoke test.
