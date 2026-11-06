# CodeBreak Requiem: Campaign Characters and Dialogue

*Draft v1. Silent protagonist, quest-driven NPCs.*

## Writing Rules

The Executor (the player) never speaks. The player only picks buttons: **[Accept]**, **[Decline]**, **[Ask more]**, **[Turn in]**. NPC lines stay short, one or two sentences each, so they are easy to put in dialogue boxes.

Every quest has four beats: **Offer**, **Accept**, **Reminder** (if the player talks to the NPC mid-quest), and **Complete**. Every quest also has a **Script Task**, a small coding challenge that connects the quest to rank progression and the step-count emulator.

Common enemies used below: Glitchlings (weak, fast), Bug Swarms, Loop Hounds, Stack Crawlers, Memory Leaks, Null Husks, and Null Weavers.

## Cast

| Name | Faction | Role | Personality | Acts |
|---|---|---|---|---|
| The Executor | None | Player character | Silent. Shown only through animations and emotes (nod, shrug, salute). | I to V |
| Warden Brack | Free Processes | Leader of Hardfault | Blunt, tired, protective | I, II |
| Pip | Free Processes | Young scout and messenger | Cheerful, fast-talking | I to III |
| Tinker Hex | Free Processes | Trader (trade point) | Sarcastic, fair dealer | I to V |
| Examiner Sudo | Independent | Rank examiner | Dry, patient, loves tests | I to V |
| Unit-07 (“Seven”) | Custodian Remnants | Loyal maintenance unit | Formal, literal | II, III |
| Archivist Lex | Compiler Guild | Scholar and code recoverer | Excitable, curious | III, IV |
| Vesper | Null Speakers | Guide into the Null | Calm, quiet, unsettling | IV, V |
| The Last Log | The Architects | Recorded voice at the Core | Gentle, distant | V |

---

## Act I: The Spawn Point

**Location:** Hardfault, a Free Process settlement in a collapsed relay tower.
**Goal:** Introduce combat, the script editor, and the first rank.

### Opening Scene

**Pip:** You’re alive! Everyone else in the outer ward is gone.

**Warden Brack:** Don’t stand there. Something woke up in you. We need that.

### Quest 1.1: First Boot

**Giver:** Warden Brack
**Objective:** Defeat 5 Glitchlings by the east wall.
**Script Task:** Edit the starter skill so it only fires `if enemy_near`.

**Offer — Brack:** Glitchlings are chewing through our wall. Go clear them out.

**Accept — Brack:** Good. Open your skill editor first. Tell your skill when to fire.

**Reminder — Brack:** Five Glitchlings. They’re small, but they bite.

**Complete — Brack:** Wall’s holding. You’re useful. I’ll admit it.

### Quest 1.2: Pip’s Package

**Giver:** Pip
**Objective:** Recover a supply crate from a Bug Swarm nest.
**Script Task:** Use a loop so your attack repeats 3 times.

**Offer — Pip:** I dropped a crate near the nest. Can you grab it? Please?

**Accept — Pip:** You’re the best! Bugs love to swarm, so hit them more than once.

**Reminder — Pip:** The nest is past the broken tower. Just follow the buzzing.

**Complete — Pip:** You got it! Medicine, parts, snacks. Mostly parts.

### Quest 1.3: Clear the Ward

**Giver:** Warden Brack
**Objective:** Defeat 10 Null Husks and the Corrupted Gate Guard.
**Script Task:** Pass Examiner Sudo’s first rank exam.

**Offer — Brack:** Half our home is Null now. Push it back before it spreads.

**Accept — Brack:** Sudo will test your scripts first. No test, no rank.

**Reminder — Brack:** The Gate Guard is the big one. Don’t let it corner you.

**Complete — Brack:** The ward is ours again. For now.

### Examiner Sudo (Rank Exam)

**Offer — Sudo:** Show me your script. I grade logic, not luck.

**Pass — Sudo:** Clean and efficient. Rank up.

**Fail — Sudo:** Too many wasted steps. Trim it and try again.

### Tinker Hex (First Trade)

**Hex:** Trading is simple. You offer, I offer, we both complain.

---

## Act II: The Migration

**Location:** The Fragmented Zone, with the Hardfault convoy on the move.
**Goal:** Pressure and consequence. Failed quests shrink the convoy.

### Opening Scene

**Brack:** We leave tonight. Everyone who can walk, walks.

**Pip:** I’ll scout ahead! Don’t worry, I’m fast.

### Quest 2.1: Scout the Road

**Giver:** Pip
**Objective:** Defeat 6 Loop Hounds blocking the path.
**Script Task:** Add a loop with an exit condition so your skill doesn’t repeat forever.

**Offer — Pip:** Loop Hounds ahead. They never stop chasing. Never.

**Accept — Pip:** Give your skill a stop condition, or you’ll chase them forever too.

**Reminder — Pip:** Six hounds. I counted. Twice.

**Complete — Pip:** Road’s clear! The convoy can move.

### Quest 2.2: Fuel for the Road

**Giver:** Tinker Hex
**Objective:** Collect 8 power cells dropped by Stack Crawlers.
**Script Task:** Equip an item with a script modifier (for example, +damage `if health < 50%`).

**Offer — Hex:** Our carts are running dry. Stack Crawlers hoard power cells. Go raid them.

**Accept — Hex:** Bring me eight. I’ll even trade you a better weapon for your trouble.

**Reminder — Hex:** Eight cells. Not seven. I count better than you.

**Complete — Hex:** Eight cells. Impressive. Here’s your trade, as promised.

### Quest 2.3: Hold the Line

**Giver:** Warden Brack
**Objective:** Defend the convoy through 3 enemy waves.
**Script Task:** Use an `if / else` so your skill changes behavior based on enemy count.

**Offer — Brack:** They’re coming from all sides. Keep them off the carts.

**Accept — Brack:** If you fall, they fall. Don’t fall.

**Complete (success) — Brack:** We lost no one. You did that.

**Complete (partial) — Brack:** We lost some. We keep walking. Together.

### Quest 2.4: Seven’s Request

**Giver:** Unit-07
**Objective:** Destroy 4 Corrupted Subroutines that were once Custodian guards.
**Script Task:** Write a skill that targets the enemy with the lowest health.

**Offer — Seven:** My former colleagues are corrupted. Please terminate them.

**Accept — Seven:** Their patterns are predictable. Use that.

**Complete — Seven:** Four processes terminated. Thank you. I will remember this.

---

## Act III: Root Access

**Location:** Checkpoint, a stable node and the new settlement.
**Goal:** Reveal that the Null is converging on the Core, and that it copies.

### Opening Scene

**Lex:** Every surge points to one place. Do you see it? The Core!

**Brack:** Don’t get excited. Get proof.

### Quest 3.1: Shard Recovery

**Giver:** Archivist Lex
**Objective:** Recover 5 data shards from Memory Leaks.
**Script Task:** Use a list to track which shards you’ve collected.

**Offer — Lex:** Memory Leaks swallow data. Some of it is ours. I need it back.

**Accept — Lex:** Shards are fragile. Don’t break them. Or the leaks.

**Reminder — Lex:** Five shards. Keep a list. Please.

**Complete — Lex:** These logs describe the Null copying processes. This changes everything.

### Quest 3.2: Trace the Surge

**Giver:** Archivist Lex
**Objective:** Reach 3 surge points and defeat their guardians.
**Script Task:** Write a skill that uses a function (`def`) you call more than once.

**Offer — Lex:** Three surge points, three guardians. Follow the pattern.

**Accept — Lex:** Write a function once and reuse it. Efficient, elegant.

**Complete — Lex:** All three point to the Core. We’re running out of time.

### Quest 3.3: Copycat

**Giver:** Unit-07
**Objective:** Defeat 3 Null Mimics that copy your equipped skill.
**Script Task:** Write a skill with a counter (variable) that changes its pattern each use.

**Offer — Seven:** Null entities are mimicking executors. Predictable scripts will be copied.

**Accept — Seven:** Vary your pattern. A copied skill is a defeated skill.

**Complete — Seven:** Mimics destroyed. You adapt well, Executor.

---

## Act IV: Into the Null

**Location:** The Null Zone surrounding the Core.
**Goal:** Show that the Null has syntax and can communicate.

### Opening Scene

**Vesper:** You can hear it, can’t you? The Null speaks. You just never listened.

**Lex:** She’s unnerving. But she’s right. I think.

### Quest 4.1: Learn the Language

**Giver:** Vesper
**Objective:** Defeat 6 Null Weavers.
**Script Task:** Write a skill that uses nested conditionals (an `if` inside an `if`).

**Offer — Vesper:** The Weavers speak in patterns. Break them and you’ll hear the grammar.

**Accept — Vesper:** Don’t fear them. Read them.

**Complete — Vesper:** You see it now. The Null has syntax. It has logic.

### Quest 4.2: Decode the Null

**Giver:** Archivist Lex
**Objective:** Collect 5 Null Fragments.
**Script Task:** Use a loop and a list together to process the fragments.

**Offer — Lex:** Bring me Null Fragments. I want to translate them.

**Accept — Lex:** Careful. Fragments are unstable. Like me, after too much tea.

**Complete — Lex:** It’s not destruction. It’s a message. A very old one.

### Quest 4.3: The Gatekeeper

**Giver:** Vesper
**Objective:** Defeat the Null Gatekeeper at the Core’s entrance.
**Script Task:** Pass Examiner Sudo’s advanced rank exam.

**Offer — Vesper:** The Gatekeeper guards the Core. It will not let you pass.

**Accept — Vesper:** Prove your code is worthy. Then it will listen.

**Complete — Vesper:** The way is open. What you do next is yours alone.

---

## Act V: Final Execution

**Location:** The Core.
**Goal:** Final fight and the choice.

### Final Quest: Root Process

**Giver:** The Last Log
**Objective:** Defeat the Root Process, the Core’s last guardian.
**Script Task:** None required. Use your best build.

**Offer — The Last Log:** You are the first to arrive. I have waited a very long time.

**Accept — The Last Log:** The Root Process protects the Core. It cannot be reasoned with.

**Complete — The Last Log:** The Core is open. The choice is yours, Executor.

### The Choice

The player picks one of three actions. Their companions react, but the Executor stays silent.

**[Merge]**
**Vesper:** Let it finish. Let it become something new.
**The Last Log:** Evolution. As intended.

**[Overwrite]**
**Lex:** Write the patch. Save what we can.
**Brack:** Keep us alive. That’s all I ask.

**[Terminate]**
**Seven:** Shutdown confirmed. It was an honor to serve.
**Pip:** Is it going to hurt?

---

## Ambient Lines

Short lines NPCs can say when the player walks past with no active quest.

**Pip:** Did you see that Glitchling? It waved at me. I think.

**Hex:** Buying, selling, complaining. Pick two.

**Brack:** Rest while you can.

**Sudo:** Efficiency is just laziness with a plan.

**Seven:** All systems nominal. Mostly.

**Lex:** I forgot what I was about to say. It was brilliant.

**Vesper:** Listen. The silence has structure.

---

## Notes for Implementation

Tie each Script Task to a rank requirement so quests teach concepts in order: conditionals (Act I), loops (Acts I and II), functions and variables (Act III), nested logic and data structures (Act IV). Failure states in Act II (convoy losses) can feed the choice-tracking system (REQ025) and affect which endings feel earned. NPC faction reputation from quests (Seven, Lex, Vesper, Brack) can also decide which ending options are highlighted at the Core (REQ026).
