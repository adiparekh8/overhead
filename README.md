# Overhead

A macOS menu bar app that shows which aircraft is flying above you right now
and who it is registered to. Native Swift and SwiftUI, macOS 14 or later, no
Dock icon.

- Aircraft positions come from the free [ADSB.lol](https://www.adsb.lol) API
  (data licensed under the ODbL).
- Owners come from the FAA's public aircraft registry, stored in a local
  SQLite file. Street addresses are never stored.

## Run it

1. Build the FAA database (about an 80 MB download, takes a minute):

       python3 build_db.py

   It writes `~/Library/Application Support/Overhead/aircraft.db`. The FAA
   refreshes its file every night; re-run this whenever you want fresh data.
   The app picks up the new file without a restart.

2. Build and open the app.

   With only the Swift command line tools:

       ./build_app.sh
       open build/Overhead.app

   With Xcode: open `Overhead.xcodeproj` and press Run, or from a terminal:

       xcodebuild -project Overhead.xcodeproj -scheme Overhead -configuration Release build
       xcodebuild -project Overhead.xcodeproj -scheme Overhead test

3. Allow location access when asked. If you decline, open Settings from the
   card (gear icon) and type a latitude and longitude.

## Tests

    swift test

The tests cover the distance math, the API response parsing (against a saved
real response in `Tests/OverheadCoreTests/Fixtures`), the choice of the
overhead aircraft, the polling schedule, formatting and the registry lookup.

## How often it updates

ADSB.lol allows 500 requests a day without an API key. Polling every 10
seconds around the clock would use that up in under 90 minutes, so:

- while the card is open, Overhead polls every 10 seconds;
- in the background, it spreads what is left of the day's quota evenly,
  which works out to about one request every 2 to 3 minutes;
- on errors it backs off (doubling up to 10 minutes), it obeys `Retry-After`
  when the limit is hit, and it stops polling while the Mac is asleep.

Only a position rounded to two decimal places (about 1 km) is sent to the API.

## Flyover

When a new aircraft comes within 5 nautical miles (straight-line), a
silhouette of it flies across the top of the screen in the direction it is
really heading, captioned with its tail number and model. The silhouette is
one of ten airframe shapes (A380, 747, four-engine wide-body, wide-body,
narrow-body, rear-engine jet, business jet, turboprop, piston single,
helicopter) chosen from the aircraft's ICAO type code. Faster aircraft cross
faster, climbing ones fly nose-up, and jets above 26,000 ft trail a contrail.
Each aircraft is shown once per half hour. The overlay ignores clicks.

Turn it off, change the distance or play a preview in Settings.

## Layout

    Sources/OverheadCore   plain Swift: distance math, API models, picking the
                           overhead aircraft, polling schedule, formatting, registry
    Sources/Overhead       the app: menu bar item, card, radar, settings
    Tests/OverheadCoreTests
    build_db.py            builds aircraft.db from the FAA registry
    build_app.sh           builds build/Overhead.app without Xcode
    project.yml            XcodeGen spec that Overhead.xcodeproj was generated from

After adding or removing source files, run `xcodegen generate` to refresh the
Xcode project.

## Checking it from a terminal

    build/Overhead.app/Contents/MacOS/Overhead --check 37.62 -122.38

makes one API request for that latitude and longitude and prints the overhead
aircraft and its owner. To watch the app's requests while it runs:

    log stream --info --predicate 'subsystem == "dev.overhead.Overhead"'
