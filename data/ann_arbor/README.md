# data/ann_arbor

Inputs for Ann Arbor, MI, built by `psim-tools prepare --city ann_arbor` from public data.
Sources, assumptions and checks: `docs/DATA_SOURCES.md`. Parameters: `prepare.json`.

- `housing.csv`, `workplaces.csv`, `campus_locations.csv`, `pois.csv`: **generated, do not edit by hand.** Re-run `fetch.sh` then `prepare`.
- `config.json`: human-written, except `group_shares`, `represented_population` and `undergraduate_dorm_share`, which `prepare` rewrites.
- `fetch.sh`, `fetch_census.py`, `check_gtfs_coverage.py`: downloads (needs `osmium` and `CENSUS_API_KEY` in `psim-tools/.env`) and a check that both service dates have service.
- `sources.json`: where every downloaded file came from, with date and hash.
- `raw/`, `generated/`, `results/` are gitignored.

`config.json` still has `"sample_data": true` so the site shows its preview banner. The inputs are real public data, but several assumptions in `prepare.json` (night-shift shares, the dorm fraction, POI weights) are placeholders. Set it to `false` once those are settled or documented as limitations.

A tiny invented dataset for the tests lives in `psim-tools/tests/fixtures/data/`.
