# To do

Open work for Everyring, newest ideas last. Move an item to `HANDOVER.md` → Decisions once it is built and settled.

## Next

- **Top priority: make the direction of ring progress clear.** Start each ring with a lighter colour at 12 o’clock and build to the strongest colour at the moving tip. Keep the tip visible where the ends overlap. Check the 98% sleep-ring example, exactly 100%, and rings beyond one full lap.

- **Graph widget from Heart Minutes.** Bring Heart Minutes' graph widget over: a widget that shows a ring's
  history as a chart (bars or a line per day, with the goal), in Everyring's own look and for any ring. Fits Erik's
  wish for few widgets: one widget with a setting for which ring, not one widget per metric.
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

- Remove `SENSITIVE_METRICS` from `project.yml` (medical, reproductive and symptom types), unless it is decided they
  may stay. See `Shared/SensitiveMetrics.swift`.

## Later

- **Everything from Heart Minutes in Everyring.** Go through Heart Minutes (github.com/usernamefourzerofour/HeartMinutes)
  feature by feature and bring over what Everyring lacks (its views, widgets, complications, settings and the heart
  minute calculation itself), so Everyring can replace it. Start with a list of Heart Minutes' features and what
  Everyring already covers.
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
