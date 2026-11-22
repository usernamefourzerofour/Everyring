# CLAUDE.md

Guidance for Claude working on Everyring, an iPhone, iPad and Apple Watch app (Swift, SwiftUI, Swift Charts,
WidgetKit, HealthKit, Codable JSON in an App Group) with concentric progress rings where each ring has its own period (day, week, month, custom or rolling).

The full product brief is in `docs/HANDOVER.md`. Read it before larger changes. Open work is in `docs/TODO.md`.

## Working with Erik

- Talk to Erik in Danish unless he writes in English. Code, code comments, commit messages, README and docs are always in English.
- Keep answers short and clear. Say what an action costs before doing it (see NoMac below).
- Plan and write code first. Only start a Mac when there is something to build, and ask Erik first.
- Never put keys, passwords, certificates, provisioning profiles or team-specific xcconfig files in the code or the repo.
  The repo is public (MIT).
- After every build: summarise errors and warnings briefly and suggest the next step.
- Erik prefers few widgets (settings instead of extra widgets); widgets simple and clean, the app has the details.

## Project layout

| Path | Contents |
| --- | --- |
| `project.yml` | XcodeGen spec. The `.xcodeproj`, all `Info.plist` and `.entitlements` files are generated from it. |
| `Everyring/` | iPhone + iPad app: HealthKit (`HealthManager.swift`), progress computation, views, editors. |
| `EveryringWatch/` | Apple Watch app (receives ring sets from the iPhone, computes from its own HealthKit store). |
| `EveryringWatchWidget/` | Watch complications (WidgetKit accessory families). |
| `EveryringWidget/` | iPhone/iPad widget extension (just the bundle). |
| `WidgetShared/` | The widget itself (timeline, views, AppIntent to pick a ring set), shared by the iPhone widget and the Watch complications. |
| `Shared/` | Used by all targets: model (`RingSet`, `Ring`, `RingPeriod`, `HealthMetric`), period and streak engines, App Group cache, ring drawing, String Catalog, privacy manifest. |
| `EveryringTests/` | Unit tests: period boundaries (week start, month lengths, DST, time zones), streaks, cache rules. |
| `Design/` | App icon source and scripts. |
| `docs/` | Brief (`HANDOVER.md`), to-do list (`TODO.md`), privacy policy, support page (GitHub Pages: `/docs`). |

Names: the app, targets, scheme and project are **Everyring** / `Everyring`. Bundle IDs: `dk.erik.everyring`,
`dk.erik.everyring.widget`, `dk.erik.everyring.watchkitapp`, `dk.erik.everyring.watchkitapp.widget`.
App Group `group.dk.erik.everyring` (the same for all four targets). Universal app (iPhone + iPad).

## Design rules

- Everyring's rings must have their own visual identity: own palette and icon, never Apple's Move/Exercise/Stand
  colours or look (HIG forbids it in icons and marketing).
- Up to 5 rings per set; stroke width scales with the ring count so 5 rings stay readable in a small widget and a complication.
- Follow the system appearance. Support Dynamic Type and VoiceOver
  ("Running, 14 of 20 kilometers this week, 70 percent").
- Week start defaults to `Calendar.current.firstWeekday`, with a user override. Never hard-code ISO weeks.
- Rolling-period values may go down; caches and widgets must accept a lower value.

## Localisation

- English only for v1, but every user-facing string goes through the String Catalog (`Shared/Localizable.xcstrings`)
  so languages can be added later. Health permission texts go in `Everyring/InfoPlist.xcstrings` and
  `EveryringWatch/InfoPlist.xcstrings`.
- Strings returned as `String` (titles, explanations) must use `String(localized:)`; `Text("…")` literals are extracted automatically.
- Format values with `Measurement`/`HKUnit` and the user's locale (km/mi, kcal/kJ); never build unit strings by hand.

## Building and testing with NoMac

All Xcode work runs on a NoMac cloud Mac ($0.90 per hour, billed per minute). Ask Erik before starting one; always stop it,
also after a failure. The project lives in `~/drive/src/Everyring` on the Mac's drive.

Getting code onto the Mac: either `git clone`/`git pull` the public repo in `~/drive/src`, or tar the changed files,
`create_mac_link` (upload to `~/drive/src/bNN.tgz`), `curl -T` the file to the upload URL, then `get_mac_file_link` to place it,
and extract it in `~/drive/src/Everyring`. Verify with a combined sha256 of all `.swift` files on both sides.

```sh
cd ~/drive/src/Everyring && xcodegen generate -q
SIM=$(xcrun simctl list devices available | grep -m1 iPhone | grep -oE '[0-9A-F-]{36}')
xcodebuild test -project Everyring.xcodeproj -scheme Everyring -destination "id=$SIM" -resultBundlePath build/test.xcresult -quiet
xcodebuild archive -project Everyring.xcodeproj -scheme Everyring -destination 'generic/platform=iOS' -archivePath build/Everyring.xcarchive \
  -xcconfig "$HOME/.nomac/signing/BYNRN8J29U.xcconfig" CURRENT_PROJECT_VERSION=NN -quiet
xcodebuild -exportArchive -archivePath build/Everyring.xcarchive -exportPath build/export \
  -exportOptionsPlist "$HOME/.nomac/signing/BYNRN8J29U.ExportOptions.plist"
```

For simulator builds, sign ad hoc so the widget extension may run and the App Group works (with
`CODE_SIGNING_ALLOWED=NO` widgets stay placeholders): add `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=`.
The simulator sometimes dies at test start ("server died" / "Channel disconnected"): boot it with `xcrun simctl boot`
and rerun. Launch the app with `-demo YES` for made-up values (screenshots); it also fills the widget cache.

Then `send_to_testflight` with `/Users/agent/drive/src/Everyring/build/export/Everyring.ipa` (encryption: false) and short notes.
NoMac project id: `prj_oY4ZSJZ4uYb0OFRHouFmV` (App Store Connect app 6835209406). Signing is set up with `set_up_signing`; run it
again on a fresh Mac before archiving (it installs the profiles in the Mac's keychain).
Bump `CURRENT_PROJECT_VERSION` in `project.yml` for every build.

## App Store

Reserve the name "Everyring" in App Store Connect early. Lessons from WeekPeek and Heart Minutes: set country availability
(all countries) by hand; App Review may ask for a screen recording from a device (Guideline 2.1); metadata can't be changed
through NoMac once a version is READY_FOR_REVIEW. HealthKit apps need a privacy policy and must not make medical claims.
The app is free: no IAP, no ads, no analytics, no account; all data stays on the device.

## Commits

Commit messages in English, imperative mood.
