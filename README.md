# NextCast

A tiny, movable "what do I cast next?" box for **Shadow Priests** on TBC Classic (Anniversary).

![Interface: 2.5.6](https://img.shields.io/badge/TBC-2.5.6-purple)

## Screenshots

| | |
|---|---|
| ![Opener suggestion](assets/initial-cast.png) | ![DoT tracker](assets/with-debuffs-up.png) |
| *Opener suggestion on a fresh target* | *DoTs running with time remaining* |
| ![Mid-fight timers](assets/with-debuffs-up-2.png) | ![Clip signal](assets/clip-it.png) |
| *Tracker mid-fight* | *Red CLIP signal: cut the Mind Flay channel now* |

## What it does

- **Next-cast icon** — one icon showing the spell you should press next, following the
  standard TBC shadow priority: Shadowform → Vampiric Touch → Shadow Word: Pain →
  Vampiric Embrace → Mind Blast → Shadow Word: Death → racial DoT → Shadowfiend
  (low mana) → Mind Flay.
- **Racial DoTs** — Devouring Plague (Undead) and Starshards (Night Elf) are woven in
  above Mind Flay, per standard priority. DP is only suggested while your mana is
  healthy (≥60%) — it's a DPS gain with a huge mana cost, so it's the first cut when
  you're running dry. Both get tracker slots automatically on races that have them.
- **Predictive** — reads your cast bar and evaluates cooldowns and DoT timers *as of the
  moment your current cast finishes*, so mid-cast it already shows your next press.
  DoT refreshes are timed so the new application lands right after the old one's final
  tick (haste-aware, so the window tightens under Bloodlust).
- **DoT tracker** — your SW:P / VT / VE on the target, with cooldown-sweep overlays and
  remaining time (red under 3 seconds).
- **Mind Flay clip signal** — once your 2nd flay tick has fired and something better is
  ready, the border turns red with a "CLIP" label: cut the channel now.
- **Burst alert** — during Bloodlust/Heroism, a pulsing pop-out suggests Destruction
  Potion (if in bags and off the potion cooldown), then any equipped on-use trinket
  that's ready.
- **Inner Focus pairing** — when IF is ready and the suggestion is Devouring Plague or
  SW:P, the pop-out flashes Inner Focus first: DoTs can't crit in TBC, so IF is a mana
  cooldown and belongs on your most expensive DoT. On Undead it holds IF for DP when
  DP is nearly off cooldown.
- **SW:D safety** — estimates the worst-case crit backlash from your rank, shadow spell
  power, and damage modifiers; when it could kill you, the Shadow Word: Death suggestion
  is shown with a red danger overlay so casting it is your informed call.
- **Time until OOM** — projects when you'll run dry from your average net mana drain
  this fight (yellow under 30s, red under 10s). Only shown in combat while you're
  actually draining.
- **Target time-to-die** — the same estimate pointed at the target's health, shown
  next to the OOM timer. It also makes suggestions smarter: DoTs aren't suggested on
  mobs that won't live long enough to pay for their GCD (VT needs ~8s, SW:P ~6s,
  DP ~12s), so on dying trash the addon steers you to direct damage instead.
- **Latency-aware timing** — DoT refresh windows include your live world latency, so
  recasts land on time at real ping.
- **Post-fight report** — after fights of 30+ seconds, a one-line chat summary: SW:P
  and VT uptime %, mana returned to your group via Vampiric Touch, Vampiric Embrace
  healing, and Mind Blast / SW:D cast counts.
- Only suggests spells you actually know, so it works while leveling too.

This is a **suggestion display only** — it never casts anything for you, which keeps it
fully within Blizzard's addon policy.

## Commands

`/nextcast` or `/nc`

| Command | Effect |
|---|---|
| `/nc unlock` / `/nc lock` | Unlock to drag the box, lock it in place |
| `/nc hide` / `/nc show` | Hide or show the box entirely |
| `/nc reset` | Reset position |
| `/nc scale <0.5–3>` | Resize |
| `/nc swd` | Toggle Shadow Word: Death suggestions |
| `/nc ve` | Toggle Vampiric Embrace suggestions |
| `/nc fiend` | Toggle Shadowfiend (low-mana) suggestions |
| `/nc lust` | Toggle potion/trinket alerts during Lust/Heroism |
| `/nc clip` | Toggle the Mind Flay clip indicator |
| `/nc oom` | Toggle the time-until-OOM display |
| `/nc racial` | Toggle racial DoT suggestions (Devouring Plague/Starshards) |
| `/nc focus` | Toggle Inner Focus pairing alerts |
| `/nc ttd` | Toggle the target time-to-die display |
| `/nc report` | Toggle post-fight reports |

## Installation

Copy the `NextCast` folder into
`World of Warcraft/_anniversary_/Interface/AddOns/` and restart the client.

## Known limitations

- The burst alert suggests **any** equipped on-use trinket — including a PvP Medallion.
- Only Bloodlust/Heroism trigger the burst alert (not Drums of Battle or Power Infusion).
- Shadow Priest only, for now.
