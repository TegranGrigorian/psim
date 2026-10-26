# Data sources

Where each input to the simulation comes from, what has been checked against the original, and what is still an assumption. Retrieved 2026-10-25.

**AI disclosure.** The sources below were located with Claude (`claude-sonnet-5-5`) through web search and direct downloads, as permitted for data gathering in `Ai-policy.md`. Every number in the tables was read from the original document or from the Census API response, not from a search snippet or from the model's memory. Items that could not be checked that way are listed under "Not verified".

## 1. Transit and map data (downloaded, hashes in `data/ann_arbor/sources.json`)

| Data | Source | Notes |
|---|---|---|
| TheRide GTFS | [google_transit.zip](https://www.theride.org/sites/default/files/google/google_transit.zip) (also listed on the [Mobility Database](https://mobilitydatabase.org/feeds/mdb-415)) | Service 2026-09-07 to 2027-01-30. Agency timezone is `America/New_York`; U-M's is `America/Detroit` (same offset). |
| U-M transit GTFS | [google_transit.zip](https://webapps.fo.umich.edu/transit_uploads/google_transit.zip) ([listing](https://mobilitydatabase.org/feeds/gtfs/mdb-2072)) | Official feed, service 2026-08-23 to 2027-01-02. |
| Street network | [Geofabrik Michigan extract](https://download.geofabrik.de/north-america/us/michigan-latest.osm.pbf), clipped to the config bbox with `osmium` | OpenStreetMap contributors (ODbL). |

Both service dates in `config.json` (Tue 2026-11-10, Sat 2026-11-14) have service in both feeds (`data/ann_arbor/check_gtfs_coverage.py`).

## 2. University of Michigan figures (verified in the official PDFs)

Source: U-M Office of Budget and Planning, [Enrollment headcounts](https://obp.umich.edu/wp-content/uploads/pubdata/factsfigures/enrollment_umaa_2025.pdf) (Ann Arbor campus, dated 2025-09-17) and [Faculty and staff headcount summary](https://obp.umich.edu/wp-content/uploads/pubdata/factsfigures/facstaffsumm_umaa_Nov2025.pdf) (dated 2025-11-11).

| Figure | Fall 2025 |
|---|---|
| Undergraduate students | 35,358 (32,700 domestic, 2,658 international) |
| Graduate students | 15,429 |
| Professional students (MD, JD, DDS, PharmD, DNP) | 2,701 |
| **All students** | **53,488** |
| Ann Arbor campus faculty and staff, excluding hospital | 33,291 |
| Hospital (Michigan Medicine) staff | 22,985 |
| Campus plus hospital | 56,276 |
| Campus plus hospital, excluding people also counted as students | 51,947 |

Definitions that matter: enrollment excludes Visiting Scholars and Post-Graduate Medicine students. Staff counts are as of November 1 and count each person once, by primary job. Student employees (graduate student instructors and research assistants) are in the 56,276 but not in the 51,947. These are campus-wide counts: not everyone lives in the city of Ann Arbor.

## 3. U.S. Census data (via the Census API, key in `psim-tools/.env`, which is gitignored)

All figures are for **Ann Arbor city** (place 03000, Michigan) unless noted.

### 2020 Census redistricting file (PL 94-171)
| Figure | Value |
|---|---|
| Population | 123,851 |
| Housing units | 53,213 |
| Population in **college/university student housing** (table P5, group quarters) | **14,930** |
| Washtenaw County: population / housing units / student housing | 372,258 / 156,882 / 17,885 |

The student-housing count is the best available figure for dorm residents. Against 35,358 undergraduates it implies that **at most about 42% of undergraduates live in university housing** (fewer, since graduate students and some others are included), well below the 62% in the current sample data.

### American Community Survey 5-year, 2019–2023
| Figure | Value | Use |
|---|---|---|
| Population | 121,179 | |
| Adults 18+ | 105,880 | denominator for group shares |
| Adults 65+ | 15,363 (14.5% of adults) | `retired` share |
| Enrolled in college, undergraduate years | 29,223 | `undergraduate` share |
| Enrolled in graduate or professional school | 12,991 | `graduate` share |
| Employed civilians | 62,888 | |
| Occupied housing units / renter-occupied | 49,907 / 27,131 (54%) | tenure split |
| Households with no vehicle: renters / owners | 5,508 of 27,131 (20.3%) / 382 of 22,776 (1.7%) | `has_car` |
| Median household income | $81,089 | |
| Commuters (workers 16+) | 61,541 | validation targets below |
| &nbsp;&nbsp;car, truck or van | 31,128 (50.6%) | |
| &nbsp;&nbsp;public transportation | 4,506 (7.3%) | |
| &nbsp;&nbsp;walked | 8,034 (13.1%) | |
| &nbsp;&nbsp;bicycle | 1,447 (2.4%) | |
| &nbsp;&nbsp;worked from home | 16,122 (26.2%) | |

Tract-level tables (tenure, income, vehicles, age) for all 107 Washtenaw County tracts download correctly with the key; they feed `housing.csv`.

**Proposed `group_shares`, first cut** (share of adults 18+): undergraduate 27.6%, graduate 12.3% (graduate and professional together), retired 14.5%. The remaining 45.6% are working-age non-students, to be split into `university_staff`, `shift_worker` and `resident_worker` using jobs data (below). Simplifications: every person 65+ is treated as retired, and students who also work are counted only as students.

### LEHD Origin-Destination Employment Statistics (LODES8)
| File | Use |
|---|---|
| [`mi_wac_S000_JT00_2021.csv.gz`](https://lehd.ces.census.gov/data/lodes/LODES8/mi/wac/) | jobs by Census block of workplace, 20 industry columns (`CNS01`–`CNS20`) → `workplaces.csv` |
| [`mi_xwalk.csv.gz`](https://lehd.ces.census.gov/data/lodes/LODES8/mi/mi_xwalk.csv.gz) | block → tract, latitude, longitude |

2021 is the latest year in the folder at the time of retrieval.

## 4. Assumptions the data cannot settle

These need to be stated in the paper and, where possible, replaced with evidence from fieldwork.

1. **Which jobs are the university's.** LODES does not name employers. Plan: treat education-sector jobs in blocks inside the U-M campus boundary, and healthcare jobs in the hospital blocks, as university jobs. The OBP totals above bound the result (about 56,000 campus and hospital employees, of whom only some work inside the city blocks we select).
2. **Night shifts.** LODES has no shift information. Plan: a share of night work by industry sector (high in healthcare, accommodation and food service, warehousing; near zero in offices and education). The shares will be written down here when chosen.
3. **Tenure by block.** The 2020 file gives housing units per block but not rent versus own; each block will get its tract's ACS renter share.
4. **Dorm locations.** Student-housing population by block from the 2020 file (14,930 in the city). University Housing's own capacity page could not be retrieved (HTTP 403), so the dorm total is cross-checked only against the Census figure.
5. **Income, cars, ages** are drawn from the tract ACS tables with noise, as in `SCHEMA.md`.

## 5. Not verified

- **Number of beds in university housing.** A Michigan Daily article (Jan 2023) and U-M news items report "more than 11,000 students" in university housing and a new 2,300-bed hall, but I only saw these as search snippets. The Census figure of 14,930 is higher because it counts all student housing (co-ops, other operators), not only U-M halls.
- **First-year housing requirement or share living on campus.** One aggregator claims over 97%; no official source was retrieved. Not used.
- **Fall 2026 enrollment.** The latest OBP table is Fall 2025; the semester simulated is Fall 2026.

## 6. Use as validation, not just input

The ACS commute figures are an independent check on the simulation. For work and class trips in the baseline run, compare the simulated share that walks and the share that takes transit with the ACS (13.1% walk, 7.3% transit of all commuters, 26.2% work from home and so not modeled). A large mismatch means the inputs, not the routing, need fixing. A simulated population is allowed to differ from the survey, but the difference must be explained.
