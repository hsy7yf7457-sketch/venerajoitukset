# Finnish Marine Speed Limits

A personal-use iOS app that shows the **active marine speed limit** (and other
waterway restrictions) at your current position in Finnish waters, with a live
GPS speedometer and enter/leave notifications.

<p align="center"><em>Data © Väylävirasto (Finnish Transport Infrastructure Agency), CC BY 4.0</em></p>

## What it does

- **GPS speedometer** — your live ground speed (km/h and/or knots).
- **Active speed limit** — the round red sign shows the strictest speed limit
  for the zone you're in, or a check mark when there's none.
- **Other restrictions** — small icons for active restrictions you've enabled
  (no-wake, motor bans, jet-ski bans, anchoring bans, etc.). Tap one for detail.
- **Notifications** — a local alert when you **enter** and when you **leave** a
  zone, for the restriction types you choose (default: speed limit + no-wake).
  Fires with the screen off while a *trip* is active.
- **Exceptions flag** — a ⚠️ badge when a limit has conditions (see below).
- **Fully offline** — all zones are bundled in the app; no connectivity needed
  on the water.

## Localization

The app is localized to **English, Finnish (suomi) and Swedish (svenska)** and
follows the device language. Strings live in String Catalogs:

- `App/Localizable.xcstrings` — all in-app UI, restriction names, notifications.
- `App/InfoPlist.xcstrings` — permission dialog texts and the app display name.

English source strings are the keys, so adding a new `Text("...")` just adds a
key to translate. To test a language on the simulator:

```bash
xcrun simctl launch <UDID> com.eliasaalto.FinnishMarineSpeedLimits -AppleLanguages '(fi)' -AppleLocale fi_FI
```

## Waterway sign icons

Active restrictions are shown under the speed limit using the **official Finnish
waterway signs** (*vesiliikennemerkit*), bundled as SVGs in the asset catalog
(`App/Assets.xcassets/sign_*.imageset`). These are **public domain** (Finnish
regulation signage, via Wikimedia Commons `Vesiliikennemerkki N.svg`). Speed
recommendation and engine-power limit have no standard pictogram and fall back
to an SF Symbol.

## Data source

The zones come from Väylävirasto's open **OGC API Features** service, layer
`vesivaylatiedot:rajoitusalue_a_uusi` (waterway restriction areas), returned in
WGS84. Licence: **CC BY 4.0** (attribution shown in the app). One polygon per
area, tagged with restriction-type codes (`RAJOITUSTYYPIT`):

| Code | Meaning | App type |
|------|---------|----------|
| 01 | Nopeusrajoitus | speed limit |
| 02 | Aallokon aiheuttamisen kielto | no wake |
| 03 | Purjelautailukielto | no windsurfing |
| 04 | Vesiskootterilla ajo kielletty | no jet skis |
| 05 | Moottorilla ajo kielletty | no motor power |
| 06 | Ankkurin käyttökielto | no anchoring |
| 07 | Pysäköimiskielto | no mooring |
| 11 | Nopeussuositus | speed recommendation |
| 12 | Vesihiihtokielto | no water-skiing |
| 13 | Tehorajoitus | engine power limit |

## Updating the bundled data

The source refreshes weekly but limits rarely change, so a manual refresh every
month or so is plenty. Regenerate the snapshot and rebuild:

```bash
python3 Scripts/refresh_data.py   # rewrites App/Resources/restrictions.json
```

The snapshot embeds a `generatedAt` timestamp, shown in the app footer and in
Settings › Data.

## Building & running

Requires **Xcode 16+** (developed on Xcode 26.2). The project uses a
file-system-synchronized group, so new files under `App/` are picked up
automatically.

1. Open `FinnishMarineSpeedLimits.xcodeproj`.
2. Set your own Team + a unique bundle identifier under *Signing & Capabilities*
   (currently `com.eliasaalto.FinnishMarineSpeedLimits`).
3. Run on a device (GPS + notifications need a real iPhone for real use).
4. On first *Start trip*, allow location **Always** and notifications so alerts
   work with the screen off.

### Smoke-testing on the simulator

The simulator can feed a location and auto-start a trip:

```bash
xcrun simctl location <UDID> set 61.63575,21.34954   # inside a 15 km/h zone
```

## Important caveats (read before relying on it)

- **This is an aid, not an authority.** Always follow the actual signs, charts,
  and the law. Data can be out of date or incomplete.
- **Vessel/time-specific limits aren't auto-applied.** Some limits only bind
  certain vessels (e.g. draught > 8 m, tonnage, electric craft) or times of day.
  The source stores these only as free Finnish text, so the app **shows the
  numeric limit and flags "exceptions apply"** rather than guessing whether a
  limit applies to your boat. Tap the sign/icon to read the official wording.
- **Overlapping zones:** when several apply, the app shows the **strictest
  (lowest)** speed limit.
- **Battery:** a *trip* keeps continuous background GPS running. Stop the trip
  when you're done.

## Project layout

```
App/
  Models/          RestrictionType, RestrictionArea (+ point-in-polygon)
  Services/        RestrictionStore, LocationManager, NotificationManager,
                   RestrictionMonitor (resolver + enter/leave), AppSettings,
                   SpeedFormatting
  Views/           MainView, SpeedometerView, SpeedLimitSignView,
                   SettingsView, RestrictionDetailSheet
  Resources/       restrictions.json  (bundled snapshot)
Scripts/
  refresh_data.py  regenerate the snapshot from Väylävirasto open data
Info.plist         location + background-mode + usage strings
```
