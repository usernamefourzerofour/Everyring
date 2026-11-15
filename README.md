# Everyring

A free iPhone, iPad and Apple Watch app with concentric progress rings, where **every ring has its own period**.

Apple's Activity rings all reset every day. In Everyring you build ring sets of up to five rings, and each ring
tracks a Health metric against a goal over its own period:

- **Steps** – 10,000 today
- **Running distance** – 20 km this week
- **Workouts** – 12 this month
- **Exercise minutes** – 150 in the last 7 days

Periods are either **fixed** (today, this week, this month, or every N days/weeks from a start date – the ring resets
when the period ends) or **rolling** (the last N days – the ring never resets, old days drop out as new ones come in).

## Features (planned for v1)

- Multiple ring sets, each with up to 5 rings: name, colour, icon, Health metric, goal and period
- Metrics from Apple Health: steps, active energy, exercise minutes, stand hours, flights climbed, walking/running,
  cycling, swimming and wheelchair distance, workouts (count or minutes, by type), sleep, mindful minutes,
  time in daylight, water
- Streaks (current and best) and history per ring
- Home Screen and Lock Screen widgets, Apple Watch app and complications
- Week start follows your region, with an override in Settings

## Privacy

Everyring only **reads** from Apple Health. There is no server, no account, no iCloud sync, no ads and no analytics.
All data stays on your device. A privacy policy will be published in `docs/privacy.md` (GitHub Pages).

## Building

Requirements: Xcode 27 or later (iOS 27 / iPadOS 27 / watchOS 27 SDK) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open Everyring.xcodeproj
```

The Xcode project, `Info.plist` and entitlement files are generated from `project.yml` and are not checked in.

### Running on your own devices

Change these to identifiers in your own Apple developer account, in `project.yml` and in the App Group constant in `Shared/`:

| | Value in this repo |
|---|---|
| `bundleIdPrefix` | `dk.erik` |
| iPhone/iPad app | `dk.erik.everyring` |
| Widget extension | `dk.erik.everyring.widget` |
| Watch app | `dk.erik.everyring.watchkitapp` |
| Watch widget extension | `dk.erik.everyring.watchkitapp.widget` |
| App Group (all targets) | `group.dk.erik.everyring` |

Signing settings (team, certificates, profiles) are kept out of the repo. Pass your own with `-xcconfig` or set your
team in Xcode locally.

### Tests

```sh
xcodebuild test -project Everyring.xcodeproj -scheme Everyring -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Project layout

| Folder | Contents |
|---|---|
| `Everyring/` | iPhone and iPad app |
| `EveryringWatch/` | Apple Watch app |
| `EveryringWatchWidget/` | Watch complications |
| `EveryringWidget/` | iPhone and iPad widgets |
| `Shared/` | Model, period and streak engines, ring drawing, cache – shared by all targets |
| `EveryringTests/` | Unit tests |
| `docs/` | Product brief, privacy policy and support page (GitHub Pages) |

Everyring is not a medical device and does not give medical advice. It is not affiliated with Apple.

## License

[MIT](LICENSE)
