**Know your next cast. Always.**

NextCast is a tiny, movable box that shows Shadow Priests exactly one thing: the icon of the spell you should press next. No bars, no spreadsheets, no clutter — one icon, plus your DoTs on the target underneath with their remaining time.

![NextCast in action](https://raw.githubusercontent.com/YOURUSER/NextCast/main/assets/with-debuffs-up.png)

**It's predictive, not reactive**

NextCast reads your cast bar and evaluates your cooldowns and DoT timers as of the moment your current cast will finish. While you're casting Vampiric Touch, it already shows what comes after. If Mind Blast has 0.8 seconds left on cooldown and your cast ends in 0.7 — it knows Mind Blast is next. DoT refreshes are timed so the new application lands right after the old one's final tick, with no clipped ticks and no downtime, and the timing is haste-aware so the refresh window tightens automatically under Bloodlust/Heroism.

**Features**

- Next-cast suggestion following the standard TBC shadow priority: Shadowform, Vampiric Touch, Shadow Word: Pain, Vampiric Embrace, Mind Blast, Shadow Word: Death, racial DoTs, Shadowfiend (when low on mana), Mind Flay
- Racial DoT support — Devouring Plague (Undead) and Starshards (Night Elf) woven in above Mind Flay; Devouring Plague is only suggested while your mana is healthy, since it's a DPS gain with a huge mana cost
- DoT tracker — your SW:P, VT, and VE on the current target with cooldown sweeps and remaining time, red when about to fall off
- Mind Flay clip signal — after your 2nd flay tick, if something better is ready, the border turns red with a "CLIP" label: cut the channel now
- SW:D danger warning — estimates the worst-case crit backlash from your rank, spell power, and damage modifiers; when it could kill you, the suggestion shows under a red overlay so it's your informed call
- Burst alerts — during Bloodlust/Heroism, a pulsing pop-out reminds you to use Destruction Potion or your on-use trinkets the moment they're available
- Inner Focus pairing — when Inner Focus is ready and your next cast is Devouring Plague or Shadow Word: Pain, the pop-out reminds you to press it first, so the free cast lands on your most expensive DoT (DoTs can't crit in TBC, so that's exactly where theorycraft says IF belongs)
- Time until OOM — a live estimate of when you'll run dry, projected from your average net mana drain this fight (spell costs, Spirit Tap, VT returns, and mp5 all included automatically); yellow under 30 seconds, red under 10
- Target time-to-die — the same live estimate pointed at your target's health, and it makes the suggestions smarter: no more DoT suggestions on mobs that will die before the DoT pays off — on dying trash you're steered to direct damage instead
- Latency-aware timing — DoT refresh windows account for your live world latency, so recasts land on time at your real ping
- Post-fight report — after fights of 30+ seconds, a one-line chat summary: SW:P and VT uptime, mana returned to your group via Vampiric Touch, Vampiric Embrace healing, and Mind Blast / SW:D cast counts
- Works while leveling — only suggests spells you actually know
- Lightweight — one aura scan per update, no per-update memory allocations, and it doesn't scale with raid combat intensity

**Screenshots**

![Opener suggestion on a fresh target](https://raw.githubusercontent.com/YOURUSER/NextCast/main/assets/initial-cast.png)

![DoT timers running mid-fight](https://raw.githubusercontent.com/YOURUSER/NextCast/main/assets/with-debuffs-up-2.png)

![The red CLIP signal: cut the Mind Flay channel now](https://raw.githubusercontent.com/YOURUSER/NextCast/main/assets/clip-it.png)

**Commands**

- /nc unlock — unlock the box so you can drag it anywhere
- /nc lock — lock it in place
- /nc hide — hide the box entirely
- /nc show — bring it back
- /nc scale 0.5–3 — resize
- /nc reset — reset position
- /nc swd — toggle Shadow Word: Death suggestions
- /nc ve — toggle Vampiric Embrace suggestions
- /nc fiend — toggle Shadowfiend (low-mana) suggestions
- /nc lust — toggle potion/trinket alerts during Bloodlust/Heroism
- /nc clip — toggle the Mind Flay clip indicator
- /nc oom — toggle the time-until-OOM display
- /nc racial — toggle racial DoT suggestions (Devouring Plague/Starshards)
- /nc focus — toggle Inner Focus pairing alerts
- /nc ttd — toggle the target time-to-die display
- /nc report — toggle post-fight reports

**Fair play**

NextCast is a suggestion display only. It never casts, queues, or automates anything — you make every decision and every keypress. It simply does the DoT math so you can watch the fight instead of your debuff bar.

**Roadmap**

Shadow Priest is the first spec — more classes are planned. Feedback and suggestions welcome in the comments.
