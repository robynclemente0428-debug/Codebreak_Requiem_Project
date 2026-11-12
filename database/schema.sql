-- =====================================================================
--  CodeBreak: Requiem  -  relational database schema
--  Dialect: SQLite 3 (also runs on PostgreSQL with minor type changes)
--
--  Mirrors what the game stores today:
--    PART A  game content   -> res://data/**/*.tres  (ItemDefinition, AffixDefinition, ...)
--    PART B  player saves   -> user://saves/slot_N.json  (SaveManager, player.write_save)
--
--  Skill-script programs (SkillProgram / ProgramRule trees) stay as JSON
--  documents (the output of SkillProgram.to_dict()); they are nested trees
--  of rules -> conditions / effects / loops / branches and are always read
--  and written whole.
-- =====================================================================

PRAGMA foreign_keys = ON;

-- =====================================================================
--  PART 0  LOOKUP TABLES (GDScript enums)
-- =====================================================================

-- StatTypes.Stat
CREATE TABLE stat (
    stat_id      INTEGER PRIMARY KEY,          -- enum value
    code         TEXT NOT NULL UNIQUE          -- 'MAX_HEALTH', 'ARMOUR', 'MOVE_SPEED', ...
);

-- Modifier.ModOp
CREATE TABLE mod_op (
    mod_op_id    INTEGER PRIMARY KEY,
    code         TEXT NOT NULL UNIQUE
);
INSERT INTO mod_op VALUES (0,'FLAT_ADD'),(1,'PERCENT_ADD'),(2,'PERCENT_MULT'),(3,'OVERRIDE');

-- TagTypes.ItemTag / EnemyTag / TagGem / Group, in one table
CREATE TABLE tag (
    tag_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    tag_family   TEXT NOT NULL CHECK (tag_family IN ('item','enemy','gem','affix_group')),
    code         TEXT NOT NULL,                -- 'MELEE', 'RANGED', 'STRIKE', ...
    enum_value   INTEGER NOT NULL,             -- value in the GDScript enum
    UNIQUE (tag_family, code)
);

-- EquipmentSlots.Slot
CREATE TABLE equipment_slot (
    slot_id      INTEGER PRIMARY KEY,
    code         TEXT NOT NULL UNIQUE,
    is_stim_slot INTEGER NOT NULL DEFAULT 0 CHECK (is_stim_slot IN (0,1))
);
INSERT INTO equipment_slot VALUES
    (0,'WEAPON',0),(1,'OFF_HAND',0),(2,'HEAD',0),(3,'BODY',0),
    (4,'HANDS',0),(5,'FEET',0),(6,'STIM_1',1),(7,'STIM_2',1);

CREATE TABLE rarity (
    rarity_id    TEXT PRIMARY KEY,             -- 'normal','magic','rare','champion','unique'
    sort_order   INTEGER NOT NULL
);
INSERT INTO rarity VALUES ('normal',0),('magic',1),('rare',2),('champion',3);

-- Ranks.LADDER (exam_id is filled after the exam table exists)
CREATE TABLE rank (
    rank_id      TEXT PRIMARY KEY,             -- '' row stored as 'initiate'
    display_name TEXT NOT NULL,                -- 'OPERATOR'
    ladder_order INTEGER NOT NULL UNIQUE
);
INSERT INTO rank VALUES
    ('initiate','INITIATE',0),('operator','OPERATOR',1),('architect','ARCHITECT',2),
    ('strategist','STRATEGIST',3),('engineer','ENGINEER',4),('defragmenter','DEFRAGMENTER',5),
    ('theorist','THEORIST',6);

-- =====================================================================
--  PART A  GAME CONTENT
-- =====================================================================

-- ---------- Classes (ClassData + ClassTrait) ----------
CREATE TABLE class_trait (
    class_trait_id             TEXT PRIMARY KEY,   -- same id as its class
    display_name               TEXT NOT NULL,
    description                TEXT,
    knob_cost_mult             REAL NOT NULL DEFAULT 1.0,
    knob_effect_mult           REAL NOT NULL DEFAULT 1.0,
    extra_points               REAL NOT NULL DEFAULT 0.0,
    buff_cost_mult             REAL NOT NULL DEFAULT 1.0,
    nth_rule_cost_mult         REAL NOT NULL DEFAULT 1.0,
    nth_rule_effect_mult       REAL NOT NULL DEFAULT 1.0,
    nth_rule_effect_per_n      REAL NOT NULL DEFAULT 0.0,
    hit_rule_cost_mult         REAL NOT NULL DEFAULT 1.0,
    hit_rule_effect_mult       REAL NOT NULL DEFAULT 1.0,
    per_hit_any_knob           INTEGER NOT NULL DEFAULT 0,
    armour_per_always_rule     REAL NOT NULL DEFAULT 0.0,
    armour_per_when_fire       REAL NOT NULL DEFAULT 0.0,
    when_buff_seconds          REAL NOT NULL DEFAULT 4.0,
    damage_per_10_armour       REAL NOT NULL DEFAULT 0.0,
    move_speed_per_rule        REAL NOT NULL DEFAULT 0.0,
    move_speed_per_knob_step   REAL NOT NULL DEFAULT 0.0,
    moving_damage_more         REAL NOT NULL DEFAULT 0.0,
    moving_damage_more_per_speed REAL NOT NULL DEFAULT 0.0,
    full_life_damage_more      REAL NOT NULL DEFAULT 0.0,
    phase_through_enemies      INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE character_class (
    class_id               TEXT PRIMARY KEY,       -- 'gladiator', 'raider', ...
    display_name           TEXT NOT NULL,
    tagline                TEXT,
    description            TEXT,
    sort_order             INTEGER NOT NULL DEFAULT 0,
    accent_color           TEXT NOT NULL DEFAULT '#00E5FF',
    base_strength          INTEGER NOT NULL DEFAULT 8,
    base_dexterity         INTEGER NOT NULL DEFAULT 8,
    base_intelligence      INTEGER NOT NULL DEFAULT 8,
    model_scene_path       TEXT,
    model_scale            REAL NOT NULL DEFAULT 1.0,
    starting_weapon_id     TEXT REFERENCES item(item_id),
    starting_skill_gem_id  TEXT REFERENCES item(item_id),
    class_trait_id         TEXT REFERENCES class_trait(class_trait_id)
);

-- ---------- Base types ----------
CREATE TABLE weapon_type (
    weapon_type_id     TEXT PRIMARY KEY,           -- 'sniper_rifle', 'assault_rifle', ...
    display_name       TEXT NOT NULL,
    base_range         REAL NOT NULL DEFAULT 0.3,
    animation_set      TEXT,
    two_handed         INTEGER NOT NULL DEFAULT 0,
    skill_mana_cost    REAL NOT NULL DEFAULT 0.0,
    attack_behavior    TEXT                        -- script path
);
CREATE TABLE weapon_type_tag (
    weapon_type_id TEXT NOT NULL REFERENCES weapon_type(weapon_type_id) ON DELETE CASCADE,
    tag_id         INTEGER NOT NULL REFERENCES tag(tag_id),
    PRIMARY KEY (weapon_type_id, tag_id)
);

CREATE TABLE equipment_type (
    equipment_type_id  TEXT PRIMARY KEY,
    display_name       TEXT NOT NULL,
    slot_id            INTEGER NOT NULL REFERENCES equipment_slot(slot_id)
);
CREATE TABLE equipment_type_tag (
    equipment_type_id TEXT NOT NULL REFERENCES equipment_type(equipment_type_id) ON DELETE CASCADE,
    tag_id            INTEGER NOT NULL REFERENCES tag(tag_id),
    PRIMARY KEY (equipment_type_id, tag_id)
);

-- ---------- Skill & support gems ----------
CREATE TABLE skill_gem (
    skill_gem_id       TEXT PRIMARY KEY,
    display_name       TEXT NOT NULL,
    description        TEXT,
    behavior_script    TEXT,                       -- strike / slam / shoot / blast
    max_support_slots  INTEGER NOT NULL DEFAULT 3,
    base_mana_cost     REAL NOT NULL DEFAULT 0.0,
    base_flags_json    TEXT NOT NULL DEFAULT '{}', -- {"arc_angle":90,"range":2.5}
    program_limits_json TEXT                       -- SkillProgramLimits
);
CREATE TABLE skill_gem_tag (
    skill_gem_id TEXT NOT NULL REFERENCES skill_gem(skill_gem_id) ON DELETE CASCADE,
    tag_id       INTEGER NOT NULL REFERENCES tag(tag_id),
    PRIMARY KEY (skill_gem_id, tag_id)
);
CREATE TABLE skill_gem_modifier (
    skill_gem_id TEXT NOT NULL REFERENCES skill_gem(skill_gem_id) ON DELETE CASCADE,
    seq          INTEGER NOT NULL,
    stat_id      INTEGER NOT NULL REFERENCES stat(stat_id),
    mod_op_id    INTEGER NOT NULL REFERENCES mod_op(mod_op_id),
    value        REAL NOT NULL,
    PRIMARY KEY (skill_gem_id, seq)
);
CREATE TABLE skill_gem_required_weapon (
    skill_gem_id   TEXT NOT NULL REFERENCES skill_gem(skill_gem_id) ON DELETE CASCADE,
    weapon_type_id TEXT NOT NULL REFERENCES weapon_type(weapon_type_id),
    PRIMARY KEY (skill_gem_id, weapon_type_id)
);

CREATE TABLE support_gem (
    support_gem_id      TEXT PRIMARY KEY,          -- 'multicast', 'for_loop', 'try_except', ...
    display_name        TEXT NOT NULL,
    description         TEXT,
    behavior_script     TEXT,
    animation_override  TEXT,
    mana_cost_increase  REAL NOT NULL DEFAULT 0.25,
    flag_modifiers_json TEXT NOT NULL DEFAULT '{}',
    program_knobs_json  TEXT NOT NULL DEFAULT '[]' -- Array[SkillKnob]
);
CREATE TABLE support_gem_allowed_tag (
    support_gem_id TEXT NOT NULL REFERENCES support_gem(support_gem_id) ON DELETE CASCADE,
    tag_id         INTEGER NOT NULL REFERENCES tag(tag_id),
    PRIMARY KEY (support_gem_id, tag_id)
);
CREATE TABLE support_gem_modifier (
    support_gem_id TEXT NOT NULL REFERENCES support_gem(support_gem_id) ON DELETE CASCADE,
    seq            INTEGER NOT NULL,
    stat_id        INTEGER NOT NULL REFERENCES stat(stat_id),
    mod_op_id      INTEGER NOT NULL REFERENCES mod_op(mod_op_id),
    value          REAL NOT NULL,
    PRIMARY KEY (support_gem_id, seq)
);

-- ---------- Stims (StimDefinition) ----------
CREATE TABLE stim (
    stim_id          TEXT PRIMARY KEY,
    kind             TEXT NOT NULL CHECK (kind IN ('HEALTH','MANA')),
    base_amount      REAL NOT NULL DEFAULT 60.0,
    amount_per_level REAL NOT NULL DEFAULT 0.08,
    amount_roll_min  REAL NOT NULL DEFAULT 0.85,
    amount_roll_max  REAL NOT NULL DEFAULT 1.15,
    duration         REAL NOT NULL DEFAULT 2.5,
    max_charges      INTEGER NOT NULL DEFAULT 30,
    charges_per_use  INTEGER NOT NULL DEFAULT 10
);

-- ---------- Items (ItemDefinition) ----------
-- Exactly one "kind" reference is set, chosen by item_kind.
CREATE TABLE item (
    item_id            TEXT PRIMARY KEY,           -- 'field_rifle', 'field_health_stim', ...
    display_name       TEXT NOT NULL,
    item_kind          TEXT NOT NULL CHECK (item_kind IN
                         ('weapon','equipment','skill_gem','support_gem','stim','quest')),
    weapon_type_id     TEXT REFERENCES weapon_type(weapon_type_id),
    equipment_type_id  TEXT REFERENCES equipment_type(equipment_type_id),
    skill_gem_id       TEXT REFERENCES skill_gem(skill_gem_id),
    support_gem_id     TEXT REFERENCES support_gem(support_gem_id),
    stim_id            TEXT REFERENCES stim(stim_id),
    item_level         INTEGER NOT NULL DEFAULT 1,
    base_value         INTEGER NOT NULL DEFAULT 10,    -- credits, normal rarity
    icon_path          TEXT,
    mesh_path          TEXT,
    CHECK ( (item_kind = 'weapon'      AND weapon_type_id    IS NOT NULL)
         OR (item_kind = 'equipment'   AND equipment_type_id IS NOT NULL)
         OR (item_kind = 'skill_gem'   AND skill_gem_id      IS NOT NULL)
         OR (item_kind = 'support_gem' AND support_gem_id    IS NOT NULL)
         OR (item_kind = 'stim'        AND stim_id           IS NOT NULL)
         OR (item_kind = 'quest') )
);
CREATE TABLE item_base_stat (
    item_id  TEXT NOT NULL REFERENCES item(item_id) ON DELETE CASCADE,
    stat_id  INTEGER NOT NULL REFERENCES stat(stat_id),
    value    REAL NOT NULL,
    PRIMARY KEY (item_id, stat_id)
);
CREATE TABLE item_allowed_affix_tag (
    item_id TEXT NOT NULL REFERENCES item(item_id) ON DELETE CASCADE,
    tag_id  INTEGER NOT NULL REFERENCES tag(tag_id),
    PRIMARY KEY (item_id, tag_id)
);

-- ---------- Affixes (AffixDefinition) ----------
CREATE TABLE affix (
    affix_id         TEXT PRIMARY KEY,
    display_name     TEXT NOT NULL,
    affix_type       TEXT NOT NULL CHECK (affix_type IN ('prefix','suffix')),
    shape            TEXT NOT NULL CHECK (shape IN
                       ('SIMPLE','DAMAGE_RANGE','PERCENT_RANGE','PERCENT_MULT_RANGE')),
    weight           INTEGER NOT NULL DEFAULT 100,
    min_item_level   INTEGER NOT NULL DEFAULT 1,
    level_half_life  REAL NOT NULL DEFAULT 5.0,
    -- SIMPLE / PERCENT shapes
    stat_id          INTEGER REFERENCES stat(stat_id),
    mod_op_id        INTEGER REFERENCES mod_op(mod_op_id),
    min_value        REAL,
    max_value        REAL,
    -- DAMAGE_RANGE shape ("adds X-Y damage")
    min_stat_id      INTEGER REFERENCES stat(stat_id),
    max_stat_id      INTEGER REFERENCES stat(stat_id),
    added_min_low    REAL, added_min_high REAL,
    added_max_low    REAL, added_max_high REAL
);
CREATE TABLE affix_tag (
    affix_id TEXT NOT NULL REFERENCES affix(affix_id) ON DELETE CASCADE,
    tag_id   INTEGER NOT NULL REFERENCES tag(tag_id),          -- item tags it can roll on
    PRIMARY KEY (affix_id, tag_id)
);
CREATE TABLE affix_exclusivity_group (
    affix_id TEXT NOT NULL REFERENCES affix(affix_id) ON DELETE CASCADE,
    tag_id   INTEGER NOT NULL REFERENCES tag(tag_id),          -- affix_group family
    PRIMARY KEY (affix_id, tag_id)
);

-- ---------- Enemies ----------
-- EnemyModifierDefinition; data/enemy_traits/*.tres are the same resource with an
-- on_spawn script, flagged is_trait.
CREATE TABLE enemy_modifier (
    enemy_modifier_id   TEXT PRIMARY KEY,          -- 'molten', 'fast', 'fragmented', ...
    display_name_prefix TEXT,
    weight              INTEGER NOT NULL DEFAULT 100,
    min_rarity          TEXT NOT NULL DEFAULT 'magic' REFERENCES rarity(rarity_id),
    on_spawn_script     TEXT,
    is_trait            INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE enemy_modifier_tag (
    enemy_modifier_id TEXT NOT NULL REFERENCES enemy_modifier(enemy_modifier_id) ON DELETE CASCADE,
    tag_id            INTEGER NOT NULL REFERENCES tag(tag_id),
    PRIMARY KEY (enemy_modifier_id, tag_id)
);
CREATE TABLE enemy_modifier_stat (
    enemy_modifier_id TEXT NOT NULL REFERENCES enemy_modifier(enemy_modifier_id) ON DELETE CASCADE,
    seq               INTEGER NOT NULL,
    stat_id           INTEGER NOT NULL REFERENCES stat(stat_id),
    mod_op_id         INTEGER NOT NULL REFERENCES mod_op(mod_op_id),
    value             REAL NOT NULL,
    PRIMARY KEY (enemy_modifier_id, seq)
);

CREATE TABLE enemy (
    enemy_id            TEXT PRIMARY KEY,
    display_name        TEXT NOT NULL,
    scene_path          TEXT,
    model_scene_path    TEXT,
    capsule_radius      REAL NOT NULL DEFAULT 0.4,
    capsule_height      REAL NOT NULL DEFAULT 1.8,
    max_health          REAL NOT NULL DEFAULT 30.0,
    armour              REAL NOT NULL DEFAULT 5.0,
    move_speed          REAL NOT NULL DEFAULT 4.0,
    aggro_range         REAL NOT NULL DEFAULT 15.0,
    attack_range        REAL NOT NULL DEFAULT 2.0,
    preferred_distance  REAL NOT NULL DEFAULT 0.0,
    flee_distance       REAL NOT NULL DEFAULT 0.0,
    kite_delay_min      REAL NOT NULL DEFAULT 0.5,
    kite_delay_max      REAL NOT NULL DEFAULT 1.0,
    min_attack_damage   REAL NOT NULL DEFAULT 4.0,
    max_attack_damage   REAL NOT NULL DEFAULT 8.0,
    attack_speed        REAL NOT NULL DEFAULT 0.5,
    basic_attack_enabled INTEGER NOT NULL DEFAULT 1,
    skill_cooldown      REAL NOT NULL DEFAULT 6.0,
    cooldown_jitter     REAL NOT NULL DEFAULT 2.0,
    cast_lock_fraction  REAL NOT NULL DEFAULT 1.0,
    act_boss            INTEGER NOT NULL DEFAULT 0,
    skill_flag_overrides_json TEXT NOT NULL DEFAULT '{}',
    skill_loops_json    TEXT NOT NULL DEFAULT '{}',
    CHECK (flee_distance <= preferred_distance OR preferred_distance = 0)
);
CREATE TABLE enemy_skill (
    enemy_id     TEXT NOT NULL REFERENCES enemy(enemy_id) ON DELETE CASCADE,
    seq          INTEGER NOT NULL,
    skill_gem_id TEXT NOT NULL REFERENCES skill_gem(skill_gem_id),
    PRIMARY KEY (enemy_id, seq)
);
CREATE TABLE enemy_skill_support (
    enemy_id       TEXT NOT NULL,
    seq            INTEGER NOT NULL,
    support_gem_id TEXT NOT NULL REFERENCES support_gem(support_gem_id),
    PRIMARY KEY (enemy_id, seq, support_gem_id),
    FOREIGN KEY (enemy_id, seq) REFERENCES enemy_skill(enemy_id, seq) ON DELETE CASCADE
);
CREATE TABLE enemy_allowed_modifier_tag (
    enemy_id TEXT NOT NULL REFERENCES enemy(enemy_id) ON DELETE CASCADE,
    tag_id   INTEGER NOT NULL REFERENCES tag(tag_id),
    PRIMARY KEY (enemy_id, tag_id)
);
CREATE TABLE enemy_innate_trait (
    enemy_id          TEXT NOT NULL REFERENCES enemy(enemy_id) ON DELETE CASCADE,
    trait_script      TEXT NOT NULL,           -- systems/enemies/traits/*_lock_trait.gd
    PRIMARY KEY (enemy_id, trait_script)
);
CREATE TABLE enemy_pool_rarity (
    enemy_id  TEXT NOT NULL REFERENCES enemy(enemy_id) ON DELETE CASCADE,
    rarity_id TEXT NOT NULL REFERENCES rarity(rarity_id),
    PRIMARY KEY (enemy_id, rarity_id)
);

-- ---------- World: acts & waypoints ----------
CREATE TABLE act (
    act_number    INTEGER PRIMARY KEY,
    title         TEXT NOT NULL,                -- 'ACT I'
    subtitle      TEXT,
    convoy_route  INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE waypoint (
    waypoint_id         TEXT PRIMARY KEY,
    act_number          INTEGER NOT NULL REFERENCES act(act_number),
    seq                 INTEGER NOT NULL,       -- order within the act
    display_name        TEXT NOT NULL,
    kind                TEXT NOT NULL CHECK (kind IN ('TOWN','DUNGEON','BOSS')),
    scene_path          TEXT NOT NULL,
    spawn_id            TEXT NOT NULL DEFAULT 'default',
    dungeon_level       INTEGER NOT NULL DEFAULT 0,
    map_x               REAL NOT NULL DEFAULT 0.5,
    map_y               REAL NOT NULL DEFAULT 0.5,
    note                TEXT,
    on_foot             INTEGER NOT NULL DEFAULT 0,
    random_threats_min  INTEGER NOT NULL DEFAULT 0,
    random_threats_max  INTEGER NOT NULL DEFAULT 0,
    route_after_id      TEXT REFERENCES waypoint(waypoint_id),
    route_needs_key     TEXT,                   -- a QuestItems recover id
    route_needs_text    TEXT,
    UNIQUE (act_number, seq)
);
CREATE TABLE waypoint_link (
    from_waypoint_id TEXT NOT NULL REFERENCES waypoint(waypoint_id) ON DELETE CASCADE,
    to_waypoint_id   TEXT NOT NULL REFERENCES waypoint(waypoint_id) ON DELETE CASCADE,
    PRIMARY KEY (from_waypoint_id, to_waypoint_id)
);
CREATE TABLE waypoint_threat (
    waypoint_id TEXT NOT NULL REFERENCES waypoint(waypoint_id) ON DELETE CASCADE,
    threat_id   TEXT NOT NULL,                  -- DungeonThreats id
    PRIMARY KEY (waypoint_id, threat_id)
);
CREATE TABLE waypoint_required_quest (
    waypoint_id TEXT NOT NULL REFERENCES waypoint(waypoint_id) ON DELETE CASCADE,
    quest_id    TEXT NOT NULL REFERENCES quest(quest_id),
    PRIMARY KEY (waypoint_id, quest_id)
);

-- ---------- Quests (QuestDefinition + Objective) ----------
CREATE TABLE quest (
    quest_id              TEXT PRIMARY KEY,     -- 'q04_the_overflow', 'exam_defragmenter', ...
    title                 TEXT NOT NULL,
    description           TEXT,
    ordered               INTEGER NOT NULL DEFAULT 0,
    reward_credits        INTEGER NOT NULL DEFAULT 0,
    reward_support_choice INTEGER NOT NULL DEFAULT 0,
    next_quest_id         TEXT REFERENCES quest(quest_id),
    grants_rank_id        TEXT REFERENCES rank(rank_id)
);
CREATE TABLE quest_prerequisite (
    quest_id        TEXT NOT NULL REFERENCES quest(quest_id) ON DELETE CASCADE,
    requires_quest_id TEXT NOT NULL REFERENCES quest(quest_id),
    PRIMARY KEY (quest_id, requires_quest_id),
    CHECK (quest_id <> requires_quest_id)
);
CREATE TABLE quest_reward_item (
    quest_id TEXT NOT NULL REFERENCES quest(quest_id) ON DELETE CASCADE,
    seq      INTEGER NOT NULL,
    item_id  TEXT NOT NULL REFERENCES item(item_id),
    PRIMARY KEY (quest_id, seq)
);
CREATE TABLE quest_objective (
    quest_id    TEXT NOT NULL REFERENCES quest(quest_id) ON DELETE CASCADE,
    seq         INTEGER NOT NULL,               -- index into QuestState.progress
    description TEXT NOT NULL,
    kind        TEXT NOT NULL,                  -- 'kill','recover','talk','enter_area','exam_passed',...
    target      TEXT NOT NULL DEFAULT '',       -- '' = anything of that kind
    required    INTEGER NOT NULL DEFAULT 1 CHECK (required > 0),
    hidden      INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (quest_id, seq)
);

-- ---------- Rank exams (ExamSpec) ----------
CREATE TABLE exam (
    exam_id                  TEXT PRIMARY KEY,  -- 'exam_operator'
    rank_id                  TEXT NOT NULL UNIQUE REFERENCES rank(rank_id),
    title                    TEXT NOT NULL,
    brief_json               TEXT NOT NULL DEFAULT '[]',
    required_condition       TEXT,
    required_condition_label TEXT,
    required_fires           INTEGER NOT NULL DEFAULT 3,
    required_stop_loop       INTEGER NOT NULL DEFAULT 0,
    required_variable        INTEGER NOT NULL DEFAULT 0,
    required_routine         INTEGER NOT NULL DEFAULT 0,
    required_callers         INTEGER NOT NULL DEFAULT 3,
    required_order           INTEGER NOT NULL DEFAULT 0,
    time_limit               REAL NOT NULL DEFAULT 75.0,
    par_time                 REAL NOT NULL DEFAULT 45.0,
    par_damage               REAL NOT NULL DEFAULT 0.30,
    fail_health              REAL NOT NULL DEFAULT 0.25,
    enemy_level              INTEGER NOT NULL DEFAULT 1,
    spawn_radius             REAL NOT NULL DEFAULT 8.5
);
CREATE TABLE exam_wave (
    exam_id   TEXT NOT NULL REFERENCES exam(exam_id) ON DELETE CASCADE,
    wave_no   INTEGER NOT NULL,
    size      INTEGER NOT NULL,
    enemy_id  TEXT NOT NULL REFERENCES enemy(enemy_id),
    name      TEXT,
    note      TEXT,
    tint      TEXT,                              -- '#RRGGBB'
    PRIMARY KEY (exam_id, wave_no)
);
CREATE TABLE exam_wave_modifier (
    exam_id           TEXT NOT NULL REFERENCES exam(exam_id) ON DELETE CASCADE,
    enemy_modifier_id TEXT NOT NULL REFERENCES enemy_modifier(enemy_modifier_id),
    PRIMARY KEY (exam_id, enemy_modifier_id)
);
CREATE TABLE exam_lent_item (                    -- ExamSpec.lends
    exam_id  TEXT NOT NULL REFERENCES exam(exam_id) ON DELETE CASCADE,
    item_id  TEXT NOT NULL REFERENCES item(item_id),
    PRIMARY KEY (exam_id, item_id)
);

-- ---------- Shops & NPCs ----------
CREATE TABLE shop (
    shop_id                TEXT PRIMARY KEY,
    display_name           TEXT NOT NULL DEFAULT 'VENDOR',
    greeting               TEXT,
    random_slots           INTEGER NOT NULL DEFAULT 6,
    magic_chance           REAL NOT NULL DEFAULT 0.30 CHECK (magic_chance BETWEEN 0 AND 1),
    rare_chance            REAL NOT NULL DEFAULT 0.10 CHECK (rare_chance  BETWEEN 0 AND 1),
    buy_markup             REAL NOT NULL DEFAULT 1.5,
    sell_ratio             REAL NOT NULL DEFAULT 0.4,
    infinite_fixed         INTEGER NOT NULL DEFAULT 1,
    use_catalog            INTEGER NOT NULL DEFAULT 1,
    include_gems           INTEGER NOT NULL DEFAULT 0,
    level_window           INTEGER NOT NULL DEFAULT 20,
    level_bias             REAL NOT NULL DEFAULT 0.5,
    allow_reroll           INTEGER NOT NULL DEFAULT 1,
    reroll_base_cost       INTEGER NOT NULL DEFAULT 40,
    reroll_cost_per_level  INTEGER NOT NULL DEFAULT 10,
    reroll_cost_growth     REAL NOT NULL DEFAULT 1.5
);
CREATE TABLE shop_item (
    shop_id  TEXT NOT NULL REFERENCES shop(shop_id) ON DELETE CASCADE,
    item_id  TEXT NOT NULL REFERENCES item(item_id),
    list     TEXT NOT NULL CHECK (list IN ('fixed','random_pool','excluded')),
    PRIMARY KEY (shop_id, item_id, list)
);
CREATE TABLE shop_catalog_folder (
    shop_id TEXT NOT NULL REFERENCES shop(shop_id) ON DELETE CASCADE,
    folder  TEXT NOT NULL,                       -- 'res://data/items/weapons'
    PRIMARY KEY (shop_id, folder)
);

CREATE TABLE dialogue (
    dialogue_id TEXT PRIMARY KEY,                -- 'hex', 'sudo', ...
    source      TEXT NOT NULL                    -- DialogueData.source script
);

-- =====================================================================
--  PART B  PLAYER DATA (one save slot = one character)
-- =====================================================================

CREATE TABLE player_character (
    character_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    slot_no            INTEGER NOT NULL UNIQUE CHECK (slot_no BETWEEN 0 AND 9), -- MAX_SLOTS
    save_version       INTEGER NOT NULL DEFAULT 1,
    name               TEXT NOT NULL CHECK (length(trim(name)) > 0),
    class_id           TEXT NOT NULL REFERENCES character_class(class_id),
    level              INTEGER NOT NULL DEFAULT 1 CHECK (level >= 1),
    xp                 INTEGER NOT NULL DEFAULT 0 CHECK (xp >= 0),
    strength           INTEGER NOT NULL,
    dexterity          INTEGER NOT NULL,
    intelligence       INTEGER NOT NULL,
    credits            INTEGER NOT NULL DEFAULT 0 CHECK (credits >= 0),  -- CurrencyComponent
    last_town_id       TEXT REFERENCES waypoint(waypoint_id),
    active_script_set  INTEGER NOT NULL DEFAULT 0,
    playtime_seconds   INTEGER NOT NULL DEFAULT 0,
    created_at         INTEGER NOT NULL,                      -- unix time
    updated_at         INTEGER NOT NULL
);

-- Every ItemInstance the character owns, wherever it sits.
CREATE TABLE item_instance (
    instance_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    character_id      INTEGER NOT NULL REFERENCES player_character(character_id) ON DELETE CASCADE,
    item_id           TEXT NOT NULL REFERENCES item(item_id),
    rarity_id         TEXT NOT NULL DEFAULT 'normal' REFERENCES rarity(rarity_id),
    item_level        INTEGER NOT NULL DEFAULT 1,
    copied            INTEGER NOT NULL DEFAULT 0,
    stim_base_amount  REAL,                                   -- stims only
    charges           INTEGER NOT NULL DEFAULT -1             -- -1 = not a stim
);
CREATE TABLE item_instance_affix (
    instance_id   INTEGER NOT NULL REFERENCES item_instance(instance_id) ON DELETE CASCADE,
    seq           INTEGER NOT NULL,
    affix_id      TEXT NOT NULL REFERENCES affix(affix_id),
    rolled_value  REAL,                                       -- SIMPLE / PERCENT shapes
    rolled_min    REAL,                                       -- DAMAGE_RANGE shape
    rolled_max    REAL,
    PRIMARY KEY (instance_id, seq)
);
CREATE TABLE item_instance_stim_mod (
    instance_id INTEGER NOT NULL REFERENCES item_instance(instance_id) ON DELETE CASCADE,
    mod_id      TEXT NOT NULL,
    PRIMARY KEY (instance_id, mod_id)
);

-- Where an instance is: backpack, equipped, or socketed. An instance appears in at most one.
CREATE TABLE inventory_entry (
    character_id INTEGER NOT NULL REFERENCES player_character(character_id) ON DELETE CASCADE,
    position     INTEGER NOT NULL,
    instance_id  INTEGER NOT NULL UNIQUE REFERENCES item_instance(instance_id) ON DELETE CASCADE,
    PRIMARY KEY (character_id, position)
);
CREATE TABLE equipped_item (
    character_id INTEGER NOT NULL REFERENCES player_character(character_id) ON DELETE CASCADE,
    slot_id      INTEGER NOT NULL REFERENCES equipment_slot(slot_id),
    instance_id  INTEGER NOT NULL UNIQUE REFERENCES item_instance(instance_id) ON DELETE CASCADE,
    PRIMARY KEY (character_id, slot_id)
);

-- SkillComponent.sockets
CREATE TABLE skill_socket (
    socket_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    character_id     INTEGER NOT NULL REFERENCES player_character(character_id) ON DELETE CASCADE,
    socket_index     INTEGER NOT NULL,
    gem_instance_id  INTEGER UNIQUE REFERENCES item_instance(instance_id) ON DELETE SET NULL,
    action           TEXT,                                    -- input action bound to it
    UNIQUE (character_id, socket_index)
);
CREATE TABLE skill_socket_support (
    socket_id            INTEGER NOT NULL REFERENCES skill_socket(socket_id) ON DELETE CASCADE,
    position             INTEGER NOT NULL,
    support_instance_id  INTEGER NOT NULL UNIQUE REFERENCES item_instance(instance_id) ON DELETE CASCADE,
    PRIMARY KEY (socket_id, position)
);

-- Script sets: each socket holds one program per set; set names are per character.
CREATE TABLE script_set_name (
    character_id INTEGER NOT NULL REFERENCES player_character(character_id) ON DELETE CASCADE,
    set_index    INTEGER NOT NULL,
    name         TEXT NOT NULL,
    PRIMARY KEY (character_id, set_index)
);
CREATE TABLE skill_program (
    socket_id    INTEGER NOT NULL REFERENCES skill_socket(socket_id) ON DELETE CASCADE,
    set_index    INTEGER NOT NULL,
    program_json TEXT NOT NULL,                               -- SkillProgram.to_dict()
    PRIMARY KEY (socket_id, set_index)
);

-- Script library (rank ARCHITECT): named programs kept per skill gem, max 12.
CREATE TABLE script_library_entry (
    character_id INTEGER NOT NULL REFERENCES player_character(character_id) ON DELETE CASCADE,
    skill_gem_id TEXT NOT NULL REFERENCES skill_gem(skill_gem_id),
    name         TEXT NOT NULL CHECK (length(name) <= 14),
    program_json TEXT NOT NULL,
    saved_order  INTEGER NOT NULL,
    PRIMARY KEY (character_id, skill_gem_id, name)
);

-- Routines (rank ENGINEER): shared callable bodies.
CREATE TABLE script_routine (
    character_id INTEGER NOT NULL REFERENCES player_character(character_id) ON DELETE CASCADE,
    seq          INTEGER NOT NULL,
    name         TEXT NOT NULL,
    body_json    TEXT NOT NULL,                               -- ProgramRoutine body
    PRIMARY KEY (character_id, seq),
    UNIQUE (character_id, name)
);

-- ---------- Quest progress (QuestManager.to_dict) ----------
CREATE TABLE character_quest (
    character_id INTEGER NOT NULL REFERENCES player_character(character_id) ON DELETE CASCADE,
    quest_id     TEXT NOT NULL REFERENCES quest(quest_id),
    status       TEXT NOT NULL CHECK (status IN ('ACTIVE','READY_TO_TURN_IN','COMPLETED')),
    PRIMARY KEY (character_id, quest_id)
);
CREATE TABLE character_objective_progress (
    character_id INTEGER NOT NULL,
    quest_id     TEXT NOT NULL,
    seq          INTEGER NOT NULL,
    count        INTEGER NOT NULL DEFAULT 0 CHECK (count >= 0),
    PRIMARY KEY (character_id, quest_id, seq),
    FOREIGN KEY (character_id, quest_id) REFERENCES character_quest(character_id, quest_id) ON DELETE CASCADE,
    FOREIGN KEY (quest_id, seq) REFERENCES quest_objective(quest_id, seq)
);
CREATE TABLE pending_support_choice (
    character_id INTEGER NOT NULL REFERENCES player_character(character_id) ON DELETE CASCADE,
    quest_id     TEXT NOT NULL REFERENCES quest(quest_id),
    PRIMARY KEY (character_id, quest_id)
);
CREATE TABLE recovered_item (                    -- keys, ward beacons (QuestItems ids)
    character_id INTEGER NOT NULL REFERENCES player_character(character_id) ON DELETE CASCADE,
    recover_id   TEXT NOT NULL,
    recovered_at INTEGER,
    PRIMARY KEY (character_id, recover_id)
);
CREATE TABLE exam_grade (
    character_id INTEGER NOT NULL REFERENCES player_character(character_id) ON DELETE CASCADE,
    rank_id      TEXT NOT NULL REFERENCES rank(rank_id),
    grade        INTEGER NOT NULL CHECK (grade IN (0,1,2)),   -- PASS, MERIT, DISTINCTION
    PRIMARY KEY (character_id, rank_id)
);
CREATE TABLE deed (                              -- "kind:target" -> count
    character_id INTEGER NOT NULL REFERENCES player_character(character_id) ON DELETE CASCADE,
    kind         TEXT NOT NULL,                  -- 'kill','enter_area','act_boss',...
    target       TEXT NOT NULL,
    count        INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (character_id, kind, target)
);

-- =====================================================================
--  INDEXES & VIEWS
-- =====================================================================
CREATE INDEX ix_item_kind            ON item(item_kind);
CREATE INDEX ix_affix_level          ON affix(min_item_level);
CREATE INDEX ix_waypoint_act         ON waypoint(act_number);
CREATE INDEX ix_instance_character   ON item_instance(character_id);
CREATE INDEX ix_character_quest_stat ON character_quest(character_id, status);

-- Highest rank a character holds (rank quests completed).
CREATE VIEW v_character_rank AS
SELECT pc.character_id, pc.name,
       COALESCE((SELECT r.rank_id FROM rank r
                 JOIN quest q ON q.grants_rank_id = r.rank_id
                 JOIN character_quest cq ON cq.quest_id = q.quest_id
                  AND cq.character_id = pc.character_id AND cq.status = 'COMPLETED'
                 ORDER BY r.ladder_order DESC LIMIT 1), 'initiate') AS rank_id
FROM player_character pc;

-- Character Select cards.
CREATE VIEW v_character_select AS
SELECT pc.slot_no, pc.name, cc.display_name AS class_name, pc.level,
       pc.playtime_seconds, w.display_name AS last_town
FROM player_character pc
JOIN character_class cc ON cc.class_id = pc.class_id
LEFT JOIN waypoint w ON w.waypoint_id = pc.last_town_id
ORDER BY pc.slot_no;
