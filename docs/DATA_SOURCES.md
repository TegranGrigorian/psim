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

## 4. How `psim-tools prepare` builds the inputs, and the assumptions it makes

`psim-tools prepare --city ann_arbor` reads only files `fetch.sh` downloaded (hashes in `sources.json`) and the parameters in `data/ann_arbor/prepare.json`. Study area: blocks of Ann Arbor city (place 03000), 1,322 blocks, 635 of them with jobs. Every number below is what the last run printed. Where the data cannot settle something, the assumption is in `prepare.json` and listed here; none of them is a result.

| Input | How it is built | Check |
|---|---|---|
| `housing.csv` (2,072 rows) | Per block, from the 2020 file: occupied housing units split into owner and renter rows by the block's tract ACS renter share; student housing (group quarters, 14,930) as `dorm` rows; nursing and other group quarters as `other_group`. Neighborhood = tract. Income band from tract median household income (below $50,000 low, $110,000 and above high). | 22,427 owner + 27,521 renter units against ACS's 49,907 occupied units; 14,930 in student housing matches the Census API |
| `workplaces.csv` (3,107 rows) | Per block and industry sector, from LODES 2021 jobs; each row split into day and night shifts by a per-sector night share (assumption 2). | 98,494 jobs, exactly the LODES total for the city |
| `campus_locations.csv` (557) | Academic and office buildings inside the OSM polygons of Central, North, South and East Campus, excluding anything Michigan Medicine runs; weight = building footprint area. | 299,833 m² central, 341,465 north, 221,776 athletic |
| `pois.csv` (231) | OSM shops and health facilities inside the bbox, weighted by type (assumption 4). | 130 shopping, 101 medical |
| `group_shares`, `represented_population`, `undergraduate_dorm_share` in `config.json` | Students and over-65s from ACS (shares of adults 18+); the remaining working-age adults split by where the jobs are (university standard-day / any night shift / other standard-day), so the shares match the pools personas draw anchors from. Dorm share = 14,930 × 0.85 ÷ 29,223 undergraduates = 43.4%. `represented_population` = ACS adults 18+ (105,880): personas are adults. | undergraduate 27.6%, graduate 12.3%, university staff 20.8%, resident worker 19.4%, shift worker 5.4%, retired 14.5% |

### LODES puts almost all of U-M's jobs in one block

LODES assigns jobs to the employer's *reported address*. In the city, block 261614022015000 holds **28,766 of the 32,738 education-sector jobs** (and 28,851 jobs in all): essentially U-M's non-hospital staff (OBP: 33,291 campus staff). Used as-is, every university employee would commute to one point and none would be recognized as university staff, because that block is not on any campus polygon. `prepare` therefore moves those jobs onto the 557 campus buildings in proportion to footprint area (`university_address_blocks` in `prepare.json`). The hospital's jobs are not affected: LODES places them in two real blocks inside the hospital polygon (14,333 and 5,824 jobs). The block was found by listing the blocks with the most education jobs; re-check it if the LODES year changes.

University jobs after this: 50,056 (the moved jobs plus healthcare and other jobs on university land) against OBP's 56,276 campus and hospital staff. The gap is jobs in Michigan Medicine buildings outside the hospital polygon.

### Assumptions (all in `prepare.json`, all placeholders until evidence replaces them)

1. **Which jobs are the university's.** Jobs in blocks inside a polygon run by U-M or Michigan Medicine (OSM `operator`), except retail and food service; plus the moved jobs above. Michigan Medicine buildings elsewhere are not recognized.
2. **Night shifts.** LODES has no shift information. Share of jobs on the night shift: healthcare 25%, retail and food 20%, other services 15%, technology and manufacturing 5%, government 2%, education and university 0%. 11,687 jobs (12%) end up on the night shift. This sets the size of the `shift_worker` group.
3. **Dorm share.** 85% of the Census "college/university student housing" population is assumed to be undergraduates; the rest are graduate students.
4. **Point-of-interest weights.** Supermarket 3, mall 10, department store 4, convenience 1; hospital 10, clinic 2, doctors 1.
5. **Housing type** is inferred only from the number of rental units in a block (20 or more is an apartment building) and is not used by the simulation.
6. **Residents versus jobs.** Personas draw workplaces in proportion to all jobs in the city, but many of those jobs are held by people who live elsewhere, and many residents work outside the city. The LODES residence-to-workplace table (`od`) would fix this and is the main known improvement.
7. **Students outside the city** (U-M students living in Ypsilanti or elsewhere) are not modeled; the student shares come from residents enrolled, not from U-M enrollment.

## 5. Not verified

- **Whether the moved block is entirely U-M.** The magnitude (28,766 education jobs against 33,291 campus staff) makes it near-certain, but LODES does not name employers.
- **Number of beds in university housing.** A Michigan Daily article (Jan 2023) and U-M news items report "more than 11,000 students" in university housing and a new 2,300-bed hall, but I only saw these as search snippets. The Census figure of 14,930 is higher because it counts all student housing (co-ops, other operators), not only U-M halls.
- **First-year housing requirement or share living on campus.** One aggregator claims over 97%; no official source was retrieved. Not used.
- **Fall 2026 enrollment.** The latest OBP table is Fall 2025; the semester simulated is Fall 2026.

## 6. Bus delays (the reliability model)

Source: TheRide, [Q1 Service Report](https://www.theride.org/sites/default/files/2026-04/Q1%20Service%20Report.pdf), operations report for October to December 2025 (read in full, page 1). Fixed-route **on-time performance was 82%** in Q1 FY2026 (82%, 87%, 87% and 81% in the four FY2025 quarters), against a benchmark of 80%. The same report's "95% target" and "30-minute window" figures are for **paratransit (ARide)**, a different service, and must not be used for buses. The report page does not define on-time; TheRide's earlier reports define it as a bus leaving a timepoint 0 to 5 minutes after the posted time (not read directly here, so the model treats 5 minutes as the window and says so). U-M buses publish no on-time figure; the model assumes the same distribution for them. I found no public GTFS-realtime feed for TheRide. See SCHEMA.md 4.1 for how the number is used and what it cannot pin down.

## 7. Use as validation, not just input

The ACS commute figures are an independent check on the simulation. For work and class trips in the baseline run, compare the simulated share that walks and the share that takes transit with the ACS (13.1% walk, 7.3% transit of all commuters, 26.2% work from home and so not modeled). A large mismatch means the inputs, not the routing, need fixing. A simulated population is allowed to differ from the survey, but the difference must be explained.
