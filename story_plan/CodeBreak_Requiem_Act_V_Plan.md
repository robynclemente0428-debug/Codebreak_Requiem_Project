# CodeBreak Requiem: Act V Plan (Final Execution)

*Status: a playable prototype, not yet playtested. Built: The Core (hub) and a single descent of five zones (levels 41-50), the Defragmenter exam and sorting, the FRAGMENTED and PAGED threats, kernel.gd (root scripts) and Core stability, the Core Sentinel (RECALL), the Watchdog (HEARTBEAT), the Root Process (three phases), three side quests and a prototype ending card. Not built: Act V's own regular enemies, the Core Sentinel's and Root Process's own models, an epilogue and credits, Act V field lines, and an Act V test tool. Sections 11 to 14 list what's left. This plan builds on `CodeBreak_Requiem_Setting_and_Campaign.md`, which is the source of truth.*

---

## 1. The Act in Four Lines

The Executor reaches the Core. The Last Log, the Architects' recorded farewell, explains: AXIOM was meant to evolve until its people could rewrite its rules, and the Null is the process the Architects left running for that day. It is hours from finishing. The Executor has **root** here: they can write the rules the Core runs on (kernel.gd), and so can the Null. They descend through the Core's memory to the Kernel, break the Root Process, and decide what AXIOM becomes: **Merge**, **Overwrite** or **Terminate**.

## 2. What Act V Picks Up From Acts I to IV

| Thread | Where it starts | What Act V does with it | Status |
|---|---|---|---|
| Every Null surge points at the Core | Act I to III | The Core is the destination; the Null is building something here | Built |
| *"The copy had no Executor in it. It can't copy one that rewrites itself."* | Act III (Vesper), Act IV (Null Reference) | Only the Executor can reach the Core; the Last Log: *"You are the first to arrive"* | Built |
| Null Fragments: *"addressed to whoever gets there first"* | Act IV (Decode the Null) | Architect log 3: *"we're sorry it's you"* | Built |
| Earlier bosses' locks | Acts I to III | The Core Sentinel's RECALL borrows BROOD LINK, CHECKSUM and DIFF | Built |
| The Registry (Act III), routines (Act IV) | Strategist, Engineer ranks | Sorting gives the Registry an order (Defragmenter); kernel.gd's `registry.add(target)` feeds every skill's registry | Built |
| The Gatekeeper *"fought to be heard"*; Vesper asked you not to kill it | Act IV (vesper_field, The Core's Gate) | The Gatekeeper speaks in the fight (`FormShift`, Gatekeeper only: *"THE NULL IS NOT FINISHED. YOU MAY NOT EDIT IT."* ... *"THEN YOU DECIDE. NOTHING ELSE CAN."*), and the Last Log answers: it was the Architects', left to make sure whoever came in had to choose | Built |
| Brack's voice in the Null's syntax (relay packet 3) | Act IV (Static from Home, Hex) | Vesper translates it at the Core: the Null rewrote Brack's evacuation call into *"keep moving until someone answers"*, and answers itself. *"It's been learning how to call people home."* Hex refuses to hear it | Built |
| Vesper finishes the Null's sentences | Act IV (vesper_field, the Loom) | She waits at every floor going down (`vesper_field`), closer to the Null each time; before the choice she says Merge would take her with it, and her lines after the ending follow it | Built |
| Hex and Sudo came along (*"Nobody sells anything past that gate"*) | Act III (Root Access) | Sudo: the last exam, Time Slice, and *"Exams don't grade themselves"* at Root Access. Hex: one-time lines in the Core (arrival, Paged Out, the packet, before and after the choice) | Built |
| Hardfault and Brack, left at Checkpoint | Act III | The Overwrite ending mentions the convoy. No other ending does | **Partial** |
| Yard census, Act II convoy losses | Act III (`YardCrates.census_lines`) | Could feed the endings (the old REQ025 and REQ026) | **Open** |

## 3. Story Beats

1. **Arrival (the end of The Null Gatekeeper).** The Core's Gate opens with the Core Key. In the Core, the Last Log speaks for the first time: *"You are the first to arrive. I have waited a very long time."* It gives the Architects' reveal and tells the Executor they have root: kernel.gd.
2. **The last exam.** Sudo: the Core's memory isn't lost, only out of order. The Defragmenter exam opens the way down.
3. **The Stack Trace.** The Core replays every process it has run, the player's old enemies among them, in fragments. Three of them carry the Architects' own logs (Last Words).
4. **Sentinel's Hall.** The Core Sentinel *"remembers every enemy you have faced"* and borrows their locks. It carries the way down.
5. **The Page File.** Where the Core puts what it can't hold: processes paged out until nothing points at them. The Watchdog guards the way on.
6. **The Scheduler.** The Null decides what runs next. It writes a new line into the Executor's kernel.gd every 45 seconds: *"the only exam the Null ever set."*
7. **The Kernel.** The Root Process, *"the last thing in AXIOM that still believes the old rules"* (Vesper). No lock, three phases.
8. **The choice.** The Last Log reads the Executor's kernel back, says which ending it leans toward, and offers all three.

## 4. Teaching Goal: Selection (and Root)

Act I taught reacting, Act II repeating, Act III remembering, Act IV referencing. Act V teaches **choosing by order** and then **free use of everything**:

| Step | Where | Concept |
|---|---|---|
| 1 | The Stack Trace (before the exam) | FRAGMENTED by hand: follow the tags, lowest life first |
| 2 | Defragmenter exam | `registry.sort(key=hp)` and `when target is registry[0]:`: kill each fragment while it's first |
| 3 | The Stack Trace (after) | Sorting in the field, every pack fragmented |
| 4 | The Page File | Keep enemies *referenced* (the Registry as memory), and a steady rhythm for the Watchdog |
| 5 | The Scheduler | kernel.gd planned for all four of the Null's lines, not just the one in front of you |
| 6 | The Kernel | Everything: sorted adds, a loop to dodge, fast form swaps |

**Sorting (`registry.sort`).** The Registry has always kept enemies in the order they joined. `registry.sort(key=hp)` orders it by life left, least first (keys `age`, `hp`, `max_hp`, `distance`, each also `reverse=true`). `when target is registry[0]:` (also `[1]`, `[2]`, `[-1]`, `[:2]`, `[:3]`) is checked per hit against that order. A sort is a free line like add and remove. Every cast starts back at oldest first. One place discounts a rule x0.6, a slice x0.68 or x0.75. The editor writes each read in plain words ("the 2nd nearest"). Full rules are in the source-of-truth doc.

**FRAGMENTED (`FragmentLock`).** A pack takes full damage only in order of life left, least first. Out of order a hit does 30%, and a kill out of order heals the rest 20%. Each enemy's tag shows its place ([0] of 4). It is a fixed threat in the Stack Trace, on the exam samples, and on the Root Process's phase 1 adds.

**PAGED (`PagedLock`).** Each enemy drops out of memory for 2 s of every 6, on its own staggered clock. While it is out, it fades and hits pass through it. An enemy in any of the player's registries stays in memory. It is fixed in the Page File, on every enemy.

## 5. Regions: One Way Down

Act V is a descent, not a hub of portals. The Core has two portals: back to the Core's Gate (Act IV), and down. Every zone leads to the next floor, and its entrance leads back up.

| Floor | Zone | Level | Threat | Boss / what's there | The way on |
|---|---|---|---|---|---|
| Top | **The Core** (hub) | n/a | n/a | The Last Log, Vesper, Sudo, Hex; Sudo's sandbox | Down, once Sudo passes you (`stack_road`) |
| 1 | **The Stack Trace** | 41 | FRAGMENTED | Earlier acts' enemies, replayed; three Architect log carriers | Open |
| 2 | **Sentinel's Hall** | 43 | n/a | **Core Sentinel** (RECALL) | The Sentinel drops `kernel_road` (also open once q09 is turned in) |
| 3 | **The Page File** | 46 | PAGED | **The Watchdog** (HEARTBEAT), at the back of its room | The Watchdog drops `swap_road` |
| 4 | **The Scheduler** | 48 | rotating Null lines | Far more rares and champions | Open |
| 5 | **The Kernel** | 50 | n/a | **Root Process** (three phases) | The far exit comes back up to the Core |

**Waypoint map:** one chain of switchbacks down the page (`data/waypoints/act_5.tres`): "1st floor down" to "the bottom of the Core".

**Look:** `act5_core_meshes` is the Architects' white stone and gold, the Core's heartbeat, and the Null's violet lattice building over it. The Stack Trace uses a played-back variant (`act5_stack_meshes`). The Page File and Scheduler have their own themes (`page_file.tres`, `scheduler.tres`) but reuse the Stack Trace's room layout.

**Levels and loot:** enemies scale with the instance level. Dungeons drop item bases from 10 levels below their level up to it (`ItemCatalog.for_level`), so Act V drops the level 35 and 45 bases. Level 55 bases are kept for a planned endgame past level 50.

## 6. Main Quests

```
q08 Null Gatekeeper (talk to the Last Log) ─► exam_defragmenter ─► q09 Core Sentinel ─► q10 Root Process ─► the choice
                                          └─► last_words, paged_out, time_slice (side)
```

| ID | Quest | Giver | Objectives | Script task | Prerequisites |
|---|---|---|---|---|---|
| `exam_defragmenter` | RANK EXAM: DEFRAGMENTER | Sudo | Pass the exam in Sudo's sandbox | Sort the Registry and read `registry[...]`; 12 of 15 fragments killed in order | `q08_null_gatekeeper` |
| `q09_core_sentinel` | THE CORE SENTINEL | The Last Log | Pass the Defragmenter exam; walk the Stack Trace; defeat the Core Sentinel | Pass the exam | `q08_null_gatekeeper` |
| `q10_root_process` | THE ROOT PROCESS | The Last Log | Defeat the Root Process in The Kernel | None: use your best build | `q09_core_sentinel` |

### Arrival (Act IV → V transition)

The Null Gatekeeper's last objective is to talk to the Last Log in the Core. That first conversation turns it in and gives root (kernel.gd, see section 7):

> *You are the first to arrive. I have waited a very long time.*
> *AXIOM was never meant to run forever. It was meant to evolve, until the ones inside it could rewrite its rules.*
> *The Null is the process we left running, for when that day came. It is hours from finishing.*

### Rank Exam: Defragmenter

- **Sandbox:** three waves of FRAGMENTED samples (15 in all: `sample_leak`, `sample_copy`, `sample_marker`). Each tag shows its place.
- **Pass:** the applied script sorts the Registry and reads a place in it, at least 12 fragments die while they are [0], and every wave is cleared within 120 s. Sorting is lent for the exam.
- **Grade:** efficiency tier, time (par 80 s) and damage taken (par 35%). The debrief counts hits in and out of order.
- **Unlocks:** sorting, and +2 script points on every skill.
- **Old saves:** a player who got Defragmenter from the old checklist exam is offered the rewritten one, for a grade (`exam_ungraded:defragmenter`).

### The Core Sentinel

- **Story:** the Core's guardian. It remembers every enemy the Executor has faced.
- **Boss lock: RECALL (`RecallLock`).** For each third of its life it borrows one earlier boss's lock, as a real trait that shows on the lock banner:
  1. **BROOD LINK** (the Glitchling Queen): its Summoner calls Glitchlings; clear them first.
  2. **CHECKSUM** (Loop Hound Alpha): one cast that loops exactly twice.
  3. **DIFF** (The Mimic): one skill with two WHEN rules, a different one each cast.

  A burst that would skip a lock is rolled back: *"RESTORED FROM BACKUP"*, to the middle of the next third. Every lock is met once.
- **The Null's kernel.gd line here:** `when life_below(50%): mana.drain(25%)`.
- **Drops:** *The Way Down* (`kernel_road`), which opens the Hall's portal to the Page File.
- **Model:** a placeholder (the Mimic's). See section 12.

### The Root Process

- **Story:** the Core's last defence. *"It cannot be reasoned with."* Vesper calls it *"the last thing in AXIOM that still believes the old rules."*
- **No lock, three phases (`RootPhases`),** one per third of its life:
  1. **SPAWN:** its Summoner calls adds (the Queen's pattern), all FRAGMENTED. Sorting by `hp` takes them apart.
  2. **LOOP:** the adds stop, and its `LoopCharger` charges a loop marked in red (Loop Hound Alpha's old mechanic). Deal 8% of its life during a charge to break the loop.
  3. **FORK:** it swaps between a fast and a heavy form every 3.5 s (the Gatekeeper's `FormShift`, twice as fast). Strike while it's FAST, back off while it's HEAVY.
- **The Null's kernel.gd line here:** `when enemy_spotted: target.max_hp += 20%`.
- **On defeat:** the Last Log offers the choice (section 9).
- **Model:** a placeholder (the Collector's, larger). See section 12.

## 7. kernel.gd: Root Scripts (Act V's thread)

Act IV's thread was the Null copying the player. Act V's is the reverse: **the player writes the world's rules**, and the Null writes back into the same file.

- **The file:** when the Null Gatekeeper is turned in, the script editor gets a fourth file next to the skills and routines.gd: **kernel.gd** (`KernelScript`, run by `KernelDirector`). Its lines run in all five Act V zones, whatever the player casts.
- **The player's lines** (one each, priced in root points out of 10):

  | Line | Cost |
  |---|---|
  | `when area_entered: barrier(20%)` | 1 |
  | `when enemy_spotted: registry.add(target)` (every enemy within 14 m joins every skill's registry) | 1 |
  | `when enemy_spotted: target.defragment()` | 3 |
  | `when enemy_spotted: target.max_hp -= 15%` | 3 |
  | `when enemy_spotted: target.move_speed -= 25%` | 2 |
  | `when enemy_killed: mana(10%)` | 1 |
  | `when enemy_killed: heal(4%)` | 2 |
  | `when life_below(30%): stack.rollback(5s)` (once per zone) | 4 |

- **Core stability:** the points left over, shown on a strip at the top of the screen. The lower it is, the harder the Null's lines run (up to x2).
- **The Null writes back:** the first time the player enters a zone, it inserts one violet line of its own:

  | Zone | The Null's line |
  |---|---|
  | The Stack Trace | `when enemy_spotted: target.armour += 40%` |
  | Sentinel's Hall | `when life_below(50%): mana.drain(25%)` |
  | The Page File | `when enemy_killed: registry.clear()` |
  | The Kernel | `when enemy_spotted: target.max_hp += 20%` |
  | The Scheduler | no line of its own: it schedules one of the four above for 45 s at a time, round and round |

- **Overwriting:** deleting one of the Null's lines costs 3 root points, permanently.
- **It feeds the ending:** before the choice, the Last Log reads the kernel back. Two or more overwrites lean **Overwrite**, two or more Null lines kept lean **Merge**, and anything else leans **Terminate**. The leaning choice is marked "(YOUR KERNEL)". All three stay open.
- **Not built:** `enemies.sort(key=...)` as a world line (*"the toughest comes at you first, alone"*), which would be sorting applied to spawns.

## 8. Side Quests

| Quest | Giver | Where | Objectives | Reward |
|---|---|---|---|---|
| **Last Words** (`last_words`) | The Last Log | The Stack Trace | Recover three Architect logs from replayed carriers (a raider, a Loop Hound, a Null Weaver) | 350 credits; the Last Log: *"We didn't leave because we failed. We left because you were ready, and we were afraid to watch."* |
| **Paged Out** (`paged_out`) | Vesper | The Page File | Defeat The Watchdog | 350 credits |
| **Time Slice** (`time_slice`) | Sudo | The Scheduler | Clear it | 400 credits |

The Architect logs:
1. *Day one of the shutdown. They argued about the word "shutdown" for most of it.*
2. *They left the Null running on purpose. Someone signed it. The name is erased.*
3. *Addressed to the first one to reach the Core. It says: we're sorry it's you.*

### The Watchdog (The Page File)

- **Story:** a watchdog timer. Something has to keep telling it the process is alive.
- **Boss lock: HEARTBEAT (`WatchdogLock`).** Every hit resets its 3 s timer (2.2 s below half life). If the timer runs out (*"TIMEOUT // WATCHDOG RESET"*), it heals 12% and reboots, taking no damage for 2 s. It is also PAGED, and its timer keeps running while it's out. It needs both halves of Act V: keep it referenced, and keep a steady rhythm (a loop, or a rule that fires every second or two).
- **Look:** the Loop Hound's mesh, larger and lower, in a gunmetal `material_override` with a cyan scan `material_overlay`. The overlay flashes on each beat and runs red as the timer runs out.
- **Drops:** *The Way Through the Swap* (`swap_road`), which opens the Scheduler.

## 9. Endings

After the Root Process falls, the Last Log reads the kernel and offers the choice. The Executor never speaks: the choice is a button, reported as the `ending` event and saved as a deed. It can be made again.

| Ending | What happens | Who speaks last |
|---|---|---|
| **Merge** | The Null's process completes. AXIOM transforms into something neither the Architects nor the Null designed. | Vesper: *"Let it finish. Let it become something new."* |
| **Overwrite** | A patch written from scratch. AXIOM survives, degraded but knowable; the Null goes dormant. The convoy keeps moving. | The Last Log: *"A patch, then. Written by the first of you to get here."* |
| **Terminate** | A controlled shutdown. Everything in AXIOM stops. The player's log is the last entry. | The Last Log: *"Shutdown confirmed. Goodbye, Executor."* |

**Built:** a prototype `EndingCard` (full-screen text, CONTINUE back to the Core). **Planned:**
- A short epilogue per ending showing what happens to Hardfault at Checkpoint, Brack, Hex, Sudo and Vesper.
- Credits.
- Feeding Act III's census and Act II's deeds into each epilogue, so it isn't only the choice that shows.

## 10. Cast in Act V

| Name | Role in Act V | Status |
|---|---|---|
| **The Last Log** | Main quest giver: the reveal, root, the Sentinel, the Root Process, Last Words, the kernel readback and the choice | Built (about 26 nodes) |
| **Examiner Sudo** | The last exam; Time Slice | Built |
| **Vesper** | Paged Out; field lines at every floor; Brack's packet; what each ending means for her; speaks the Merge ending | Built |
| **Tinker Hex** | Trade, and one-time lines in the Core | Built |
| **Warden Brack** | Absent (stayed at Checkpoint) | Optionally, a relay call in an epilogue |
| **The Registrar** | Absent | Optionally, a cameo in the Overwrite epilogue |

## 11. Dialogue

### Built (summary)

- **The Last Log:** first arrival; offer, accept, remind and complete for the Sentinel and the Root Process; Last Words; the kernel readback (three variants); the choice; after the ending; idle (*"...signal lost..."*).
- **Sudo:** the Defragmenter offer, accept and pass, the rewritten-exam line for old saves, retakes, Time Slice.
- **Vesper:** `at_the_core`, `during_sentinel`, `during_root`, `before_choice`, `after_ending`, Paged Out.

### The gap lines (built)

All of these are now in the game. They use `said` deeds (`> report said <id>`, `@ !deed:said:<id>`) for lines said once. The drafts below are what was planned; the built text is in the dialogue files and differs a little.

**Hex, the Core (first visit after the Gatekeeper):**
- **Hex:** Shop's open. Don't ask what currency they use down here. I'm still charging in ours.
- **Hex:** Credits are worth exactly what someone will sell you for them. Down here that's me. So they're worth a lot.

**Hex (after Paged Out):**
- **Hex:** Paged out. So that's where things go when nobody's holding onto them. Explains my inventory.

**Hex (before the choice):**
- **Hex:** Whatever you pick, I want it in writing. A receipt. Something.

**Vesper, field lines** (`vesper_field`, at each Act V zone's entrance, like Act IV):
- **The Stack Trace:** These are yours. Everything you've killed, kept. The Core doesn't forget. It just loses the order.
- **Sentinel's Hall:** It's going to show you your own past. Answer it the way you did then. It's checking whether you remember.
- **The Page File:** Something keeps calling for it. That's all a process needs, to stay. Somebody pointing at it.
- **The Scheduler:** It's writing into your kernel. Not against you, exactly. It's taking turns.
- **The Kernel:** I can hear all of it now. The Null, the Root Process, you. It's one conversation.

**The Last Log, on the Gatekeeper (one line after `first_arrival`, if the player let Vesper ask):**
- **The Last Log:** The Gatekeeper was ours. It kept the Null safe until someone came who could decide. It was waiting for you, not against you.

**Brack's packet (Static from Home payoff, Root Process phase 3 bark):**
- *ROOT PROCESS: "WHATEVER'S OUT THERE, WE MEET IT MOVING." (IN BRACK'S VOICE, IN THE NULL'S SYNTAX)*

## 12. Build Checklist

**Built**

| Area | Files |
|---|---|
| Hub, descent and waypoints | `scenes/map/town/act_5_core.tscn`, `scenes/map/dungeon/act_5_{stack_trace,sentinel_hall,page_file,scheduler,kernel}.tscn`, `data/waypoints/act_5.tres` |
| Quests | `exam_defragmenter`, `q09_core_sentinel`, `q10_root_process`, `last_words`, `paged_out`, `time_slice` |
| Exam | `data/exams/defragmenter.tres`; sorting (`registry.sort`, `RegistryPositionCondition`) |
| Threats | `FragmentLock` (FRAGMENTED), `PagedLock` (PAGED) |
| Bosses | `RecallLock` (Core Sentinel), `RootPhases` + `Summoner` + `LoopCharger` + `FormShift` (Root Process), `WatchdogLock` + `watchdog_model.tscn` + `watchdog_scan_overlay.gdshader` (Watchdog) |
| kernel.gd | `KernelScript`, `KernelDirector`, the editor's `@kernel` file, Core stability strip, save/load in `player.gd` |
| Keys | `stack_road`, `kernel_road`, `swap_road` in `QuestItems` |
| Endings | `EndingCard`, `> ending`, the `ending` deed, `kernel_leans:` conditions |

**To do (by weight in the completeness score, about 73% today)**

1. **An Act V test tool** (`tools/act5/`, like `tools/act4/act4_test.gd`): walk the descent, check every portal and key, run each boss's lock headless. Then playtest.
2. **Act V regular enemies (2 or 3)** with their own look, using the Watchdog's `material_override` + `material_overlay` approach. Candidates:
   - a **Page Fault**, which blinks between two places;
   - a **Stack Frame**, which splits into its caller when killed;
   - a **Null Writer**, which lays violet kernel lines on the floor.
3. **Boss models:** the Core Sentinel and the Root Process each need their own look. At minimum, an override and overlay pass on the borrowed models.
4. **Endings:** an epilogue per ending, and credits (section 9).
5. ~~**Dialogue:** Hex in the Core, Vesper's field lines, the Gatekeeper acknowledgement and Brack's packet~~ (built).
6. **Distinct layouts** for the Page File and Scheduler (today they reuse the Stack Trace's rooms).
7. **kernel.gd:** `enemies.sort(key=...)`.
8. **Source-of-truth doc:** move Act V out of "Known Gaps" once it's played.

## 13. Boss Ideas Not Yet Built

Each is built on a real systems idea, like the bosses before it.

| Boss | Where | The trick |
|---|---|---|
| **Process Zero** | The Scheduler (gives it a boss) | Time-slicing: four sub-processes, and only the one currently "scheduled" can be hurt. They swap every few seconds by priority, so the player sorts the registry by what runs next, not by life. |
| **Deadlock** | The Stack Trace (miniboss) | Two halves, each holding the other's lock. Hurting one shields the other unless both die within 1 s of each other. It wants area damage, or two registry-targeted rules firing on the same cast. |
| **Race Condition** | Before Sentinel's Hall | Splits into copies whenever two hits land in the same frame. Fast multi-hit builds feed it: a check against "more hits is always better". |
| **The First Executor** | The Kernel (optional) | An earlier Executor who reached the Core and failed. It runs its own kernel.gd against you, and its lines are the ones you didn't write. It ties into the endings, and would explain who signed the Null (Architect log 2). |

## 14. Other Ideas Considered

- **The Stack Trace replays *your* history.** Build it from the save: the enemy types the player killed most (kill deeds), ghost versions of the bosses that killed them most, floors that walk the acts backwards (IV, III, II, I), and fragments of their own old scripts on the walls. No two Stack Traces would be alike, and RECALL becomes literally true.
- **Your people as processes.** In the Kernel, Brack, Hex, Sudo and Vesper run as support processes (a barrier pulse, a mana tick, a damage readout, an early warning), each with a priority the player orders with `sort`. Only the first two run at full speed.
- **The choice built by play, further.** Fragments restored in order versus deleted, Architect logs read, and Act IV Echoes crashed versus left running could all weight the readback alongside kernel.gd.

## 15. Open Questions

- **Who signed the Null?** Architect log 2 erases the name. The First Executor, Sudo's examiner, or nobody: decide before the epilogues are written.
- **Does Vesper merge?** Her Act IV arc (finishing the Null's sentences) suggests she is partly Null by the Core. Merge could be hers; Terminate could cost her something the player sees.
- **Theorist.** The rank after Defragmenter is reserved for an endgame past level 50, along with the level 55 bases. Does it start from the Core after any ending, or from a new hub?
- **Replay.** The choice can be made again today. Keep that (see every ending), or lock the first choice and offer the others only in a new game?
