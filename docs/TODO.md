# To do

Open work for Everyring, newest ideas last. Move an item to `HANDOVER.md` → Decisions once it is built and settled.

## Next

- **Top priority: make the direction of ring progress clear.** Start each ring with a lighter colour at 12 o’clock and build to the strongest colour at the moving tip. Keep the tip visible where the ends overlap. Check the 98% sleep-ring example, exactly 100%, and rings beyond one full lap.

- **High priority (Erik will use it): Screen Time rings.** Screen time is not in Apple Health; it comes from Apple's
  Screen Time API (FamilyControls with `.individual` authorization, DeviceActivity). Limits to design around:
  - Needs the **Family Controls entitlement**, which Apple must approve before App Store distribution (request form).
    Check early whether it works on TestFlight / development without approval.
  - **Real numbers can only be shown inside the app**, in a `DeviceActivityReport` extension view: the app itself can't
    read the usage, so it can't write it to the App Group for widgets or send it to the watch.
  - **Widgets:** approximate with a `DeviceActivityMonitor` extension and usage thresholds (e.g. every 15 min), which
    the extension writes to the App Group. Show it as approximate.
  - iPhone and iPad only (no watch data). Rings for total screen time or chosen apps/categories (social, games), today
    or per week, usually as limits ("stay under 2 hr").
  - Start with a small prototype on TestFlight to see what the API allows, then decide on the design.

- **Graph widget from Heart Minutes.** Done: "Ring and Chart" (one ring and a chart of its period, small/medium/large).
  Maybe later: the zone bar on the large widget for Heart Minutes rings.
- **Rings on the watch:** should the watch also write icon and percentage on its rings, like the iPhone? (Asked,
  not answered yet.)

- **Bedtime and get-up time rings.** Add Bedtime and Get-up Time as separate metrics. Each ring can use either mode:
  - **Clock-time target:** Set a local target time and a tolerance (e.g. bedtime at 22:30 ± 30 min).
    For a single night, show the actual time and its deviation from the target. Over multiple nights,
    score the share of recorded nights within tolerance.
  - **Consistency:** Choose a fixed or rolling period (e.g. the last 14 days) and a maximum acceptable
    variation in minutes. Measure how much the recorded times vary within that period, independently of
    any target time. Show the variation in minutes alongside the ring. A schedule can be consistent
    even when it regularly misses the clock-time target.
  - Treat clock times on either side of midnight as close together (23:55 and 00:05 are 10 min apart).
    Assign each night to its wake date, following the existing sleep rings. Exclude missing nights
    from the calculations, show how many nights were recorded, and require at least two observations
    for consistency.
  - Check whether Apple Health provides actual in-bed and get-up times. If only sleep onset and final
    awakening are available, label those clearly as estimates of bedtime and get-up time.

## Before the App Store

- **Heart Minutes is one of the headline features** in the App Store listing and marketing: minutes in the moderate
  and vigorous heart-rate zones (AHA: 150 min a week), calculated from heart rate with the background-activity
  filter, on any ring and in the Ring and Chart widget. Name it early in the description and show it in a screenshot.
- **Feature "When closed: fade / hide" in the App Store listing.** Erik loves it. Make it part of the pitch, with the idea
  behind it: *you should only be shown the data you need to act on.* Rings you've already closed step back, so a
  glance at the widget shows what's left to do today. Use it in the subtitle or first lines of the description and in
  one of the first screenshots (a widget with closed rings faded and one or two still bright).
- Remove `SENSITIVE_METRICS` from `project.yml` (medical, reproductive and symptom types), unless it is decided they
  may stay. See `Shared/SensitiveMetrics.swift`.

## Later

- **Everything from Heart Minutes in Everyring.** Go through Heart Minutes (github.com/usernamefourzerofour/HeartMinutes)
  feature by feature and bring over what Everyring lacks, so Everyring can replace it. Done: the Heart Minutes metric
  with its calculation and settings (zones, max heart rate, background activity filter, gaps). Still to do: the zone
  breakdown and the heart-rate chart with zone bands on the detail screen, the comparison with Exercise minutes, the
  hint about background measurements without Apple Watch's active marking, and the 38 languages.
  - **Time in heart rate zones.** Let a ring count minutes in one or more selected zones across activities,
    for example 90 minutes in zone 2 over the last seven days.
- **Time windows for existing rings.** Add an optional local time window that works with weekday and period
  settings. For example, count days with 20 minutes of daylight between 07:00 and 10:00, or track caffeine
  consumed after 14:00.
- **Custom exercises and repetitions.** Record or import repetitions per set for a named exercise. Let the
  ring track either the best single set (100 consecutive push-ups) or the total over a period (200 in a week).
- **Best single workout.** Add a workout aggregation that takes the greatest distance or duration among
  matching workouts in the period. A 10 km monthly walking goal in this mode requires one 10 km walk.
- **Longest uninterrupted sleep.** Track the longest recorded sleep stretch per night. Join adjacent sleep
  stages across transitions, split at recorded awakenings, and avoid counting gaps in the data as sleep.

## Rings from data outside Apple Health

Suggested order: manual rings and Shortcuts first (easy, very useful), then motion (no extra permission), then Screen
Time (see Next), then places.

- **Manual rings and Shortcuts (App Intents).** Rings you count up yourself: a + button in the app, an interactive
  widget button, Siri ("read 20 pages", "played guitar", "called mum", "coffee"). Plus a Shortcuts action "Add to
  ring" so automations and other apps can log values. Values stored by Everyring in the App Group (not Health).
- **Motion (Core Motion, `CMMotionActivityManager`).** No extra approval beyond Motion & Fitness. Minute by minute:
  - Time in a car (driving), e.g. a limit of 1 hr a day, or less car than last week.
  - Time cycling; time walking and running, also outside workouts.
  - Time stationary, e.g. at most 8 hr still.
  - Share of active transport: cycling and walking versus car ("70 % without a car").
  - iOS keeps only the last 7 days: Everyring must record history itself (e.g. on each refresh and in the background).
- **Places (Core Location: visits and regions).** Needs location "Always" (App Review is strict; explain it well).
  Battery use is low with visit monitoring.
  - Time at home and away from home ("at least 2 hr out every day").
  - Visits to a place ("gym 3 times a week", "forest or beach once a week").
  - Time at work ("at most 40 hr a week").
  - New places visited ("one new place a month").
  - Distance travelled, e.g. by car ("at most 200 km a week"), together with motion.
- **Calendar and reminders (EventKit).**
  - Time in meetings ("at most 15 hr a week"); free evenings without events.
  - Completed reminders ("20 tasks a week").
- **Photos (PhotoKit).** Photos taken ("one photo a day", as a diary).
- **Weather (WeatherKit) with location.** Time outdoors in good weather; walks in daylight (time in daylight is
  already a Health ring).
- **Spending (FinanceKit).** US only for now: Apple Card / Apple Cash spending, e.g. a limit on takeaway.

