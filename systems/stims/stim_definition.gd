class_name StimDefinition
extends Resource
## The base of a stim (health or mana "potion"). Put one on an ItemDefinition's `stim` field.
## Each dropped copy rolls its own numbers around these (StimRoller), and magic / rare copies
## get extra stim modifiers.

enum Kind { HEALTH, MANA }

@export var kind: Kind = Kind.HEALTH
## Restored per use at item level 1. Grows with item level (amount_per_level, as a fraction).
@export var base_amount: float = 60.0
@export var amount_per_level: float = 0.08
## Rolled amount is base x a random factor in this range.
@export var amount_roll_min: float = 0.85
@export var amount_roll_max: float = 1.15
## Seconds the amount is restored over. 0 = all at once.
@export var duration: float = 2.5
@export var max_charges: int = 30
@export var charges_per_use: int = 10
