# Everyring — Handover prompt for Claude Code

You are building **Everyring**, a free iOS app with Apple-style concentric progress rings. In Apple's Activity rings every ring resets daily. In Everyring **each ring has its own period** (day, week or month). Data comes from Apple Health.

Read this whole brief first. Then reply with an implementation plan and any open questions before you write code.

---

## 0. First task: set up the repo

The public repo **github.com/usernamefourzerofour/Everyring** already exists, with only an MIT `LICENSE`. Before any app code:

1. Save this brief as `docs/HANDOVER.md`.
2. Write `CLAUDE.md`, adapted from Heart Minutes' `CLAUDE.md` (working with Erik, project layout, NoMac workflow), with Everyring names, bundle IDs and App Group.
3. Write `README.md` (what the app does, build instructions, MIT license) and a `.gitignore` for Xcode/XcodeGen that keeps out `.xcodeproj`, build output and all signing files.
4. Commit and push, then reply with the implementation plan.

## 1. Concept

- The user builds one or more **ring sets**. Each set has **up to 5 concentric rings** drawn in one combined image, like Apple's Activity rings.
- Each ring has:
  - a name, a color and an SF Symbol icon
  - a **Health metric** (see section 4)
  - a **goal value** with a unit
  - a **period**, either *fixed* or *rolling* (see section 5)
- A ring on a fixed period fills as Health data accumulates and resets when the next period starts. A ring on a rolling period always shows the last N days, so old data drops out as new data comes in.
- Example set: Steps 10,000 today · Running 20 km this week · Workouts 12 this month · Heart minutes 150 in the last 7 days.

## 2. Platforms and targets

| Target | Scope |
|---|---|
| iPhone app | Main app: ring sets, editing, history, settings |
| iPad | Same app, adapted layout |
| iPhone + iPad widgets | WidgetKit; the user picks which ring set a widget shows (AppIntent configuration). Sizes: small, medium, large, plus Lock Screen accessory widgets |
| Apple Watch | **Complications** (WidgetKit accessory families) plus a **small watchOS app**. Tapping the complication opens the app with ring details |

- **Minimum OS:** iOS 27, iPadOS 27, watchOS 27 (decided 2026-11-15; originally 26). Use current SwiftUI APIs and system materials (Liquid Glass where it fits naturally).
- **Language:** English only for now, but put every string in a String Catalog so localization can be added later.

## 3. Data storage

- **Local only. No iCloud and no accounts.**
- Use SwiftData (or another local store) in an **App Group** container so the app and widgets share ring configuration and cached progress.
- **Watch:** send ring-set configuration from iPhone to Watch with WatchConnectivity. The Watch computes progress from its own HealthKit store and caches it for its complications.
- **iPad:** has its own local configuration and reads its own Health data (no sync between iPhone and iPad, which is acceptable).

## 4. Apple Health metrics

Support all Health data types that make sense as a goal; leave out the silly ones. Starting list:

- **Activity:** steps, active energy, exercise minutes, stand hours, flights climbed
- **Distance:** walking + running, cycling, swimming, wheelchair
- **Workouts:** number of workouts or workout minutes, optionally filtered by workout type (running, strength, yoga, etc.)
- **Recovery and mind:** sleep duration, mindful minutes, time in daylight
- **Nutrition:** water

Notes:
- Ask only for **read** access to the types actually in use, and request it when the user adds a ring that needs a new type.
- Cumulative quantities: `HKStatisticsCollectionQuery` with `.cumulativeSum`, bucketed by the ring's period.
- Workouts: `HKWorkout` queries. Sleep: category samples, summing asleep stages without double counting.
- Respect locale units (km/mi, kcal/kJ) via `HKUnit` and `Measurement` formatting.
- Widgets cannot reliably read HealthKit, for example when the device is locked. The app should compute progress and **cache it in the App Group**, then reload widget timelines. Use `HKObserverQuery` with background delivery where allowed. Widgets render from the cache.

## 5. Periods and calendar

Each ring has its own period. There are two kinds:

**Fixed periods** reset when the period ends. Reach the goal before the period ends, then start over.
- Presets: **today, this week, this month**, aligned to calendar boundaries in the user's time zone.
- **Custom fixed:** every N days or every N weeks, counted from a start date the user picks (e.g. "every 2 weeks from Monday 5 Jan").

**Rolling periods** move with time and never reset. They show the sum of the last N days up to now, like Heart Minutes and Google Fit's weekly Heart Points. The point is to stay above the goal all the time.
- Presets: **last 3, 7, 14 and 30 days**.
- **Custom rolling:** last N days, N chosen freely (e.g. 1–90).
- The value can go down as old data drops out of the window. Caches and widgets must allow that (see `ComplicationStore.shouldReplace` in Heart Minutes, where rolling periods may decrease).

Calendar rules:
- The week start **defaults to the device region** (`Calendar.current.firstWeekday`). A setting lets the user override it (Monday / Sunday / Saturday). Note: Heart Minutes hard-codes ISO weeks (Monday). Everyring must not.
- Fixed whole-day periods move in calendar days, so daylight saving time doesn't shift them.
- The UI shows the period clearly on each ring, e.g. "This week · 3 days left" or "Last 7 days".

Model it as one enum, something like:

```swift
enum RingPeriod: Codable, Hashable {
    case today, thisWeek, thisMonth
    case everyDays(Int, from: Date)     // custom fixed
    case everyWeeks(Int, from: Date)    // custom fixed
    case rollingDays(Int)               // last N days
}
```

with `interval(now:calendar:)`, `title`, `isRolling` and `next/previous` for history.

## 6. Motivation features

- **Close animation + haptics** when a ring reaches 100%. A ring may go past 100% and wrap around like Apple's.
- **Streaks per ring:**
  - Fixed periods: number of consecutive *periods* in which the ring was closed (days, weeks, months or the custom period).
  - Rolling periods: number of consecutive days on which the rolling window ended at or above the goal (checked at the end of each day).
  - Show current and best streak.
- **History:** a calendar/list showing each past period per ring, with mini rings and completion state. For rolling rings, show the window value per day as a line chart with the goal line. Compute it from HealthKit data, using a cache where useful.
- **No notifications in v1.**

## 7. Design

- **Follows the system appearance** (light/dark).
- The rings are custom-drawn in SwiftUI (gradient stroke, round caps, overlap shadow at the ring end past 100%).
- **Important:** Apple's HIG forbids using Apple's Activity rings in app icons or marketing. The Everyring rings must have their own clearly distinct visual identity (own palette, own icon), not a copy of Apple's Move/Exercise/Stand rings.
- The rings must stay readable at 5 rings in a small widget and a watch complication. Scale stroke width with the number of rings.
- Support Dynamic Type and VoiceOver (each ring reads as e.g. "Running, 14 of 20 kilometers this week, 70 percent").

## 8. App structure (suggestion)

1. **Home:** swipeable ring sets; the large concentric ring view with a list of rings below (value, goal, period, streak).
2. **Ring detail:** progress, history, streaks, edit.
3. **Ring editor:** pick metric → goal + unit → period → name/color/icon. Show a live preview.
4. **Set editor:** name, reorder rings (max 5), delete.
5. **Settings:** first day of week, Health permissions, about.
6. **Onboarding:** short explanation, Health permission, and a suggested starter set the user can edit.

## 9. Business model

- **Completely free.** No IAP, no ads, no analytics SDKs, no account. All data stays on the device.
- Add a privacy policy page stating that Health data never leaves the device, as required by App Review for HealthKit apps.

### Open source

- The code is **open source** in a **public GitHub repo** (e.g. `usernamefourzerofour/Everyring`), under the **MIT license** like Heart Minutes.
- **Never commit secrets:** no signing certificates, provisioning profiles, API keys, App Store Connect keys or team-specific xcconfig files. Keep them on the NoMac Mac (as in Heart Minutes) and list local files in `.gitignore`.
- Keep the generated `.xcodeproj` out of git; `project.yml` (XcodeGen) is the source of truth.
- The README explains what the app does, how to build it (`xcodegen generate`) and which bundle IDs and App Group others must change to run it on their own devices.
- Host the privacy policy and support page with GitHub Pages from `/docs`, like Heart Minutes.
- Code, comments, commit messages and docs are in English.

## 10. Reuse from Heart Minutes

Erik already has a published app with the same architecture: **github.com/usernamefourzerofour/HeartMinutes** (iPhone + Watch, HealthKit, widgets, complications, MIT). Clone it and reuse patterns and code instead of starting from zero:

| Heart Minutes file | Reuse for |
|---|---|
| `CLAUDE.md` | Working conventions with Erik and the full **NoMac build/upload/TestFlight workflow**. Copy and adapt it as Everyring's own `CLAUDE.md`. |
| `project.yml` | XcodeGen setup for app, widget, watch app and watch widget targets, App Group entitlements |
| `HeartMinutes/Period.swift`, `Shared/ComplicationStore.swift` (`SummaryPeriod`) | Fixed and rolling period logic, labels, DST-safe shifting, "refresh to now" |
| `Shared/WidgetCore.swift`, `Shared/HeartProgress.swift` | Ring drawing and progress model, generalize to up to 5 concentric rings |
| `HeartMinutes/HealthManager.swift` | HealthKit authorization and queries |
| `HeartMinutes/WidgetUpdater.swift`, `PhoneSync.swift`, `HeartMinutesWatch/WatchSync.swift` | App Group cache, widget reloads, iPhone → Watch sync |
| `HeartMinutes/HeartViews.swift` (`PeriodPicker`) | Period picker UI with presets and the fixed-vs-rolling explanation |
| `HeartMinutesTests/PeriodTests.swift` | Starting point for period tests |

Differences to keep in mind: Everyring has many Health metrics instead of only heart rate, up to 5 rings per set, multiple sets, iPad support, and a region-based week start.

## 11. Build, test and ship

- Build and test **via NoMac** (cloud Mac), following the workflow in Heart Minutes' `CLAUDE.md`: XcodeGen, signing, simulator tests, archive, TestFlight. Ask Erik before starting a Mac, and always stop it afterwards.
- Bundle ID: `<TODO: e.g. dk.erik.everyring>`, App Group e.g. `group.dk.erik.everyring`. Use the same App Group and team for app, widget extension, watch app and watch widget extension.
- Add the HealthKit capability and usage descriptions (`NSHealthShareUsageDescription`), plus background delivery entitlement if used.
- Unit tests for period boundary math (week start variants, month lengths, DST and time-zone changes) and streak calculation.
- Reserve the app name "Everyring" in App Store Connect early.

## 12. Suggested milestones

1. Data model + period engine (fixed, custom fixed, rolling) + streak engine with tests (no UI).
2. HealthKit reading for 3–4 core metrics + home screen with one ring set.
3. Ring and set editors, multiple sets, settings (week start).
4. Widgets (home + Lock Screen) reading from the App Group cache.
5. Watch app + complications via WatchConnectivity.
6. History view, close animation/haptics, remaining Health metrics.
7. Polish, accessibility, app icon, TestFlight.

## Out of scope for v1

Manual logging, notifications, iCloud sync, sharing/social, quarter and year periods, localization beyond English, Mac app.

---

## Decisions (2026-11-15)

- Bundle ID `dk.erik.everyring` (+ `.widget`, `.watchkitapp`, `.watchkitapp.widget`), App Group `group.dk.erik.everyring`.
- Minimum OS: iOS / iPadOS / watchOS 27.
- Workout rings can measure count, minutes or **distance**, optionally filtered by workout type (e.g. running distance).
- The example "Heart minutes 150 in the last 7 days" uses **exercise minutes**; Heart Minutes doesn't write to Health.
- Sleep counts on the day you wake up.
- A period in progress never breaks a streak; it adds to it once the goal is reached.
- Rolling windows are whole calendar days: today plus the previous N − 1 days (so the oldest day drops out at midnight).
- Configuration and cache are Codable JSON in the App Group container (not SwiftData): small, easy to send to the Watch
  and to read from widgets.
- Work happens directly on `main`.
- Every summable Health type is offered as a ring. Medical, reproductive and symptom types (insulin, inhaler, falls,
  heart/breathing/hearing notifications, sexual activity, cycle tracking, symptoms) are only offered in builds with the
  `SENSITIVE_METRICS` compilation condition, set for TestFlight in project.yml. Before an App Store release, remove it
  unless it is decided they may stay: Everyring can't vouch for their precision and must not give medical advice
  (decided 2026-11-16, revised 2026-11-22).
- Rings can be goals to reach or limits to stay under (turn red when exceeded).
- Rings of several days can count a total or a daily average (goal per day, e.g. 8 h sleep a night over the last 30 days). The average divides by all the days of a finished period or rolling window, and by the days so far (today included) in a fixed period in progress; days without data count as zero by default; a ring setting can leave them out instead.
- Workout rings can count only some workout types or all but some, and can ignore short workouts.
- Activity rings (steps, active energy, exercise minutes, walking + running distance) can leave out what was logged while workouts of chosen types ran (Health doesn't tie samples to workouts, so it goes by time; most activity is everyday life, so there is no "only these"). Their detail screen lists the period's workouts with what was logged during each.
- Rings of several days can count a total, a daily average, or the days that reach a daily target ("10,000 steps on 5 days"); and can count only weekdays or weekends.
- Any ring can be limited to data from chosen apps and devices.
- Sleep stages (core, deep, REM) are rings of their own, counted on the night they belong to.
