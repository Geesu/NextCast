# Changelog

## 1.0.2 (2026-07-11)

- Balance Druid support: Moonkin Form → Faerie Fire (anyone's counts) → Moonfire (while mana is healthy) → Starfire filler, with Innervate suggested on bosses at low mana (`/nc mana` toggles it); FF/MF tracker row and a druid post-fight report (IS/MF uptime, SF/Wrath casts)
- Insect Swarm is only suggested (and tracked) while wearing 4pc Tier 5 — per sims, keeping the set's +10% Starfire buff up is the one case where IS beats casting more Starfire
- NextCast learns how long each mob type lives (per instance difficulty) from your kills; the DoT time-to-die gates use that from the very first GCD of a pull, instead of waiting ~3 seconds for the live estimate to warm up — so dots stop being suggested on trash that historically dies before they pay off
- Vampiric Embrace suggestions are now off by default and boss-only — trash dies too fast for the group healing to matter; `/nc ve` opts it into the boss rotation
- Devouring Plague is only suggested on bosses, so its 3-minute cooldown isn't burned on trash right before a pull
- Shadowfiend is now suggested only on bosses and below 20% mana (was 50%, any target) — you can drink between trash packs, and its 5-minute cooldown belongs to the boss
- The box now starts unlocked on a fresh install so new users can drag it into place right away — `/nc lock` once positioned
- `/nc fiend` is now `/nc mana`, toggling the low-mana cooldown suggestion for either class (Shadowfiend/Innervate); `fiend` still works as an alias
- Boss detection recognizes 5-man dungeon bosses (high-level elites inside instances), not just skull/raid bosses — the boss-gated suggestions now work in dungeons and heroics
- On druids the box only appears once Moonkin Form is known, so resto and feral druids don't get DPS suggestions
- Mob lifetimes are measured from the mob's actual first combat activity and survive mid-fight combat drops, so learned averages aren't biased short by late joins or boss phase transitions

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
