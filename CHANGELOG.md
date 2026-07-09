# Changelog

## 1.0.1 (2026-07-09)

- Time-until-OOM display: live countdown to empty mana from your actual net drain rate, shown under the DoT row in combat (`/nc oom` to toggle)
- Racial DoT support: Devouring Plague (Undead) and Starshards (Night Elf) join the priority above Mind Flay, with a tracker slot; Devouring Plague is only suggested while mana is healthy (`/nc racial` to toggle)
- Inner Focus pairing alert: when IF is ready and the suggestion is Devouring Plague or SW:P, the pop-out reminds you to press it first; holds IF for DP on Undead when DP is nearly ready (`/nc focus` to toggle)
- Target time-to-die: live estimate shown next to the OOM timer, and DoTs are no longer suggested on mobs that will die before they pay off (`/nc ttd` toggles the display)
- Latency-aware DoT refresh windows via live world ping
- Post-fight report: one-line summary after 30s+ fights — SW:P/VT uptime, VT mana returned to group, VE healing, MB/SW:D casts (`/nc report` to toggle)

## 1.0.0 (2026-07-08)

Initial release.

- Next-cast suggestion box for TBC Shadow Priests (draggable, scalable, always visible)
- Predictive logic: evaluates cooldowns and DoT timers as of the end of your current cast;
  haste-aware Vampiric Touch refresh timing
- SW:P / VT / VE tracker row with cooldown sweeps and remaining-time text
- Mind Flay clip indicator (red border + "CLIP" after the 2nd tick when something better is ready)
- Destruction Potion / on-use trinket alert during Bloodlust or Heroism
- Shadow Word: Death crit-backlash safety check (red danger overlay when it could kill you)
- Shadowfiend suggestion when below 50% mana in combat
- Post-cast grace window (per-target) so suggestions don't flicker while auras are in flight
- Slash commands: lock/unlock, hide/show, reset, scale, and per-feature toggles
