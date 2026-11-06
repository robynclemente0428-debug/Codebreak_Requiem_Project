# CodeBreak Requiem: Simplified Campaign (Boss Focus)

*Draft v2. Silent protagonist, five NPCs, ten boss quests.*

## The Story in Four Lines

The Executor wakes in Hardfault, the last safe settlement in AXIOM. The Null (corrupted code) is spreading from the Core. Each region is ruled by a boss. Beat the bosses, reach the Core, and choose how it ends.

## Writing Rules

The Executor never speaks. The player only picks buttons: **[Accept]**, **[Decline]**, **[Turn in]**. NPC lines are one or two sentences. Every quest has three beats: **Offer**, **Accept**, **Complete**. Every boss has a **Boss Trait** (a simple pattern the player can exploit) and a **Script Task** (a small coding challenge that ties into rank progression).

## Cast (5 NPCs)

| Name | Role | Personality | Acts |
|---|---|---|---|
| The Executor | Player, silent (nods, shrugs, salutes only) | n/a | I to V |
| Warden Brack | Leader of Hardfault, gives most boss quests | Blunt, tired | I to III |
| Tinker Hex | Trader and trade point | Sarcastic, fair | I to V |
| Examiner Sudo | Rank examiner | Dry, patient | I to V |
| Vesper | Null Speaker, guide to the Core | Calm, eerie | IV, V |

The Last Log (a recorded voice) appears only in Act V.

## Boss Ladder

| # | Boss | Act | Region |
|---|---|---|---|
| 1 | Glitchling Queen | I | Hardfault Outskirts |
| 2 | Corrupted Gate Guard | I | Hardfault Gate |
| 3 | Loop Hound Alpha | II | Fragmented Zone |
| 4 | The Overflow | II | Fragmented Zone |
| 5 | The Leak | III | Checkpoint |
| 6 | The Mimic | III | Checkpoint |
| 7 | Null Weaver Prime | IV | Null Zone |
| 8 | Null Gatekeeper | IV | Null Zone |
| 9 | Core Sentinel | V | The Core |
| 10 | Root Process | V | The Core |

---

## Act I: Hardfault

**Goal:** Teach combat and the script editor.

### Opening Scene

**Brack:** You’re alive. Good. Something woke up in you, and we need it.

### Quest 1: The Glitchling Queen

**Giver:** Brack
**Objective:** Defeat the Glitchling Queen and her swarm.
**Boss Trait:** Spawns small Glitchlings every 10 seconds. Kill the Queen to stop them.
**Script Task:** Edit your starter skill so it only fires `if enemy_near`.

**Offer — Brack:** A Queen is breeding Glitchlings near the wall. Kill her.

**Accept — Brack:** Open your skill editor first. Tell your skill when to fire.

**Complete — Brack:** Wall’s holding. You’re useful. I’ll admit it.

### Quest 2: The Corrupted Gate Guard

**Giver:** Brack
**Objective:** Defeat the Corrupted Gate Guard.
**Boss Trait:** Slow, heavy swings. Dodge, then strike.
**Script Task:** Pass Examiner Sudo’s first rank exam.

**Offer — Brack:** The Gate Guard went rogue. Nobody gets in or out until it falls.

**Accept — Brack:** Sudo will test your scripts first. No test, no rank.

**Complete — Brack:** The gate is open. Time to move.

### Examiner Sudo (Rank Exam)

**Offer — Sudo:** Show me your script. I grade logic, not luck.

**Pass — Sudo:** Clean and efficient. Rank up.

**Fail — Sudo:** Too many wasted steps. Trim it and try again.

### Tinker Hex (First Trade)

**Hex:** Trading is simple. You offer, I offer, we both complain.

---

## Act II: The Fragmented Zone

**Goal:** Introduce loops and tougher patterns.

### Quest 3: Loop Hound Alpha

**Giver:** Brack
**Objective:** Defeat Loop Hound Alpha.
**Boss Trait:** Charges in the same path again and again. Learn the loop, break it.
**Script Task:** Add a loop with an exit condition so your skill doesn’t repeat forever.

**Offer — Brack:** Alpha leads the pack that blocks our road. Cut off the head.

**Accept — Brack:** Give your skill a stop condition, or you’ll chase it forever.

**Complete — Brack:** The hounds scatter without him. Road’s clear.

### Quest 4: The Overflow

**Giver:** Hex
**Objective:** Defeat The Overflow, a giant Stack Crawler.
**Boss Trait:** Gets stronger as more enemies stack on it. Kill the small ones first.
**Script Task:** Equip an item with a script modifier (for example, +damage `if health < 50%`).

**Offer — Hex:** A big crawler is sitting on all my power cells. Kill it and I’ll pay well.

**Accept — Hex:** Don’t let it stack up. Clear the small ones first.

**Complete — Hex:** My cells! Here’s your reward. A better weapon, as promised.

---

## Act III: Checkpoint

**Goal:** Introduce functions and unpredictable bosses.

### Quest 5: The Leak

**Giver:** Brack
**Objective:** Defeat The Leak, a mass of corrupted memory.
**Boss Trait:** Splits into smaller blobs when hit. Use area attacks.
**Script Task:** Write a skill that uses a function (`def`) you call more than once.

**Offer — Brack:** Something is eating Checkpoint’s memory. It splits every time we hit it.

**Accept — Brack:** Hit it hard and hit it wide. A reusable function helps.

**Complete — Brack:** The leak is sealed. We can finally rest.

### Quest 6: The Mimic

**Giver:** Brack
**Objective:** Defeat The Mimic.
**Boss Trait:** Copies your equipped skill. Predictable scripts get used against you.
**Script Task:** Write a skill with a counter (variable) that changes its pattern each use.

**Offer — Brack:** A Null thing is copying everything we do. It copied my voice yesterday.

**Accept — Brack:** Vary your pattern. A copied skill is a defeated skill.

**Complete — Brack:** It’s gone. I never want to hear that voice again.

---

## Act IV: The Null Zone

**Goal:** Reveal that the Null has logic, and meet Vesper.

### Opening Scene

**Vesper:** You can hear it, can’t you? The Null speaks. You just never listened.

### Quest 7: Null Weaver Prime

**Giver:** Vesper
**Objective:** Defeat Null Weaver Prime.
**Boss Trait:** Weaves traps in patterns. Read the pattern, step through the gaps.
**Script Task:** Write a skill that uses nested conditionals (an `if` inside an `if`).

**Offer — Vesper:** The Weaver spins the Null’s grammar. Break it and you’ll hear the language.

**Accept — Vesper:** Don’t fear it. Read it.

**Complete — Vesper:** You see it now. The Null has logic. It isn’t just destruction.

### Quest 8: The Null Gatekeeper

**Giver:** Vesper
**Objective:** Defeat the Null Gatekeeper at the Core’s entrance.
**Boss Trait:** Shifts between a fast form and a slow, heavy form.
**Script Task:** Pass Examiner Sudo’s advanced rank exam.

**Offer — Vesper:** The Gatekeeper guards the Core. It will not let you pass.

**Accept — Vesper:** Prove your code is worthy. Sudo will test you first.

**Complete — Vesper:** The way is open. What you do next is yours alone.

---

## Act V: The Core

**Goal:** Final bosses and the ending choice.

### Quest 9: The Core Sentinel

**Giver:** The Last Log
**Objective:** Defeat the Core Sentinel.
**Boss Trait:** Combines patterns from earlier bosses (summons, loops, copies).
**Script Task:** None required. Use your best build.

**Offer — The Last Log:** You are the first to arrive. The Sentinel will test you.

**Accept — The Last Log:** It remembers every enemy you have faced.

**Complete — The Last Log:** The Sentinel falls. One guardian remains.

### Quest 10: The Root Process

**Giver:** The Last Log
**Objective:** Defeat the Root Process.
**Boss Trait:** Three phases. Each phase changes its attack pattern.
**Script Task:** None required. Use your best build.

**Offer — The Last Log:** The Root Process is the Core’s last defense. It cannot be reasoned with.

**Accept — The Last Log:** Break it, and the Core is yours to decide.

**Complete — The Last Log:** The Core is open. The choice is yours, Executor.

### The Choice

The player picks one action. The Executor stays silent.

**[Merge]**
**Vesper:** Let it finish. Let it become something new.

**[Overwrite]**
**Brack:** Save what we can. Keep us alive.

**[Terminate]**
**The Last Log:** Shutdown confirmed. Goodbye, Executor.

---

## Ambient Lines

**Brack:** Rest while you can.

**Hex:** Buying, selling, complaining. Pick two.

**Sudo:** Efficiency is just laziness with a plan.

**Vesper:** Listen. The silence has structure.

---

## Notes for Implementation

Each act has two bosses, so the campaign is a clean ladder of ten fights, and every boss teaches one scripting idea in order: conditionals, loops, modifiers, functions, variables, and nested logic. Rank exams sit after Act I and before the Core. Optional side quests (for example, kill 10 of a common enemy) can be added later for item drops and trading without changing the main story.
