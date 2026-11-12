#!/usr/bin/env python3
"""Record raw Open-Meteo responses as test fixtures and check API facts (MW-32).

    python3 record.py record    # fetches everything, writes raw bytes + manifest.json
    python3 record.py check     # prints the facts of docs/open-meteo-api.md §6 from recorded files, no network

Output: Packages/WeatherCore/Tests/WeatherCoreTests/Fixtures/. Requests follow A-21
(docs/architecture.md). Responses are stored byte for byte, errors included.
Standard library only.
"""

import datetime as dt
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zoneinfo
from pathlib import Path

OUT = (Path(__file__).resolve().parents[3]
       / "Packages/WeatherCore/Tests/WeatherCoreTests/Fixtures")

# slug: (latitude, longitude, IANA zone used only to compute the location's "today")
CITIES = {
    "moscow": (55.7558, 37.6173, "Europe/Moscow"),
    "tokyo": (35.6895, 139.6917, "Asia/Tokyo"),
    "newyork": (40.7128, -74.0060, "America/New_York"),
    "berlin": (52.5200, 13.4050, "Europe/Berlin"),
    "mumbai": (19.0760, 72.8777, "Asia/Kolkata"),
    "murmansk": (68.9585, 33.0827, "Europe/Moscow"),
    "auckland": (-36.8485, 174.7633, "Pacific/Auckland"),
}
RECENT_DAYS_BACK = 8
PAUSE_SECONDS = 1.0

COMMON = {"timezone": "auto", "wind_speed_unit": "ms", "timeformat": "unixtime"}
FORECAST_HOST = "api.open-meteo.com/v1/forecast"
ARCHIVE_HOST = "archive-api.open-meteo.com/v1/archive"
HISTORICAL_HOST = "historical-forecast-api.open-meteo.com/v1/forecast"
GEOCODING_HOST = "geocoding-api.open-meteo.com/v1/search"

FORECAST_HOURLY = ("temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,"
                   "precipitation_probability,wind_speed_10m,wind_gusts_10m,wind_direction_10m,"
                   "pressure_msl,cloud_cover,uv_index,weather_code,is_day")
FORECAST_DAILY = "weather_code,sunrise,sunset,temperature_2m_max,temperature_2m_min"
ARCHIVE_HOURLY = ("temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,"
                  "wind_speed_10m,wind_gusts_10m,wind_direction_10m,pressure_msl,cloud_cover")

ERROR_429_BODY = (b'{"reason":"Daily API request limit exceeded. Please try again tomorrow.",'
                  b'"error":true}')
ERROR_429_NOTE = ("recorded manually: real Archive response from the cloud, "
                  "2026-11-10T18:43Z, HTTP 429")


def forecast(city):
    lat, lon, _ = CITIES[city]
    return FORECAST_HOST, {"latitude": lat, "longitude": lon, "forecast_days": 16,
                           "hourly": FORECAST_HOURLY, "daily": FORECAST_DAILY, **COMMON}


def archive(city, start, end):
    lat, lon, _ = CITIES[city]
    return ARCHIVE_HOST, {"latitude": lat, "longitude": lon, "start_date": start, "end_date": end,
                          "models": "ecmwf_ifs", "hourly": ARCHIVE_HOURLY,
                          "daily": "sunrise,sunset", **COMMON}


def historical(city, start, end):
    lat, lon, _ = CITIES[city]
    return HISTORICAL_HOST, {"latitude": lat, "longitude": lon, "start_date": start,
                             "end_date": end, "hourly": "uv_index", **COMMON}


def geocoding(name, language):
    return GEOCODING_HOST, {"name": name, "language": language, "count": 10}


def local_today(city, now):
    return now.astimezone(zoneinfo.ZoneInfo(CITIES[city][2])).date()


def recent_end(city, now):
    """End of the "recent" window: Archive rejects an end_date after the UTC date (API §6),
    so east of UTC the local "today" is capped at the UTC date."""
    return min(local_today(city, now), now.date())


def plan(now):
    """Ordered list of (file name, host+path, query params)."""
    items = []
    for city in CITIES:
        items.append((f"forecast-{city}.json", *forecast(city)))
    for city in CITIES:
        today = recent_end(city, now)
        start, end = (today - dt.timedelta(days=RECENT_DAYS_BACK)).isoformat(), today.isoformat()
        items.append((f"archive-{city}-recent.json", *archive(city, start, end)))
        items.append((f"historical-forecast-{city}-recent.json", *historical(city, start, end)))
    items.append(("archive-berlin-year.json", *archive("berlin", "2025-01-01", "2025-12-31")))
    items.append(("historical-forecast-berlin-year.json",
                  *historical("berlin", "2025-01-01", "2025-12-31")))
    items.append(("archive-newyork-dst.json", *archive("newyork", "2025-10-30", "2025-11-04")))
    items.append(("archive-murmansk-june.json", *archive("murmansk", "2025-06-01", "2025-06-30")))
    today = local_today("auckland", now)
    tomorrow = today + dt.timedelta(days=1)
    start = (today - dt.timedelta(days=RECENT_DAYS_BACK)).isoformat()
    for label, end in (("today", today), ("tomorrow", tomorrow)):
        items.append((f"archive-auckland-end-{label}.json", *archive("auckland", start, end.isoformat())))
        items.append((f"historical-forecast-auckland-end-{label}.json",
                      *historical("auckland", start, end.isoformat())))
    for name, file, query in (
        ("geocoding-berlin-ru.json", "Berlin", "ru"), ("geocoding-berlin-en.json", "Berlin", "en"),
        ("geocoding-moscow-ru.json", "Москва", "ru"), ("geocoding-moscow-en.json", "Moscow", "en"),
        ("geocoding-springfield-en.json", "Springfield", "en"),
        ("geocoding-empty-en.json", "zzqxv", "en"),
    ):
        items.append((name, *geocoding(file, query)))
    return items


def fetch(host, params):
    url = f"https://{host}?{urllib.parse.urlencode(params)}"
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=120) as response:
                return url, response.status, response.read()
        except urllib.error.HTTPError as error:
            return url, error.code, error.read()
        except urllib.error.URLError:  # transient network failure: retry with backoff
            if attempt == 3:
                raise
            time.sleep(2 ** attempt)


def record():
    now = dt.datetime.now(dt.timezone.utc)
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {}
    items = plan(now)
    for index, (name, host, params) in enumerate(items):
        if index:
            time.sleep(PAUSE_SECONDS)
        fetched = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        url, status, body = fetch(host, params)
        (OUT / name).write_bytes(body)
        manifest[name] = {"url": url, "status": status, "fetched_at_utc": fetched}
        print(f"{status} {len(body):>8} B  {name}")
    (OUT / "error-429.json").write_bytes(ERROR_429_BODY)
    manifest["error-429.json"] = {
        "url": "https://archive-api.open-meteo.com/v1/archive", "status": 429,
        "fetched_at_utc": "2026-11-10T18:43:00Z", "note": ERROR_429_NOTE}
    (OUT / "manifest.json").write_text(json.dumps(dict(sorted(manifest.items())), indent=2,
                                                  ensure_ascii=False) + "\n")
    total = sum(path.stat().st_size for path in OUT.iterdir())
    print(f"wrote {len(manifest)} files, {total / 1e6:.2f} MB, started {now:%Y-%m-%dT%H:%MZ}")


def load(name):
    return json.loads((OUT / name).read_bytes())


def check():
    manifest = load("manifest.json")
    print("== 1. timeformat=unixtime with timezone=auto ==")
    for city in CITIES:
        data = load(f"forecast-{city}.json")
        first = data["hourly"]["time"][0]
        offset = data["utc_offset_seconds"]
        utc = dt.datetime.fromtimestamp(first, dt.timezone.utc)
        local_midnight = (first + offset) % 86400 == 0
        absolute_midnight = first % 86400 == 0
        sunrise = data["daily"]["sunrise"][0]
        print(f"{city}: timezone={data['timezone']} abbr={data['timezone_abbreviation']} "
              f"utc_offset_seconds={offset} first_time={first} ({utc:%Y-%m-%d %H:%M}Z) "
              f"first+offset%86400==0: {local_midnight}, first%86400==0: {absolute_midnight}, "
              f"daily.time[0]={data['daily']['time'][0]} sunrise[0]={sunrise} "
              f"({dt.datetime.fromtimestamp(sunrise, dt.timezone.utc):%H:%M}Z)")
    print("\n== 2. Auckland end_date ==")
    for name in ("archive-auckland-end-today.json", "archive-auckland-end-tomorrow.json",
                 "historical-forecast-auckland-end-today.json",
                 "historical-forecast-auckland-end-tomorrow.json"):
        raw = (OUT / name).read_bytes()
        data = json.loads(raw)
        entry = manifest[name]
        query = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(entry["url"]).query))
        if data.get("error"):
            print(f"{name}: HTTP {entry['status']} end_date={query['end_date']} "
                  f"fetched {entry['fetched_at_utc']} reason={data.get('reason')}")
        else:
            times = data["hourly"]["time"]
            last = dt.datetime.fromtimestamp(times[-1], dt.timezone.utc)
            print(f"{name}: HTTP {entry['status']} end_date={query['end_date']} "
                  f"fetched {entry['fetched_at_utc']} hours={len(times)} last_time={last:%Y-%m-%d %H:%M}Z "
                  f"utc_offset_seconds={data['utc_offset_seconds']}")
    print("\n== 3. Geocoding ==")
    for name in sorted(path.name for path in OUT.glob("geocoding-*.json")):
        data = load(name)
        results = data.get("results")
        print(f"{name}: top-level keys={sorted(data)} results="
              f"{'absent' if results is None else len(results)}")
        if results:
            print(f"  fields: {sorted(set().union(*(r.keys() for r in results)))}")
            first = results[0]
            print("  first: " + json.dumps(first, ensure_ascii=False))


if __name__ == "__main__":
    if sys.argv[1:2] == ["record"]:
        record()
    elif sys.argv[1:2] == ["check"]:
        check()
    else:
        sys.exit(__doc__)
