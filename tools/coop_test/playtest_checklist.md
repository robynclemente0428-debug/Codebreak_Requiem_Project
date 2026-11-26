# LAN co-op playtest checklist

Two machines (or two windows on one PC), the same build: the lobby refuses a different
`Coop.PROTOCOL`. One hosts, one joins. Tick each line on **both** screens unless it says otherwise.

## Scripted runs (optional, two windows)

Run the host first, then the guest, with the same extra word:

```
godot --headless res://tools/coop_test/coop_test.tscn -- host
godot --headless res://tools/coop_test/coop_test.tscn -- join
```

| Extra word | What it covers |
|---|---|
| *(none)* | lobby, travel, seeing each other, a guest's hit on the host's enemy, kill credit, shared loot |
| `warden` | the Perimeter Warden's challenge with a party |
| `locks` | the host's locks judging a guest's hits: absorbed vs landed, the Reflector's zap, a port opening on the guest's copy |
| `kernel` | Act V's pull requests: each player's own card, no pause, a trip waiting for the one answering, the host spawning a guest's TERMINATE champion, every player's lines on the shared enemies |

Each window prints `[COOP host]` / `[COOP join]` lines and ends with `ALL PASSED` or the failures.

## Enemies and their skills

- [ ] An enemy's blast, slam or projectile shows on the guest's screen, at the same moment as on the host's.
- [ ] The guest takes each enemy hit once (not twice).
- [ ] Damage numbers and hit sounds show on the guest for every player's hits, the guest's own included.
- [ ] Explode on Kill / Tremor Chain: when the guest's skill kills a pack, **every** kill explodes, on both screens.

## Boss parts

- [ ] **Loop Hound Alpha / Root Process:** the guest sees the loop marks, the telegraph and "LOOP BROKEN"; the charge hurts the guest once.
- [ ] **Null Weaver Prime:** the guest sees the same webs as the host; standing on a strand hurts, the gap is safe.
- [ ] **Glitchling Queen:** no extra summons that pop out of existence on the guest.

## Locks (the guest attacking)

- [ ] **Firewalled / Reflector enemy:** the guest's hits are reduced on the host; the guest gets zapped.
- [ ] **Loop Hound Alpha (Checksum):** `for i in range(2)` from the guest gives "LOOP 1/2", "LOOP 2/2", "CHECKSUM OK"; the port glows on both, and the banner's bar counts down.
- [ ] **The Overflow:** 6+ hits in one guest cast overflows; the spill ring shows on the guest and only hurts inside it.
- [ ] **Hollow Choir (Echo):** "PATTERN LEARNED" on both; the ring shows on the guest.
- [ ] **The Mimic (Diff):** "DIFF" / "NO DIFF" on the guest; the guest sees the mirror orb charge above it, then fly.
- [ ] **Null Weaver Prime (Grammar) / The Auditor (Audit):** the guest's right rule or graded script gets through; a wrong one says why, on the guest's screen, with the fail click.
- [ ] **Core Sentinel (Recall):** "RECALL // ..." lock swaps on both; the guest's lock tag changes with them.
- [ ] **Perimeter Warden:** the challenge panel goes round the party; a guest hitting it while locked sees "LOCKED // ANSWER THE CHALLENGE".
- [ ] **Leech on a closed port:** a guest with leech hits a closed-port boss and gains **no** life; once the port opens, leech works.

## Locks that watch the players

- [ ] **FormShift / Generations / Refcount / Watchdog:** the guest walking up first starts the fight; forms change size on both.
- [ ] **Paged:** while the guest's script registry holds it, it stays solid; drop it and it pages out on both screens.
- [ ] **Null Echo:** a guest casting near it gets copied ("COPIED: ..."); its casts on the guest's screen look like the copied skill (its supports, its repeats).
- [ ] **Corrupted Gate Guard (Handshake):** the guest taking the slam with a scripted shield up gets "HANDSHAKE OK".

## The session itself

- [ ] Travel by portal and by the waypoint map: both arrive together; a guest who falls behind catches up by itself.
- [ ] A guest changing gear or skills: the host's copy of them updates.
- [ ] Shared loot: one drop on both floors; whoever takes it first has it.
- [ ] The host leaving ends the session for the guest, back to the main menu with the reason.
- [ ] No "is_inside_tree" errors or "above the MTU" warnings in the editor's Debugger while playing.

## Not covered yet

Joining mid-game, quests, and the convoy's and dock's wave fights.

## Act V: the Null's pull requests

- [ ] Each player who has root gets their own card on a new floor; a visitor (carried there) gets none.
- [ ] The game keeps running, but nothing hurts the one answering; the others see **ANSWERING...** over them.
- [ ] A portal or the waypoint map while someone is answering: **WAITING FOR <name>**, and nobody leaves.
- [ ] A guest's **TERMINATE**: the champion appears by the guest on **both** screens and stays.
- [ ] A guest's `max_hp -= 15%` / `move_speed -= 25%` / merged Null lines change the enemies on the host too.
- [ ] The KERNEL card shows each partner's answers (`NAME  M O T -`).
