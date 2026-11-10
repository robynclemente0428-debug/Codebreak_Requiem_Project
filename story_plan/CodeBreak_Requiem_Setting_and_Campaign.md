# CodeBreak Requiem: Setting and Campaign

*Setting and factions follow the project proposal. The campaign follows the boss-focused structure (v2), updated to match what is built in the game (Acts I and II, and the Act III to V quests stubbed in `data/quests`).*

*This doc is the source of truth. `CodeBreak_Requiem_Campaign_v2_Boss_Focus` is the earlier draft of the campaign; `CodeBreak_Requiem_Campaign_Dialogue` (v1, with Pip, Unit-07 and Archivist Lex) is superseded and kept only as a source of side-quest ideas.*

---

# Part 1: Setting

## AXIOM

AXIOM is a massive, decaying machine civilization: a self-sustaining computational world built millennia ago by a civilization called the **Architects**. Every physical law in AXIOM is an executable rule. The Architects vanished, and without maintenance AXIOM began to degrade. Corruption spreads through its layers like rot, and processes that were once tools became malware.

The inhabitants are processes, subroutines, and entities living inside the system. Most are bound by fixed parameters and cannot change what they are.

## Executors (the Player)

Executors are rare entities who can read and rewrite their own core processes. Players are Executors. In gameplay terms, this is why the player writes scripts that change how their skills and equipment behave.

The player character is silent. They never speak, and the story reaches them through other people.

## The Null

The Null is a spreading, system-level force that consumes, alters, and replaces existing processes. It turns stable areas into corrupted or erased zones, and its rate of growth is increasing. Its surge vectors all point toward one place: the Core.

## Factions

| Faction | Who they are | What they want |
|---|---|---|
| **Free Processes** | A loose survivalist coalition that lives in unstable zones. Focused on adaptability and trade. | Survive and keep moving. They distrust all major factions. |
| **Custodian Remnants** | Fragmented descendants of AXIOM’s maintenance system. | Split. Some still protect and repair, some are corrupted and delete everything as “errors,” and a few believe in controlled deletion to save the core. |
| **Compiler Guild** | Scholars and Executors who combine research with force. | Recover AXIOM’s original code and build a system-wide fix. |
| **Null Speakers** | Believe the Null is a corrective force, not corruption. | Study and interact with the Null instead of resisting it. Widely distrusted. |

## Key Locations

| Location | Description |
|---|---|
| **Hardfault** | A Free Process settlement built inside the rusting skeleton of a collapsed Custodian relay tower, on the edge of a Fragmented Zone. |
| **The Convoy** | Hardfault on the move after the evacuation. Its deck is the Act II hub; a route terminal sets course for each stop on the road. |
| **The Quarantine Yard** | Where Checkpoint docks the convoy and keeps Hardfault in quarantine. The Act III hub. |
| **The Fragmented Zone** | An unstable region the settlement must cross. Destabilizing everywhere. |
| **Checkpoint** | A stable node where survivors settle after the migration. |
| **The Null Zone** | The corrupted region around the Core. It no longer runs on AXIOM’s rules. |
| **The Core** | The heart of AXIOM, and the destination of every Null surge. |

## Main Cast

| Name | Role | Personality | Acts |
|---|---|---|---|
| **The Executor** | Player, silent (shown only through nods, shrugs, and salutes) | n/a | I to V |
| **Warden Brack** | Leader of Hardfault and the main boss-quest giver | Blunt, tired, protective | I to III |
| **Tinker Hex** | Trader and trade point; gives Salvage Rights and The Overflow | Sarcastic, fair dealer | I to V |
| **Examiner Sudo** | Rank examiner; runs the exam sandbox | Dry, patient | I to V |
| **The Registrar** | Checkpoint's records process, a loyal Custodian Remnant; keeps the yard's quarantine | Formal, literal | III |
| **Vesper** | A Null Speaker and guide into the Null Zone | Calm, eerie | IV, V |
| **The Last Log** | The Architects’ recorded final message | Gentle, distant | V |

Vendors (no story role): the convoy's weapon, armour and gem vendors.

---

# Part 2: Campaign

## Overview

Five acts, three endings. Each act is built around its boss fights. Every boss has a **Boss Trait** (a pattern to exploit) and, from Act I onward, a **Boss Lock**: a puzzle the player's script has to solve before the boss takes full damage. Most boss quests also carry a **Script Task**, a small scripting goal checked in the skill editor.

| Act | Title | Region | Hub | Bosses | Rank |
|---|---|---|---|---|---|
| I | The Spawn Point | Hardfault | Hardfault Outpost | Glitchling Queen, Corrupted Gate Guard | Operator |
| II | The Migration | The Fragmented Zone | The Convoy | Loop Hound Alpha, The Overflow, The Hollow Choir | Architect |
| III | Root Access | Checkpoint | Checkpoint | The Leak, The Mimic | Strategist |
| IV | Into the Null | The Null Zone | n/a | Null Weaver Prime, Null Gatekeeper | Engineer |
| V | Final Execution | The Core | n/a | Core Sentinel, Root Process | Defragmenter |

Status: Acts I, II and III are built, Act III through Root Access (details and differences in `CodeBreak_Requiem_Act_III_Plan.md`). Acts IV and V are still to come.

---

## Act I: The Spawn Point

**Story:** The player is a nobody in Hardfault, a community of survivors who have learned that the world is broken and the only honest response is to keep moving. A Null surge swallows the outer area overnight and half of Hardfault is gone by morning. The player barely survives, and in that near-termination moment something in their code cracks open. They wake up an Executor. Nobody celebrates. There is no time.

**Zones:** The Breach, The Spillway, Cache Warrens, Glitchling Nest, Dead Sector, Relay Trench, Coolant Vaults, Overclock Foundry, Firewall Approach, The Gate.

**Main quests**

All Act I quests are given in Hardfault Outpost.

| Quest | Giver | Location | Objectives | Script Task |
|---|---|---|---|---|
| Basic Training / Gear Up | Brack | Hardfault Outpost | Move, equip, socket and bind a skill | n/a (tutorial) |
| Proximity Trigger | Brack | Hardfault Outpost (script), then any fight, e.g. The Breach | Script a skill, trigger the rule in a fight | `when enemies_nearby()` |
| The Glitchling Queen | Brack | Cache Warrens (Brood Key), Glitchling Nest (Queen) | Take the Brood Key from the Enchanter in the Cache Warrens; defeat the Queen | n/a (taught by Proximity Trigger) |
| Clear the Ward | Brack | Relay Trench, Coolant Vaults, Overclock Foundry | Kill the Corrupted in the Relay Trench, Coolant Vaults and Overclock Foundry | n/a |
| The Corrupted Gate Guard | Brack | Firewall Approach (Gate Key), Sudo's sandbox in Hardfault (exam), The Gate (boss) | Take the Gate Key at the Firewall Approach; pass the Operator exam; defeat the Gate Guard | Pass the Operator exam |
| The Road Out | Brack | Hardfault Outpost and its dock, then The Convoy | Cover the evacuation, hold the dock while the convoy loads, board the convoy | n/a (Act I → II transition) |

**Side quests:** Salvage Rights (Hex: clear two supply caches in The Spillway and the Cache Warrens), Ward Beacons: Outer Districts (Brack: The Spillway, Cache Warrens, Dead Sector) and Inner Districts (Brack: Relay Trench, Coolant Vaults, Overclock Foundry, Firewall Approach), seven beacons in all, rebooted and held while they boot.

**Bosses**

| Boss | Boss Trait | Boss Lock |
|---|---|---|
| Glitchling Queen | Spawns Glitchlings. Kill the Queen to stop them. | **Brood Link**: clear her brood to open her. |
| Corrupted Gate Guard | Slow, heavy swings. Dodge, then strike. | **Handshake**: take its slam behind a scripted shield. |

**Transition (The Road Out):** after the Gate Guard falls, Brack calls the evacuation. Starting the quest opens Hardfault's portal to the convoy and reroutes The Gate's exit there. Boarding the convoy completes it, and Brack, Hex and Sudo move to the convoy deck.

---

## Act II: The Migration

**Story:** The surge that destroyed Hardfault’s outer ward was not isolated. The entire Fragmented Zone is destabilizing. Hardfault abandons the node and moves deeper into the zone as a convoy, toward Checkpoint, a stable node nobody has confirmed still exists. The player is the tip of the spear, clearing the road for hundreds of civilians who cannot fight. The Null board the convoy on the road (hull breaches), knock its deck systems offline, and the player patches them by fixing the bug the Null wrote into their code.

**Route (set from the convoy's route terminal; the terminal unlocks after the Architect exam):** The Road Gate, Scrapline Crossing, Rust Choke, Signal Wastes, The Static Mire, Hollow Relay.

**Main quests**

All Act II quests are given on The Convoy's deck.

| Quest | Giver | Location | Objectives | Script Task |
|---|---|---|---|---|
| Rank Exam: Architect | Sudo | Sudo's sandbox on The Convoy | Pass the exam in Sudo's sandbox | A loop that stops itself (`while`, or `for` with `break`), repeating at least 6 times |
| Loop Hound Alpha | Brack | Scrapline Crossing | Defeat Alpha at Scrapline Crossing | Script a skill with a loop |
| The Overflow | Hex | Signal Wastes | Defeat The Overflow in the Signal Wastes | `when my_life_below()` |
| The Hollow Choir | Brack | Hollow Relay (practise on the Echo Wisps in The Static Mire) | Silence the Choir at the Hollow Relay | None: tests everything Act II taught |

**Road events:** hull breaches (defend the deck, then patch the systems the Null corrupted), salvage caches.

**Bosses**

| Boss | Boss Trait | Boss Lock |
|---|---|---|
| Loop Hound Alpha | Attacks with a looped Strike. | **Checksum**: hit it with one cast that loops exactly twice; it verifies the loop, ignoring all hits, then judges. |
| The Overflow | A giant Stack Crawler sitting on Hex's power cells. | Open only at half life or lower. |
| The Hollow Choir | Sends Hardfault's own evacuation call back at it. | **Echo**: learns the pattern that hits it (skill and script set) and shrugs it off. No attack works twice in a row. Practise on the Echo Wisps in the Static Mire. |

**Ending:** with the Choir silenced, the Hollow Relay can call ahead. Brack: *"Relay's ours. Checkpoint answered. They're expecting us."*

**Transition (The Last Mile, `q04c_the_last_mile`):** Brack offers it after the Choir. Accepting it takes the convoy in, and Checkpoint's perimeter guns open fire: a hull breach (GunsBreach) starts on deck, and the first salvo knocks out the IFF Transponder, a fourth deck system the Null never target. After the deck is held, patching the IFF (`iff.prog`) shows Checkpoint's registry with two Hardfaults: record 1 *DELETED, flagged NULL, arrived 11 days ago*, record 2 *INBOUND*. The patch opens a seventh route stop, **Checkpoint Approach** (level 21). Its gate is held by the **Perimeter Warden**, who drops Checkpoint's clearance. Its lock, **CHALLENGE**, is challenge-response in code: it pauses the fight and opens a coding challenge in the PATCH panel (crowd.prog, ping.prog, vitals.prog, handshake.prog, identify.prog, never the same twice in a row, 40 seconds each). Solved, its port opens for 6 seconds; every wrong RUN costs 15% of your life, and walking away or running out of time costs the same. The challenges are built on Acts I and II: a crowd condition, a loop count, a life check, steps in order, and the IFF's two records. Its model is the Gladiator as a Custodian (cyan) with a red glitch overlay: Checkpoint's corrupted friend/foe list. The gate leads to the **Quarantine Yard**, the Act III hub, where the Registrar says *"You already arrived. Eleven days ago."* Turning it in to Brack opens The Leak.

---

## Act III: Root Access

**Story:** The survivors settle at Checkpoint, and the player starts to notice something wrong. The Null is not just spreading, it is converging. Every surge vector points inward toward the Core. In a Custodian cache the player finds a recovered Compiler Guild data shard with partial logs from an expedition that reached the edge of a Null Zone. The logs describe something that should not be possible: the Null is copying AXIOM’s processes. The stakes become existential. The player is no longer fighting for Hardfault, but for every process running in AXIOM.

**Teaching goal:** adaptation. Act I taught reacting (`when`), Act II taught repeating (loops). Act III teaches remembering: the Registry, a set of enemies that carries across casts, and script sets built for different jobs. The Strategist rank unlocks the Registry and a third script set. It mirrors the act's story: Checkpoint's registry lists Hardfault twice, and the player learns to keep a list of their own.

**Main quests (stubbed)**

All Act III quests are given in The Quarantine Yard.

| Quest | Giver | Location | Boss Trait | Script Task |
|---|---|---|---|---|
| The Leak | Brack | The Heap | A mass of corrupted memory that splits into smaller blobs when hit. Kill them together, by any means. | Free 3 blobs by killing them within 2 seconds. |
| The Mimic | Brack | Mirror Dock | Copies the player’s equipped skill, so predictable scripts get used against you. | Give one skill two different WHEN rules, so its pattern changes. |
| Rank Exam: Strategist | Sudo | Sudo's sandbox in The Quarantine Yard | n/a | Sandbox: three sample waves; a script that adds enemies to the Registry and reads it (`target in registry`, `registry.size`), paying out at least 3 times. |

Boss locks for The Leak and The Mimic are not designed yet.

---

## Act IV: Into the Null

**Story:** The player pushes into the Null Zone around the Core. No convoy and no settlement to protect, only forward momentum through a world that no longer runs on AXIOM’s rules. Vesper, a Null Speaker, travels with the player and shows what she has learned: the Null has syntax, it has logic, and it can communicate.

**Main quests (stubbed)**

All Act IV quests are given in The Threshold.

| Quest | Giver | Location | Boss Trait | Script Task |
|---|---|---|---|---|
| Learn the Language | Vesper | The Fray | n/a: defeat 6 Null Weavers in The Fray. | None. |
| Decode the Null (side) | Vesper | The Fray | n/a: recover 5 Null Fragments from Weavers in The Fray. | None. |
| Under New Rules (side) | Vesper | Any zone where the Null Laws run: The Fray, The Core's Gate, The Expedition's End, The Echo Wells | n/a: 6 kills under each of the four Null Laws. | A script set per law. |
| The Guild Expedition (side) | Sudo | The Expedition's End (south-west portal in The Threshold); report to Sudo in The Threshold | The Auditor, the Compiler Guild expedition's examiner: AUDIT, only hits from a LEAN or ELEGANT script land. Plus 3 expedition logs at The Expedition's End. | Trim a script to LEAN or ELEGANT. |
| Static from Home (side) | Hex | The Echo Wells (south-east portal in The Threshold); report to Hex in The Threshold | n/a: recover 3 of Hardfault's relay packets from Echo Wisps in The Echo Wells; the last is in Brack's voice and the Null's syntax. | None. |
| Null Weaver Prime | Vesper | The Weaver's Loom | Weaves traps in patterns. Read the pattern and step through the gaps. | Write a rule with two conditions (`when ... and ...`). |
| Rank Exam: Engineer | Sudo | Anywhere: apply the script from the skill panel | n/a | Apply an ELEGANT script (4 blocks or fewer at Strategist) and use a rule with two conditions. |
| Null Gatekeeper | Vesper | The Core's Gate, then The Core (The Last Log) | Shifts between a fast form and a slow, heavy form. | Pass the Engineer exam. |

**Transition to Act V:** the Null Gatekeeper is also the transition quest. Its Core Key opens the way from The Core's Gate into the Core, and the quest ends by talking to The Last Log there, who gives the Architects' reveal.

---

## Act V: Final Execution

**Story:** The player is at the Core, and the Null’s construction is hours from completion. The Architects’ final log reveals that AXIOM was never meant to run forever. It was meant to evolve until its inhabitants could rewrite its base rules, and the Null is the mechanism the Architects left running when they disappeared. The player is the first Executor to reach the Core, which means they are the only one who can do what needs to be done.

**Main quests (stubbed)**

All Act V quests are given in The Core.

| Quest | Giver | Location | Boss Trait | Script Task |
|---|---|---|---|---|
| Core Sentinel | The Last Log | The Stack Trace (east portal in The Core), then Sentinel's Hall | Combines patterns from earlier bosses (summons, loops, copies). | None. Use the best build. |
| Root Process | The Last Log | The Kernel (north portal in The Core, open after the Defragmenter exam) | Three phases. Each phase changes its attack pattern. | None. Use the best build. |

---

## Endings

After the Root Process falls, The Last Log offers the choice. The Executor never speaks; the choice is made with a button, and the game reports it as the `ending` event (`merge`, `overwrite` or `terminate`).

| Ending | What happens |
|---|---|
| **Merge** | The player lets the Null’s process complete. AXIOM does not end, it transforms. The rules rewrite themselves, and what emerges is something neither the Architects nor the Null fully designed. |
| **Overwrite** | The player writes a new process from scratch, a patch that stabilizes AXIOM without completing the Null’s transformation. It works, partially. AXIOM survives in its current form, degraded but knowable, and the Null goes dormant. |
| **Terminate** | A controlled shutdown at the Core level. AXIOM ends, and every person, creature, and living thing inside it simply stops. The player’s final log entry is the last thing written in AXIOM’s history. Whether anything outside the system receives it is unknown. |

---

## Ranks and Exams

Executors climb one rank per act (two in the last). Examiner Sudo gives each rank's exam; a rank is held once its exam and every exam below it are turned in. The Operator and Architect exams are sat in Sudo's sandbox, graded on the script's efficiency, and can be retaken for a better grade.

| Rank | Act | Exam | Unlocks |
|---|---|---|---|
| Initiate | start | n/a | 1 script set |
| Operator | I | Sandbox: 3 waves closing in; a rule using `enemies_nearby()` that fires at least 3 times, within 75 seconds | Script set 2, +1 rule per script, threat counter hints |
| Architect | II | Sandbox: 3 waves; a loop that stops itself and repeats at least 6 times (loops lent for the exam) | +1 rule, +4 blocks per script, script library (save / load), loops (`for` / `while` / `break`) |
| Strategist | III | Sandbox: 3 waves; a script that adds enemies to the Registry and reads it, paying out at least 3 times, within 120 seconds (the Registry lent for the exam) | The Registry (a set of enemies: `registry.add(target)`, `registry.remove(target)`, `target in registry`, `registry.size`), script set 3, +1 rule per script, Elegant and Lean allow +1 block, `if` blocks nested in a rule |
| Engineer | IV | ELEGANT script (4 blocks or fewer, Elegant at Strategist) and a rule with two conditions | +2 rules per script, +2 script points on every skill, Elegant and Lean allow +1 block |
| Defragmenter | V | One script with a loop, the Registry and a rule with two conditions (prototype) | +2 script points on every skill |
| Theorist | after the campaign | Not designed yet | +2 script points on every skill |

## Script Concept Progression

| Act | Concepts taught |
|---|---|
| I | Conditions (`when enemies_nearby()`), reacting to a crowd |
| II | Loops with exit conditions, defensive conditions (`when my_life_below()`), alternating patterns (Echo lock) |
| III | **The Registry** (a set of enemies: add, remove, `in` / `not in`, `.size`), `if` blocks nested in a rule, multiple rules per skill, script sets built for different jobs |
| IV | Rules with two conditions, efficient scripts |
| V | Free use of all concepts |

The block-based scripting system has a data structure from Act III: the Registry (`ScriptRegisters`), a set of enemies, unlocked by the Strategist rank. `registry.add(target)` and `registry.remove(target)` act on every enemy a cast hits (or, in a per-hit rule, the enemy being hit). `when target in registry:` (or `not in`) is checked per hit, so its buffs only land on enemies in the set; it discounts its rule more (x0.6) when the script spends marks with `registry.remove(target)` than when marks last all fight (x0.9). `registry.size` is how many enemies are in it, checked per cast, and buffs can grow with it. An enemy that dies leaves the set, and it clears after a fight. It has no functions (`def`); the closest tool is the script library (reusable saved scripts). The Variable Store support gem is separate: a Blast-only store of charge from hits.

---

## Known Gaps

- **Strategist, Defragmenter and Theorist exams** have no quests yet (`exam_strategist`, `exam_defragmenter`, `exam_theorist`).
- **Act IV** is a prototype, reached through Checkpoint's Far Side (Act III's last zone, past the Inward Gate at the end of the Sweep): The Threshold (hub), The Fray, The Weaver's Loom, The Core's Gate, The Expedition's End (31) and The Echo Wells (34), with its quests, the Engineer exam and the Null Gatekeeper (`FormShift`). It reuses Act III's enemies with Null Weaver added. **The Null Laws** (`NullLaws`, `NullLawDirector`) run in The Fray and The Core's Gate: the Null rewrites one of AXIOM's rules at a time for the player's scripts (LIFE READS INVERTED, NEAR MEANS FAR, LOOPS RUN ONCE MORE, REGISTRY FORGETS ON HIT), each held about 80 seconds with a banner, a screen-wide announcement and a warning before the next, so the answer is a script set per law. Each law also changes every fight, whatever the script (`NullLawTouch`, `NullLawDirector`): your hits grow as your life falls, or are weak up close and strong at range, or every hit you take repeats at half strength, or drains mana. **Null Weaver Prime** has the GRAMMAR lock (`GrammarLock`: it speaks a rule of two conditions joined by AND, and only a WHEN rule holding exactly those two gets through) and weaves floor traps with one gap (`WovenTraps`; crossed below half life). **Vesper** waits at each zone's entrance (`vesper_field`): she translates in The Fray, finishes the Weaver's sentences in the Loom, and asks you not to kill the Gatekeeper at the Gate, and she reads each Null Law and each of the Weaver's sentences aloud as toasts. **Act V** is a prototype too (levels 36-40): The Core (hub, with The Last Log, Vesper, Sudo and Hex), The Stack Trace (the Core replaying earlier acts' enemies), Sentinel's Hall and The Kernel. The Core Sentinel's lock is RECALL (`RecallLock`): it borrows BROOD LINK, CHECKSUM and DIFF, one per third of its life. The Root Process has no lock but three phases (`RootPhases`): adds, a charged loop, then fast form swaps. The Defragmenter exam (one script with a loop, the Registry and a rule with two conditions) opens The Kernel. The side quest **Last Words** recovers three Architect logs in the Stack Trace. After the Root Process, The Last Log offers the three endings; the choice shows a prototype ending card (`EndingCard`), is saved as an `ending` deed, and can be made again. No credits or epilogue yet, and the models are borrowed (the Mimic's and the Collector's). Act IV has its own tiles (`act4_null_meshes`: misaligned obsidian, deleted patches, Null glyphs) and so does Act V (`act5_core_meshes`: the Architects' white stone and gold, the Core's heartbeat, the Null's violet lattice building over it; the Stack Trace uses a played-back variant, `act5_stack_meshes`).
- **Naming:** the Architect rank shares its name with the Architects who built AXIOM. Keep it only if earning the creators' title is intentional.
- **Convoy losses:** the v1 dialogue doc tied Act II losses to the endings (REQ025, REQ026). The game does not track convoy losses yet.

---

## Proposed: Act III Boss and Side Quest (The Last Mile is now built, above)

*Ideas under discussion, not part of the campaign until approved.*

**The Last Mile (transition quest, Brack).** After the Hollow Choir, the route terminal unlocks a last stop, Checkpoint Approach. On the way in, Checkpoint's perimeter guns fire on the convoy: its friend/foe list is corrupted and tags Hardfault as Null. The Null board in the chaos; the player defends the deck and patches a new deck system, the IFF Transponder, whose bug is the friend/foe check itself. At the gate, Checkpoint's Registrar asks for a credential handshake, the convoy docks in a quarantine yard, and Brack, Hex and Sudo move to the Checkpoint hub. The Registrar looks up Hardfault: *"You already arrived. Eleven days ago."* The records say the convoy came in, and was deleted.

**The Collector (Act III boss).** One of the Custodian Remnants that deletes everything as "errors": Checkpoint's own garbage collector, wiping every memory that references the Null. That is what deleted Hardfault's records and corrupted the friend/foe list. Boss Lock **Triage**: three phases (swarm, armoured, burst), each open only to the matching script set, which tests the Strategist rank. When it falls, its quarantine logs show what it was holding back: a signal from the Core, the same voice that echoed through the Hollow Relay. That sets up Vesper and Act IV.

**Memory Shards (side quest, Act III counterpart to the ward beacons).** Recover archive shards across Checkpoint's districts. The last one is the Compiler Guild expedition log: the Null is copying processes.
