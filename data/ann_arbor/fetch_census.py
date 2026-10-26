"""Downloads the ACS tables `psim-tools prepare` reads, using the Census API.

usage: CENSUS_API_KEY=... python3 -I fetch_census.py <state_fips> <county_fips> <place_fips> <out_dir> [acs_year]

Writes <out_dir>/acs_tracts.json (every tract in the county) and <out_dir>/acs_place.json
(the city). The key is read from the environment and never written anywhere.
"""
import json
import os
import sys
import urllib.parse
import urllib.request

KEY = os.environ.get("CENSUS_API_KEY")
if not KEY:
    sys.exit("CENSUS_API_KEY is not set (put it in psim-tools/.env)")
state, county, place, out_dir = sys.argv[1:5]
year = sys.argv[5] if len(sys.argv) > 5 else "2023"
BASE = f"https://api.census.gov/data/{year}/acs/acs5"

MALE_18_24 = [f"B01001_{i:03d}E" for i in range(7, 11)]
FEMALE_18_24 = [f"B01001_{i:03d}E" for i in range(31, 35)]
MALE_ADULT = [f"B01001_{i:03d}E" for i in range(7, 26)]
FEMALE_ADULT = [f"B01001_{i:03d}E" for i in range(31, 50)]

TRACT_VARS = (
    ["B25003_001E", "B25003_002E", "B25003_003E", "B19013_001E",
     "B25044_001E", "B25044_002E", "B25044_003E", "B25044_009E", "B25044_010E", "B01001_001E"]
    + MALE_18_24 + FEMALE_18_24
)
PLACE_VARS_A = (
    ["B01003_001E", "B14001_008E", "B14001_009E", "B23025_004E", "B25003_001E", "B25003_003E",
     "B19013_001E", "B08301_001E", "B08301_002E", "B08301_010E", "B08301_018E", "B08301_019E", "B08301_021E",
     "B01001_001E"]
)


def get(variables, geography):
    query = urllib.parse.urlencode({"get": "NAME," + ",".join(variables), "for": geography[0], "in": geography[1], "key": KEY},
                                   safe=",:*")
    # the "in" clause must use spaces, not +, between its parts
    url = f"{BASE}?{query}".replace("%20", "%20")
    with urllib.request.urlopen(url, timeout=120) as r:
        rows = json.load(r)
    header, *data = rows
    return [dict(zip(header, row)) for row in data]


def write(name, obj):
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, name), "w") as f:
        json.dump(obj, f, indent=1)
        f.write("\n")


in_county = f"state:{state} county:{county}"
tracts = get(TRACT_VARS, ("tract:*", in_county))
write("acs_tracts.json", {"acs": f"{year} 5-year", "state": state, "county": county, "tracts": tracts})
print(f"acs_tracts.json: {len(tracts)} tracts")

in_state = f"state:{state}"
a = get(PLACE_VARS_A, (f"place:{place}", in_state))[0]
male = get(MALE_ADULT, (f"place:{place}", in_state))[0]
female = get(FEMALE_ADULT, (f"place:{place}", in_state))[0]
cells = {k: int(v) for part in (male, female) for k, v in part.items() if k.startswith("B01001_")}
adults = sum(cells[k] for k in MALE_ADULT + FEMALE_ADULT)
seniors = sum(cells[f"B01001_{i:03d}E"] for i in list(range(20, 26)) + list(range(44, 50)))
write("acs_place.json", {"acs": f"{year} 5-year", "name": a["NAME"], "place": place, "values": a,
                         "adults_18_plus": adults, "adults_65_plus": seniors})
print(f"acs_place.json: {a['NAME']}, adults {adults}, 65+ {seniors}")
