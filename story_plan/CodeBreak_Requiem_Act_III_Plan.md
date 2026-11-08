# CodeBreak Requiem: Act III Plan (Root Access)

*Built: the Quarantine Yard hub, all six districts, the REFCOUNT, DIFF and GENERATIONS locks, the Strategist exam, every main quest through Root Access, and both side quests. Differences from the plan below: **Memory Shards** has four shards, one per district, because a district holds one beacon. **The Mimic** copies the skill that hits it but not the script. **Blobs** feed The Leak while alive instead of crawling back to it. **The Collector** sweeps its adds once five are alive rather than as it reaches them. **Sweeps** only go for crates, not civilians, since the yard has none yet. The convoy's route terminal stays usable when DOCKED: Hardfault stays moored, and the terminal drops the player at Act II's stops, with no breaches or Sweeps owed for those runs. The Inward Gate opens once Root Access is turned in, onto Checkpoint's Far Side, a level 30 zone that comes out at Act IV's prototype hub, so Act III ends at the end of a zone like Act II does. Builds on `CodeBreak_Requiem_Setting_and_Campaign.md`, the source of truth.*

---

## 1. The Act in Four Lines

Checkpoint answered the Hollow Relay, but the answer was a record: Hardfault already arrived, eleven days ago, and was deleted as Null. The Null heard Hardfault's evacuation call through the Choir and built a **copy** of the convoy, and the copy got there first. Checkpoint's garbage collector deleted the copy and now treats everything that remembers it, including the real Hardfault, as garbage. The player cleans up what the copy left behind, beats the Collector, and earns **root access** to the last Custodian node before the Null Zone.

## 2. What Act III Picks Up From Acts I and II

Each thread below is already in the game. Act III either pays it off or pushes it further.

| Thread from Acts I and II | Where it is now | What Act III does with it |
|---|---|---|
| The Hollow Choir sent Hardfault's evacuation call back "in our own voices" | Act II finale, `q04b_hollow_choir` | The Choir was the Null **recording** Hardfault. Act III shows what it built from the recording: a copied convoy. |
| Brack: *"Checkpoint answered. They're expecting us."* | Act II's last line | Turns sour. Checkpoint *was* expecting them, on its deletion list. |
| Deck systems, hull breaches and PATCH puzzles | Act II convoy | One last breach on the approach, and a fourth deck system (IFF Transponder) whose patch output gives the twist away. |
| The Handshake lock (shield up, take the slam) | Act I, Gate Guard | Checkpoint's gate asks for the same handshake. A small callback, no boss. |
| Echo lock: never the same attack twice (switch skills or sets) | Act II, Choir and Echo Wisps | The Mimic goes one step further. Switching from outside no longer fools it; the script itself has to branch. |
| Script set 2 (Operator) and set swapping | Act I unlock, Act II Choir | Strategist unlocks set 3. The Collector needs all three, each built for one job. |
| Ward beacons (hold a point while it boots) | Act I side quest | Memory Shards reuses the hold mechanic: restore a shard while the Leak's blobs come for it. |
| Hex's power cells (The Overflow) | Act II, Hex | Hex finds her own stock in the copy's cargo. *"Somebody copied my inventory. I want royalties."* |
| Brack's arc: "We meet it moving" | Acts I and II | Brack stops moving. He faces his own copy and stays at Checkpoint with the survivors (the cast table already ends him at Act III). |
| Hardfault was built in a collapsed Custodian relay tower | Act I setting | Act III brings in the Custodian Remnants as a faction split in two: the Registrar (repairs) and the Collector (deletes). |

## 3. Story Beats

1. **The Last Mile** (transition). The convoy sets course for Checkpoint. Its perimeter guns open fire; the Null board in the chaos. Patching the IFF Transponder shows two Hardfault records: one *ARRIVED, DELETED (NULL)*, one *INBOUND*.
2. **The gate.** The Registrar, a loyal Custodian process, asks for a credential handshake and docks the convoy in a quarantine yard. *"You already arrived. Eleven days ago."*
3. **The Leak.** The copy was deleted but its memory was never freed. It leaked into Checkpoint's Heap as a splitting mass that is eating the archive. Killing it frees what it swallowed, including a **Compiler Guild data shard**: an expedition reached the edge of the Null Zone and logged that *the Null is copying processes*.
4. **The Mimic.** One process escaped the deletion: the copy's Brack. It wears his voice and copies whatever skill it meets. When it falls it says, in Brack's voice, the line the real Brack said at the Road Out. Brack hears it.
5. **The Strategist exam.** Sudo: the Collector does not forgive a one-trick script.
6. **The Collector.** Checkpoint's garbage collector. It deleted the copy (correctly), then widened its sweep to everything that references the Null: Hardfault's records, the Guild logs, a quarantined Null Speaker called Vesper, and next the survivors in the yard. Its quarantine was also holding back a signal from the Core: the same voice that sang in the Hollow Relay.
7. **Root Access** (transition to Act IV). The Registrar restores Hardfault's records, so the survivors finally settle, and grants the Executor root credentials. Checkpoint is the last Custodian node before the Null Zone, and root opens its far gate. Vesper walks out of quarantine. Brack stays.

**The lore this sets up for Act V:** the copy convoy had no Executor in it. The Null can copy any process, but not one that rewrites itself. That is why the copy could not fight off the Collector, and why the player is the only one who can reach the Core.

## 4. Teaching Goal: Adaptation

Act I taught reacting (`when`). Act II taught repeating (loops) and switching patterns from outside (Echo). Act III teaches **choosing a strategy**: scripts that branch on their own, and script sets planned for different jobs.

| Step | Where | Concept |
|---|---|---|
| 1 | The Leak | Killing several enemies at once, by any means (AREA, Cleave, chains, a fast script). Optional: a second set with big hits for the core. |
| 2 | The Mimic | One skill with two WHEN rules, so the script itself changes pattern (`program_branches`). |
| 3 | Strategist exam | **Counters** (`x`, `y`): a rule counts something, another acts on the count and resets it. |
| 4 | The Collector | Three phases, three sets, each built for one phase. Swapping at the right moment, not every hit. |

The difference from the Echo lock matters. Echo asks "switch anything"; Act III asks "switch to the *right* thing". The Mimic punishes outside switching and rewards branching inside one script. The Collector punishes the wrong set rather than a repeated one.

Counters (`x`, `y`) are the game's variables. No functions are needed.

## 5. Regions and Hub

**Hub: The Quarantine Yard.** The convoy stays docked in the yard and is still walkable, so the move from Act II is physical: the same deck, now parked, with Checkpoint's walls around it. Brack, Hex, Sudo and the vendors stay on or beside the deck. The Registrar stands at the yard gate. Hull breaches stop; **Sweeps** replace them (see Road Events).

**Look:** Act III has its own tile sets. The yard (`act3_yard_meshes`, built and in use) is Custodian intake: glazed ceramic pavers, slate lanes, printed bay codes, red quarantine tape, ice-blue status slots and a slow scan line. The districts (`act3_district_meshes` with the `act3_districts` theme, built, used by every district, with a theme for each kind: `act3_heap`, `act3_dangling`, `act3_marks`) are the inside of the node: dark glass, circuit traces, flickering memory cells, server-rack walls, and racks the Collector has marked in red. The theme's enemy and loot lists are Act II's stand-ins until Act III's own exist. `tools/act3/tile_preview` shows both.

**Travel:** the **District Gate** in the yard (a route terminal) sends you to districts. Districts open by **quarantine level**, which drops as you earn clearance: the Act III version of Act I's keys and Act II's route stops.

| Zone | Opens at | What is there |
|---|---|---|
| Checkpoint Approach | The Last Mile (convoy route stop) | The road to the gate; the Perimeter Warden (CHALLENGE lock) |
| The Registry | After the Strategist exam (level 3) | Custodian archive, shards, the Registrar's records |
| The Heap | After the Strategist exam (level 3) | Memory allocation sprawl, Leak blobs. **The Leak** |
| Mirror Dock | After The Leak (level 2) | Where the copy convoy docked and was deleted. Copied crates, frozen copies of Hardfault's people. **The Mimic** |
| Dangling Quarter | After The Leak (level 2) | Pointers to things that no longer exist. Side content, Echo Wisp variants |
| Mark Yards | After the Mimic (level 1) | The Collector's marking floors. Red-tagged processes waiting for deletion |
| The Sweep | After the Mimic and the exam (level 0) | The Collector's furnace. **The Collector** |
| Inward Gate | Root Access | In the yard; opens onto Checkpoint's Far Side (level 30), a zone that comes out at Act IV's hub |

## 6. Main Quests

The structure mirrors Act II: one boss, then two quests in parallel, then a finale.

```
q04b Hollow Choir ─► q04c The Last Mile ─► exam_strategist ─► q05 The Leak ─► q06 The Mimic ─► q06b The Collector ─► q06c Root Access ─► q07 (Act IV)
```

| ID | Quest | Giver | Objectives | Script Task | Prerequisites | Act |
|---|---|---|---|---|---|---|
| `q04c_the_last_mile` | THE LAST MILE | Brack | Set course for Checkpoint Approach; defend the deck; patch the IFF Transponder; answer the Perimeter Warden's challenges; dock in the Quarantine Yard | n/a (transition) | `q04b_hollow_choir` | II |
| `q05_the_leak` | THE LEAK | Brack | Pass the Strategist exam; free 3 blobs by killing them together; defeat The Leak in the Heap | None: the task is in the fight | `q04c_the_last_mile` (was `q04b`) | III |
| `q06_the_mimic` | THE MIMIC | Brack | Give one skill two WHEN rules; defeat The Mimic at Mirror Dock | Two WHEN rules (existing) | `q05_the_leak` | III |
| `exam_strategist` | RANK EXAM: STRATEGIST | Sudo | Pass the exam in Sudo's sandbox | Keep a count with counters (below) | `q04c_the_last_mile` | III |
| `q06b_the_collector` | THE COLLECTOR | Brack | Pass the Strategist exam; defeat The Collector in the Sweep | Pass the Strategist exam | `q06_the_mimic`, `exam_strategist` | III |
| `q06c_root_access` | ROOT ACCESS | Registrar | Take the root key to the Registrar; open the Inward Gate | n/a (transition) | `q06b_the_collector` | III |

`q07_null_weaver_prime` (Vesper) then takes `q06c_root_access` as its prerequisite.

### The Last Mile (Act II → III transition)

Built like The Road Out: a transition quest that still belongs to the act it leaves.

1. **Turn in the Choir.** Brack's current lines stay (*"Relay's ours. Checkpoint answered. They're expecting us."*). The Last Mile is offered right after.
2. **Set course.** The route terminal gets a seventh stop, **Checkpoint Approach**. It needs the Comms Relay online, as every stop does, so a player with comms down patches it first: Act II's systems still matter on the last day.
3. **Guns.** Halfway in, the perimeter guns fire on the convoy (tracers out of the void, screen shake) and a breach starts. A fourth deck system, the **IFF Transponder** (glyph `I`), joins the three the Null go for, and it goes down whatever the player does.
4. **Patch the IFF.** The fourth PATCH puzzle: a comparison against the wrong record. Its OUTPUT gives the twist away before any NPC says it:
   `RECORD 1: HARDFAULT  ARRIVED  DELETED (NULL)`
   `RECORD 2: HARDFAULT  INBOUND`
   Fixing it makes the transponder answer as record 2, and the guns stop.
5. **The gate.** On foot through Checkpoint Approach to the gate, held by the **Perimeter Warden**. Lock **CHALLENGE** (challenge-response): it pauses the fight and hands you a coding challenge in the PATCH panel, never the same twice in a row. Solved, the port opens; a wrong answer hurts. Checkpoint asks who you are, and you answer in code. It drops Checkpoint Clearance, which opens the gate.
6. **Dock.** Enter the Quarantine Yard. Brack, Hex and Sudo move there. The Registrar's first line plays.

### The Leak

- **Story:** the copy's memory was never freed. It pooled in the Heap and is eating Checkpoint's archive.
- **Boss Trait:** splits into smaller blobs when hit.
- **Boss Lock: REFCOUNT.** Blobs crawl back into the Leak and heal it. A blob killed on its own leaks again (it respawns as a new blob a few seconds later). Three or more killed within 2 seconds, by any skill, are **freed** and stay dead. The Leak's core only takes full damage while its refcount (blobs alive, shown over it) is 0. The next split starts the count again, like the Glitchling Queen's brood but faster: Act I's lock grown up.
- **Tip:** Slam or Blast catch them all at once, Cleave or a chain can sweep them, and a fast script can pick them off. Big hits in another set for the core, if you want it faster.
- **Drops:** the Compiler Guild data shard (quest item, shown in the quest items tab). It plays the Act's key revelation through the Registrar on turn-in.
- **Why it fits:** "memory leak" taken literally. AREA is the easy answer here, not the only one.

### The Mimic

- **Story:** the one process that escaped the deletion, a copy of Brack. It has been living in Mirror Dock among the frozen copies, speaking in his voice.
- **Boss Trait:** copies the skill that hits it and casts it back at you, script and all. A `when my_life_below()` rule you wrote fires for *it* too.
- **Boss Lock: DIFF.** It compares each cast with the last one it copied. If the same rule fired, the diff is empty and the hit does nothing (*"NO DIFF"*). If a different rule fired, the hit lands (*"DIFF: RULE 2"*). Swapping skills or script sets does not work: it copies your whole loadout as you swap (*"LOADOUT COPIED"*). Only a script that branches inside itself gets through.
- **Script Task:** give one skill two different WHEN rules (`program_branches`, existing). Good pairs: `enemies_nearby` and `every_nth_cast`, or `target_life_below` and `hit_recently`.
- **Practice:** the Dangling Quarter has small copy processes ("Mirror Husks") with the same lock.
- **On defeat:** it says, in Brack's voice, the line the real Brack said at the Road Out: *"Whatever's out there, we meet it moving."* Then it stops.
- **Why it fits:** Echo (Act II) was the Null learning. The Mimic is the Null copying. The player answers by doing what a copy can't: changing its own code mid-fight.

### Rank Exam: Strategist

Sat in Sudo's sandbox like the Operator and Architect exams, graded on efficiency, and retakeable. For this one the sandbox is a sealed quarantine bay built from the yard's tiles, replaying Checkpoint's quarantine logs (the Registrar lets Sudo use them). Each wave drains its own sample tank at the rim, and the rim takes that wave's colour.

- **Spec:** three waves of holographic samples of what's past the District Gate, with the same numbers as plain test processes (`sample_leak`, `sample_copy`, `sample_marker`; no locks):
  1. **Leaked Memory (swarm):** many weak blobs closing in.
  2. **Copied Processes (armoured):** a few armoured copies.
  3. **Marker Drones (burst):** fast drones that hit hard and often, in melee rather than shooting as the real ones do.
- **Pass:** clear all three within the time limit with a script that keeps a count: a WHEN rule about the fight raises `x` or `y`, and a rule reading it fires at least 3 times. Counters are lent for the exam, the way loops are lent for the Architect exam.
- **Grade:** the same as the other exams: efficiency tier, time and damage taken. Counter writes aren't blocks, so a script using them can still reach ELEGANT.
- **Counters (`ScriptRegisters`):** two registers per script, kept between casts and cleared when the script is applied. Both blocks are modular, like the patch puzzles: reads are `when [x] [>=] [3]:` with any of `< > <= >= == !=`, writes are `[x] [+=] [1]` with `=`, `+=` or `-=`, and every part is a token you click. A write can name at most 5, while the counter itself climbs to 99 and reads can compare up to 99. In the snippets list the counters and operators are separate pieces: an operator adds a whole line, or changes the operator of the line it's dropped on, and a counter changes a counter line or, dropped on a knob, makes that buff grow with it. Writes are free. Reads discount a rule to x0.75. A cast reads first and writes after, so rule order doesn't change the meaning, and a toggle (`x < 1`, `x >= 1`) answers The Mimic's DIFF. A read needs a line raising the register, and can't be always or never true (`x >= 0`), or the script doesn't compile. A buff can grow with a counter (`damage += x * 2%`): it grows until it reaches the knob's limit, less the script's flat lines on that knob, and a knob can have one growing line. Its value sets how fast it gets there. It costs x0.3 (slowest) to x0.6 (fastest) of that room's flat price if a WHEN about the fight raises the counter, and full price otherwise, so `always: x = 5` gets no discount. A counter a buff grows with only rises once per cast. Only buffs on values that can change gradually can grow (damage, radius, range, arc, spread, speed, leech, barrier, guard), not whole numbers like pierce. Counters live on the script, so rebuilding a skill keeps them and each set has its own, and they clear 10 seconds out of combat or on a change of area. A read always gets the discount, even if nothing lowers the register, because counters clear after every fight: a one-way switch has to be earned again each time. The Variable Store support stays as it was: a Blast-only store of charge from hits.
- **Unlocks:** script set 3 (already in `Ranks.PERKS`).

### The Collector (Act III finale)

- **Story:** process C-0, Checkpoint's garbage collector, one of the Custodian Remnants that deletes everything it calls an error. It deleted the copy convoy, which was the right call. Then it widened its sweep to everything that remembers the copy: Hardfault's records, the Guild logs, Vesper, and next the yard.
- **Boss Trait:** each phase marks processes (adds and itself) for deletion. Marked processes it reaches are swept: they heal it.
- **Boss Lock: GENERATIONS.** A garbage collector cleans by generation, and so does this fight. Three phases, each open only to one script set, shown on the lock banner:
  | Phase | Generation | What it throws at you | Open to |
  |---|---|---|---|
  | 1 | Gen 0 (young garbage) | A swarm of fresh adds | Set A |
  | 2 | Gen 1 (survivors) | Armoured adds, the Collector shielded | Set B |
  | 3 | Gen 2 (old garbage) | The Collector itself, burst attacks | Set C |
  The sets are the player's own, so the lock tests whether they built each set for its job: AREA in A, big hits in B, survival in C. The wrong set doesn't just do nothing; that generation is **promoted** and heals a little.
- **Script Task:** pass the Strategist exam.
- **On defeat:** it drops the **root key**. Its quarantine logs open: the deleted Hardfault records, the rest of the Guild logs, Vesper's cell, and a signal from the Core it had been holding back, the voice from the Hollow Relay.
- **Why it fits:** Act I's Gate Guard was a rogue guardian at Hardfault's gate. The Collector is a rogue guardian at Checkpoint's heart, and this time it is not corrupted. It is working as designed.

### Root Access (Act III → IV transition)

1. Take the root key to the Registrar. Hardfault's records are restored, the quarantine lifts, and the yard becomes Checkpoint's newest district. The survivors settle, which closes Act II's whole journey.
2. The Registrar grants the Executor root credentials: the act's title, paid off.
3. Vesper comes out of quarantine. She has been listening to the Core's signal through the cell wall for eleven days.
4. Brack's farewell (see Dialogue). Hex and Sudo say they are coming along. The vendors stay.
5. Open the Inward Gate. Act IV starts on the other side with Vesper's existing opener: *"You can hear it, can't you?"*

## 7. Side Quests and Road Events

| Quest | Giver | Objectives | Reward |
|---|---|---|---|
| **Memory Shards** (`memory_shards`) | Registrar | Restore six archive shards across the Registry, the Heap, Mirror Dock and the Dangling Quarter. Each is a hold point, like the ward beacons: start the restore, hold the ring while Leak blobs come for it. | Cache pick, plus the full Compiler Guild expedition log (lore: who reached the Null Zone's edge, and where the route in starts) |
| **Copied Stock** (`copied_stock`) | Hex | Recover four of Hex's copied crates from Mirror Dock. They are hers, exactly: same scratches, same price tags. | Hex stocks 10 levels above the act, plus two "COPY OF" items at half price |

**Road event, Act III version: Sweeps.** Replaces hull breaches while docked. An alarm sounds and the Collector's marker drones come over the yard wall and head for the convoy's crates and civilians, red-tagging them (same saboteur logic as `HullBreach`, aimed at cargo instead of systems). Kill the markers before the sweep timer ends. A tagged crate is deleted: the breach's cargo bonus, in reverse. Sweeps stop for good once the Collector falls, so the yard visibly becomes safe. Built as `YardSweep`: one sweep is owed per run through a district.

## 8. Cast Changes

| Name | Change |
|---|---|
| **Warden Brack** | Gives every Act III boss quest. Faces his copy. Stays at Checkpoint at the end; his last scene is the Root Access farewell. |
| **Tinker Hex** | Copied Stock side quest. Joins the trip into the Null Zone at the end. |
| **Examiner Sudo** | Strategist exam. Joins the trip into the Null Zone. |
| **The Registrar** (new, Custodian Remnant) | Formal and literal, a loyal maintenance process (the personality of v1's Unit-07). Act III's quest point at the yard gate. Shows the "repairs" half of the Custodian split, against the Collector's "deletes" half. Act III only, or a short cameo in Act V. |
| **Vesper** | First seen at the end of Act III, in the Collector's quarantine. Takes over as main quest giver in Act IV, as planned. |

## 9. Dialogue Drafts

Same writing rules as the other acts: the Executor is silent, lines are one or two sentences, every quest has Offer, Accept, Reminder and Complete.

### The Last Mile

**Offer — Brack:** Checkpoint's two stops out. Set course and let's finish this.
**Offer — Brack:** They've got guns on the approach. They know we're coming. Should be a quiet ride.
**Accept — Brack:** Comms has to be up to plot it. Patch it first if it's down.
**Mid-quest (guns open fire) — Brack:** That's not a welcome. Get to the transponder.
**Mid-quest (IFF patched) — Brack:** Two of us on their list? That's not a typo.
**Mid-quest (gate) — Brack:** It asks in code. It'll hand you a program and wait. Fix it right and it opens up.
**Reminder — Brack:** Get us through that gate.
**Complete — Brack:** We're docked. Inside a fence, but docked.

**Registrar (first meeting):** Hardfault. You already arrived. Eleven days ago.
**Registrar:** You were deleted. Please remain in quarantine while I resolve the duplicate.

### The Leak

**Offer — Brack:** Something is eating Checkpoint's memory. It splits every time it's hit. *(existing)*
**Offer — Brack (new):** The Registrar says it's what's left of the other us. I'm not asking how that works.
**Accept — Brack:** Script whatever you like. A Slam, a cleave, a chain, something fast. It just has to catch the pieces.
**Accept — Brack (new, lock):** Pieces you kill one at a time come back. Kill three inside a couple of seconds and they stay dead. Then hit the big one.
**Reminder — Brack:** It's still splitting. Hit it wider. *(existing)*
**Complete — Brack:** It's sealed. Something fell out of it. The Registrar wants to see.
*(replaces "We can finally rest", which no longer fits mid-act)*

**Registrar (shard):** Compiler Guild expedition, partial. Final entry: *"It is not eating them. It is copying them."*

### The Mimic

**Offer — Brack:** A Null thing is copying everything we do. It copied my voice yesterday. *(existing)*
**Offer — Brack (new):** It's in Mirror Dock, where the other convoy docked. It knows my name.
**Accept — Brack:** Vary your pattern. A copied skill is a defeated skill. *(existing)*
**Accept — Brack (new, lock):** Swapping won't fool it; it copies the swap. Your script has to change its own mind. Two rules, one skill.
**Reminder — Brack:** Change your pattern. It's learning. *(existing)*
**Complete — Brack:** It's gone. I never want to hear that voice again. *(existing)*
**Complete — Brack (new):** It said my line. The one from the dock. It meant it, too.

### Rank Exam: Strategist

**Offer — Sudo:** Your scripts only know what's true right now. This whole place is what happens when memory goes wrong.
**Offer — Sudo:** The Strategist exam. The Registrar let me replay Checkpoint's quarantine logs into a sealed bay.
**Offer — Sudo:** Three samples from out there, and one new tool: a script that remembers.
**Accept — Sudo:** I'll lend you two counters, x and y. Count something with one rule, use it with another. They clear themselves when the fight ends. In the middle of one, though, a count nobody spends is just a leak.
**Pass — Sudo:** It remembered, and it let go. Rank up. Strategist.
**Idle — Sudo:** A plan is just a loop you haven't run yet.

### The Collector

**Offer — Brack:** The thing that deleted us is still running. It's marking our crates now. Our people next.
**Accept — Brack:** Sudo says it sorts what it kills. Three kinds. Bring a script for each.
**Accept — Brack (lock):** Wrong script for the phase and it gets stronger. Watch the banner.
**Reminder — Brack:** It's still sweeping. Pass Sudo's exam, then end it.
**Complete — Brack:** It's done. First time since Hardfault there's nothing hunting us.

**Collector (fight barks):** *GENERATION 0. MARKED.* / *REFERENCE TO NULL. COLLECTING.* / *YOU ARE NOT IN MY RECORDS. YOU CANNOT BE COPIED. ERROR.*

### Root Access

**Offer — Registrar:** The root key. With it I can restore your records, and open what C-0 kept shut.
**Accept — Registrar:** Bring it to me. I am not authorized to touch it. You are not a process I can authorize either.
**Complete — Registrar:** Hardfault: restored. Executor: root. The Inward Gate answers to you now.

**Vesper (leaving quarantine):** Eleven days of listening. It hasn't stopped calling. It's calling you.
**Hex:** Nobody sells anything past that gate. Which is why I'm going.
**Sudo:** Exams don't grade themselves. Unfortunately.
**Brack (farewell):** This is where I stop. Somebody has to keep them alive here.
**Brack:** I saw what a copy of me looks like. It kept moving. I'd rather stay put and be real.
**Brack:** Go. Come back if there's a back to come to.

### Registrar ambient

**Registrar:** All records nominal. One duplicate pending.
**Registrar (after Root Access):** Population: Hardfault, one. Correct.

## 10. Build Checklist

What the plan needs in the project, grouped by area. Everything listed as existing was checked in the code.

**Quests** (`data/quests`)
- New: `q04c_the_last_mile`, `exam_strategist`, `q06b_the_collector`, `q06c_root_access`, `memory_shards`, `copied_stock`.
- Change: `q05_the_leak` prerequisite to `q04c_the_last_mile`; `q07_null_weaver_prime` prerequisite to `q06c_root_access`; add lock text (LOCK / TIP) to Leak and Mimic descriptions, as Act II quests have.

**Dialogue** (`data/dialogue`)
- `brack.tres`: Last Mile, Collector and farewell nodes; new Leak and Mimic lines; Leak turn-in line replaced.
- `sudo.tres`: Strategist nodes (the `exam_strategist` id is already in `Ranks.LADDER`).
- `hex.tres`: Copied Stock.
- New `registrar.tres`. Vesper gets a short Act III node.

**Locks** (`systems/enemies/traits`)
- `refcount_lock_trait.gd`: blobs killed by a cast that hit 3+ count as freed; others respawn.
- `diff_lock_trait.gd`: needs the cast info to say which rule fired. EchoLock keys on `skill|set`; DIFF keys on the rule index, so the program runner has to pass it along.
- `generations_lock_trait.gd`: phase index to required set index; a wrong-set hit heals.
- HandshakeLock reused on the gate drone.

**Enemies** (`data/enemies`): `the_leak`, `leak_blob`, `the_mimic`, `mirror_husk`, `the_collector`, `marker_drone`.

**Convoy and travel**
- Route terminal: seventh stop Checkpoint Approach, then a DOCKED state that can still deploy to the old stops.
- `DeckSystem`: fourth system `iff` (glyph `I`), forced offline during the Last Mile breach; `PatchPanel` gets the IFF puzzle and the two-record output. `DeckOutages` needs a look for it.
- Sweep event: a `HullBreach` variant whose saboteurs target cargo.
- `data/waypoints/act_3.tres` and the quarantine-level gating.

**Exam:** `data/exams/strategist.tres` with three sample waves; lends counters; `required_variable` checks `SkillProgram.keeps_a_count()`.

**Scenes:** `act_2_checkpoint_approach`, the `act_3_quarantine_yard` hub (docked convoy deck plus yard), and districts `act_3_registry`, `act_3_heap`, `act_3_mirror_dock`, `act_3_dangling_quarter`, `act_3_mark_yards`, `act_3_sweep`.

**Source-of-truth doc:** fill in the Act III section and the Strategist exam row, update the Act II "Ending" line to point at The Last Mile, and add the Registrar to Main Cast.

## 11. Suggested Build Order

1. The Last Mile: the IFF system, the Approach zone and docking. This is the transition, and it can be played as soon as it exists.
2. The Quarantine Yard hub with Brack, Hex, Sudo and the Registrar.
3. The Leak: the Heap and the REFCOUNT lock.
4. The Mimic and the Strategist exam (independent, either order).
5. The Collector: the Sweep and the GENERATIONS lock.
6. Root Access, then side quests and Sweeps.

## 12. Open Questions

- **Functions.** Counters are in, as the Strategist exam's new system. Functions aren't. For The Mimic, a `counter` that switches rules would be the cleanest answer to DIFF.
- **Convoy losses.** Optional and cheap: the Registrar runs a census on docking, counting Act II deeds (breaches held, cargo kept, systems never lost) and Sweep losses. That count could feed the endings later (the old REQ025 and REQ026).
- **The Mimic's last fragment.** An optional silent choice when it falls, [Delete] or [Keep]. It costs nothing now and gives the Merge and Terminate endings something earned in Act III. Leave it out if Act III should stay choice-free.
- **Hex and Sudo in Act IV.** Act IV says "no settlement". With Hex and Sudo coming along, it becomes a camp that moves with the player. Confirm that is wanted, or have them stay and reach the player remotely.
