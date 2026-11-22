# To do

Open work for Everyring, newest ideas last. Move an item to `HANDOVER.md` → Decisions once it is built and settled.

## Next

- **Graph widget from Heart Minutes.** Bring Heart Minutes' graph widget over: a widget that shows a ring's
  history as a chart (bars or a line per day, with the goal), in Everyring's own look and for any ring. Fits Erik's
  wish for few widgets: one widget with a setting for which ring, not one widget per metric.
- **Rings on the watch:** should the watch also write icon and percentage on its rings, like the iPhone? (Asked,
  not answered yet.)

## Before the App Store

- Remove `SENSITIVE_METRICS` from `project.yml` (medical, reproductive and symptom types), unless it is decided they
  may stay. See `Shared/SensitiveMetrics.swift`.

## Later

- **Everything from Heart Minutes in Everyring.** Go through Heart Minutes (github.com/usernamefourzerofour/HeartMinutes)
  feature by feature and bring over what Everyring lacks (its views, widgets, complications, settings and the heart
  minute calculation itself), so Everyring can replace it. Start with a list of Heart Minutes' features and what
  Everyring already covers.
