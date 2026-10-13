#!/usr/bin/env python3
"""Snapshot and compare the recent tail of Open-Meteo historical APIs.

Answers open question 1 in docs/open-meteo-api.md §6: are the last days of the
archive (models=ecmwf_ifs) and of Historical Forecast (uv_index) revised after
the fact, and how far back.

    python3 tail_snapshot.py snapshot          # writes snapshot-<UTC date>.json
    python3 tail_snapshot.py compare <file>    # refetches the same range, reports drift

Standard library only. Times are GMT (no timezone parameter) so keys are stable.
"""

import datetime as dt
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

CITIES = {
    "Moscow": (55.75, 37.62),
    "Tokyo": (35.68, 139.69),
    "NewYork": (40.71, -74.01),
    "Berlin": (52.52, 13.40),
}
DAYS_BACK = 14

ARCHIVE = (
    "archive-api.open-meteo.com",
    "/v1/archive",
    "ecmwf_ifs",
    "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,"
    "wind_speed_10m,wind_gusts_10m,wind_direction_10m,pressure_msl,cloud_cover",
)
HISTORICAL_FORECAST = (
    "historical-forecast-api.open-meteo.com",
    "/v1/forecast",
    "best_match",
    "uv_index",
)
SOURCES = {"archive_ecmwf_ifs": ARCHIVE, "historical_forecast_uv": HISTORICAL_FORECAST}


def fetch(source, lat, lon, start, end):
    host, path, model, variables = source
    query = urllib.parse.urlencode({
        "latitude": lat,
        "longitude": lon,
        "start_date": start,
        "end_date": end,
        "hourly": variables,
        "models": model,
        "wind_speed_unit": "ms",
    })
    with urllib.request.urlopen(f"https://{host}{path}?{query}", timeout=60) as response:
        hourly = json.load(response)["hourly"]
    # With an explicit model some APIs suffix variable names; strip the suffix.
    return {key.split("_" + model)[0] if model != "best_match" else key: values
            for key, values in hourly.items()}


def take_snapshot():
    now = dt.datetime.now(dt.timezone.utc)
    end = now.date()
    start = end - dt.timedelta(days=DAYS_BACK)
    snapshot = {
        "fetched_at_utc": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "start_date": start.isoformat(),
        "end_date": end.isoformat(),
        "data": {
            name: {city: fetch(source, lat, lon, start.isoformat(), end.isoformat())
                   for city, (lat, lon) in CITIES.items()}
            for name, source in SOURCES.items()
        },
    }
    out = Path(__file__).with_name(f"snapshot-{end.isoformat()}.json")
    out.write_text(json.dumps(snapshot, separators=(",", ":")))
    print(f"wrote {out.name}: {start} .. {end}, fetched {snapshot['fetched_at_utc']}")


def compare(path):
    old = json.loads(Path(path).read_text())
    fetched = dt.datetime.fromisoformat(old["fetched_at_utc"].replace("Z", "+00:00"))
    print(f"snapshot {old['fetched_at_utc']} vs now {dt.datetime.now(dt.timezone.utc):%Y-%m-%dT%H:%MZ}")
    for name, source in SOURCES.items():
        for city, (lat, lon) in CITIES.items():
            before = old["data"][name][city]
            after = fetch(source, lat, lon, old["start_date"], old["end_date"])
            index = {time: i for i, time in enumerate(after["time"])}
            changed_by_day = {}
            for variable in (key for key in before if key != "time"):
                for i, time in enumerate(before["time"]):
                    a, b = before[variable][i], after[variable][index[time]]
                    if a is None or b is None or abs(a - b) < 1e-9:
                        continue
                    day = time[:10]
                    worst = changed_by_day.setdefault(day, {})
                    worst[variable] = max(worst.get(variable, 0.0), abs(a - b))
            print(f"\n{name} / {city}")
            if not changed_by_day:
                print("  no changes")
            for day in sorted(changed_by_day):
                age = (fetched.date() - dt.date.fromisoformat(day)).days
                drift = ", ".join(f"{v} {d:.2f}" for v, d in sorted(changed_by_day[day].items()))
                print(f"  {day} ({age:+d} d from snapshot): {drift}")


if __name__ == "__main__":
    if sys.argv[1:2] == ["snapshot"]:
        take_snapshot()
    elif sys.argv[1:2] == ["compare"] and len(sys.argv) == 3:
        compare(sys.argv[2])
    else:
        sys.exit(__doc__)
