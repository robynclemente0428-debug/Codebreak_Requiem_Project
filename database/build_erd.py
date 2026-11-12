"""Builds database/erd.html, an entity-relationship diagram, from database/schema.sql.

Run from the project folder:   python database/build_erd.py
Open erd.html in any browser. Rerun after changing schema.sql.

The diagram is split into area panels. Inside a panel, parent tables sit on the left and the
tables that reference them to the right, so every line runs left to right. A table from another
area is drawn as a small dashed stub inside the panel instead of a line across the sheet, and
references to the lookup tables (enums) are shown as a "-> table" label on the column.
"""
import json
import pathlib
import sqlite3

HERE = pathlib.Path(__file__).parent

# Lookup tables: referenced from everywhere, so they get a label instead of lines.
LOOKUPS = ["stat", "mod_op", "tag", "equipment_slot", "rarity", "rank"]

# Rows of area panels, top to bottom. Each area: (title, one-line note, tables).
AREAS = [
    [
        ("Items", "Every item definition and its base type", [
            "item", "weapon_type", "equipment_type", "stim", "item_base_stat",
            "item_allowed_affix_tag", "weapon_type_tag", "equipment_type_tag"]),
        ("Gems", "Skill gems and the support gems linked to them", [
            "skill_gem", "support_gem", "skill_gem_tag", "skill_gem_modifier",
            "skill_gem_required_weapon", "support_gem_allowed_tag", "support_gem_modifier"]),
        ("Affixes", "Random item mods", ["affix", "affix_tag", "affix_exclusivity_group"]),
    ],
    [
        ("Character & gear", "One save slot and every item copy it owns", [
            "player_character", "item_instance", "skill_socket", "item_instance_affix",
            "item_instance_stim_mod", "inventory_entry", "equipped_item", "skill_socket_support"]),
        ("Character scripts", "Skill-script sets, library and routines", [
            "skill_program", "script_set_name", "script_library_entry", "script_routine"]),
    ],
    [
        ("Character progress", "Quest status, exam grades, keys and deeds", [
            "character_quest", "character_objective_progress", "pending_support_choice",
            "recovered_item", "exam_grade", "deed"]),
        ("Quests", "Quest chains, objectives and rewards", [
            "quest", "quest_objective", "quest_prerequisite", "quest_reward_item"]),
        ("World", "Acts and the waypoint map", [
            "act", "waypoint", "waypoint_link", "waypoint_threat", "waypoint_required_quest"]),
    ],
    [
        ("Enemies", "Enemy definitions, their skills and modifiers", [
            "enemy", "enemy_modifier", "enemy_skill", "enemy_skill_support", "enemy_innate_trait",
            "enemy_pool_rarity", "enemy_allowed_modifier_tag", "enemy_modifier_stat",
            "enemy_modifier_tag"]),
        ("Rank exams", "Sudo's sandbox exams", [
            "exam", "exam_wave", "exam_wave_modifier", "exam_lent_item"]),
    ],
    [
        ("Classes", "Playable classes", ["character_class", "class_trait"]),
        ("Shops & NPCs", "Vendors and dialogue", [
            "shop", "shop_item", "shop_catalog_folder", "dialogue"]),
        ("Lookups", "Enums from GDScript, referenced as → labels", LOOKUPS),
    ],
]


def read_schema():
    db = sqlite3.connect(":memory:")
    db.executescript((HERE / "schema.sql").read_text(encoding="utf-8"))
    names = [r[0] for r in db.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]
    tables = {}
    for t in names:
        cols = db.execute(f"PRAGMA table_info('{t}')").fetchall()
        fks = db.execute(f"PRAGMA foreign_key_list('{t}')").fetchall()
        unique = set()
        pk_cols = [c[1] for c in cols if c[5]]
        if len(pk_cols) == 1:
            unique.add(pk_cols[0])
        for idx in db.execute(f"PRAGMA index_list('{t}')").fetchall():
            if idx[2]:
                icols = [r[2] for r in db.execute(f"PRAGMA index_info('{idx[1]}')")]
                if len(icols) == 1:
                    unique.add(icols[0])
        fk_cols = {f[3] for f in fks}
        columns = [{"name": c[1], "type": (c[2] or "").lower(), "pk": bool(c[5]),
                    "fk": c[1] in fk_cols, "nn": bool(c[3]) or bool(c[5])} for c in cols]
        # Shown in this order: primary keys (including PK+FK), then foreign keys, then the rest.
        # The sort is stable, so each group keeps the order from schema.sql.
        columns.sort(key=lambda c: 0 if c["pk"] else 1 if c["fk"] else 2)
        for c in columns:
            c["group"] = "pk" if c["pk"] else "fk" if c["fk"] else "other"
        tables[t] = {"columns": columns, "fks": []}
        for f in fks:
            tables[t]["fks"].append({"from": f[3], "table": f[2], "to": f[4], "one": f[3] in unique})
    for t in tables.values():        # FKs that name only the table point at its primary key
        for fk in t["fks"]:
            if not fk["to"]:
                fk["to"] = next(c["name"] for c in tables[fk["table"]]["columns"] if c["pk"])
    return tables


def home_of(areas):
    home = {}
    for row in areas:
        for title, _, names in row:
            for n in names:
                home[n] = title
    return home


def layout_area(names, tables):
    """Layers left to right: parents first. External parents become stubs. Returns
    a list of layers, each a list of {"name", "stub"}."""
    inside = set(names)
    parents, children = {n: set() for n in names}, {n: set() for n in names}
    stubs = {}                                       # stub table -> referenced columns
    for n in names:
        for fk in tables[n]["fks"]:
            p = fk["table"]
            if p in LOOKUPS or p == n:
                continue
            if p not in inside:
                stubs.setdefault(p, set()).add(fk["to"])
                p = "stub:" + p
            parents[n].add(p)
            children.setdefault(p, set()).add(n)

    layer = {}

    def depth(n, seen=()):
        if n in layer:
            return layer[n]
        ps = [p for p in parents.get(n, ()) if not p.startswith("stub:") and p not in seen]
        layer[n] = 0 if not ps else 1 + max(depth(p, seen + (n,)) for p in ps)
        return layer[n]

    for n in names:
        depth(n)
    for s in stubs:                                  # a stub sits just left of its first child
        layer["stub:" + s] = min(layer[c] for c in children["stub:" + s]) - 1
    low = min(layer.values())
    layers = [[] for _ in range(max(layer.values()) - low + 1)]
    order = [n for n in names] + ["stub:" + s for s in stubs]
    for n in order:
        layers[layer[n] - low].append(n)

    # Reduce crossings: sort each layer by the average position of its neighbours.
    def pos_map():
        return {n: i for L in layers for i, n in enumerate(L)}
    for _ in range(6):
        pm = pos_map()
        for L in layers[1:]:
            L.sort(key=lambda n: sum(pm[p] for p in parents.get(n, ())) / len(parents[n])
                   if parents.get(n) else pm[n])
            pm = pos_map()
        for L in reversed(layers[:-1]):
            L.sort(key=lambda n: sum(pm[c] for c in children.get(n, ())) / len(children[n])
                   if children.get(n) else pm[n])
            pm = pos_map()

    return [[{"name": n.removeprefix("stub:"), "stub": n.startswith("stub:"),
              "cols": sorted(stubs.get(n.removeprefix("stub:"), []))} for n in L] for L in layers]


def main():
    tables = read_schema()
    home = home_of(AREAS)
    missing = sorted(set(tables) - set(home))
    unknown = sorted(set(home) - set(tables))
    if missing or unknown:
        raise SystemExit(f"AREAS out of date. Not placed: {missing}  Not in schema: {unknown}")
    rows = []
    for row in AREAS:
        rows.append([{"title": title, "note": note, "layers": layout_area(names, tables)}
                     for title, note, names in row])
    data = {"rows": rows, "tables": tables, "home": home, "lookups": LOOKUPS}
    template = (HERE / "erd_template.html").read_text(encoding="utf-8")
    (HERE / "erd.html").write_text(template.replace("/*DATA*/null", json.dumps(data)),
                                   encoding="utf-8")
    links = sum(len(t["fks"]) for t in tables.values())
    print(f"erd.html: {len(tables)} tables, {links} relationships, "
          f"{sum(len(r) for r in AREAS)} areas")


if __name__ == "__main__":
    main()
