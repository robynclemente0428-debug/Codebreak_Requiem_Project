"""Writes database/schema_sqlserver.sql, a SQL Server (T-SQL) copy of database/schema.sql.

Run from the project folder:   python database/export_sqlserver.py
Then load it (creates or refreshes the CodeBreakRequiem database on this PC's SQL Server):
    sqlcmd -S localhost -E -b -i database/schema_sqlserver.sql

schema.sql (SQLite) stays the source of truth; rerun this after changing it.

What changes on the way to SQL Server:
  - INTEGER -> INT, REAL -> FLOAT, TEXT -> NVARCHAR(100), or NVARCHAR(MAX) for long text and JSON
  - AUTOINCREMENT -> IDENTITY(1,1)
  - foreign keys are added after all tables exist (SQL Server needs the parent table first)
  - SQL Server refuses two cascade paths to the same table, so where SQLite deletes along two
    paths, one of them becomes NO ACTION (listed in the header of the generated file)
  - a UNIQUE column that may be empty becomes a filtered unique index (SQL Server would
    otherwise allow only one empty value)
"""
import pathlib
import re
import sqlite3

HERE = pathlib.Path(__file__).parent
DB_NAME = "CodeBreakRequiem"
LONG_TEXT = {"description", "source", "greeting", "note", "route_needs_text"}


def q(name):
    return f"[{name}]"


def sql_type(table, col, ctype, is_identity):
    ctype = (ctype or "").upper()
    if is_identity:
        return "INT IDENTITY(1,1)"
    if ctype == "INTEGER":
        return "INT"
    if ctype == "REAL":
        return "FLOAT"
    if col.endswith("_json") or col in LONG_TEXT:
        return "NVARCHAR(MAX)"
    return "NVARCHAR(100)"          # short enough for 3-column keys (SQL Server's 900-byte limit)


def checks_of(create_sql):
    """Every CHECK (...) in a CREATE TABLE statement, translated to T-SQL."""
    out, i = [], 0
    text = re.sub(r"--[^\n]*", "", create_sql)
    while True:
        m = re.search(r"\bCHECK\s*\(", text[i:])
        if not m:
            return out
        start = i + m.end() - 1
        depth, j = 0, start
        while True:
            depth += text[j] == "("
            depth -= text[j] == ")"
            if depth == 0:
                break
            j += 1
        expr = " ".join(text[start + 1:j].split())
        expr = re.sub(r"\btrim\((\w+)\)", r"LTRIM(RTRIM(\1))", expr)
        expr = re.sub(r"\blength\(", "LEN(", expr)
        out.append(expr)
        i = j + 1


class CascadeGraph:
    """Tracks cascading delete paths so no table is reachable two ways (SQL Server error 1785)."""

    def __init__(self):
        self.edges = {}

    def _reach(self, start, forward=True):
        seen, stack = {start}, [start]
        while stack:
            n = stack.pop()
            nxt = self.edges.get(n, set()) if forward else \
                {p for p, cs in self.edges.items() if n in cs}
            for m in nxt:
                if m not in seen:
                    seen.add(m)
                    stack.append(m)
        return seen

    def try_add(self, parent, child):
        if parent == child:
            return False
        ups, downs = self._reach(parent, forward=False), self._reach(child)
        if child in ups:
            return False
        for a in ups:
            if self._reach(a) & downs:
                return False
        self.edges.setdefault(parent, set()).add(child)
        return True


def main():
    src = (HERE / "schema.sql").read_text(encoding="utf-8")
    db = sqlite3.connect(":memory:")
    db.executescript(src)
    tables = [(n, s) for n, s in db.execute(
        "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY rowid")]
    names = [n for n, _ in tables]

    create, indexes, fks, downgraded = [], [], [], []
    graph = CascadeGraph()
    for name, create_sql in tables:
        cols = db.execute(f"PRAGMA table_info('{name}')").fetchall()
        pk = [c[1] for c in sorted(cols, key=lambda c: c[5]) if c[5]]
        identity = "AUTOINCREMENT" in create_sql.upper() and len(pk) == 1
        nullable = {c[1] for c in cols if not c[3] and not c[5]}
        lines = []
        for _, col, ctype, notnull, default, is_pk in cols:
            line = f"    {q(col):<30} {sql_type(name, col, ctype, identity and is_pk)}"
            line += " NOT NULL" if notnull or is_pk else " NULL"
            if default is not None:
                line += f" DEFAULT ({default})"
            lines.append(line)
        lines.append(f"    CONSTRAINT {q('PK_' + name)} PRIMARY KEY ({', '.join(map(q, pk))})")
        for idx in db.execute(f"PRAGMA index_list('{name}')").fetchall():
            _, iname, unique, origin, _ = idx
            icols = [r[2] for r in db.execute(f"PRAGMA index_info('{iname}')")]
            if origin == "u":
                if len(icols) == 1 and icols[0] in nullable:
                    indexes.append(f"CREATE UNIQUE INDEX {q('UX_' + name + '_' + icols[0])} "
                                   f"ON {q(name)} ({q(icols[0])}) WHERE {q(icols[0])} IS NOT NULL;")
                else:
                    lines.append(f"    CONSTRAINT {q('UQ_' + name + '_' + '_'.join(icols))} "
                                 f"UNIQUE ({', '.join(map(q, icols))})")
            elif origin == "c":
                kind = "UNIQUE INDEX" if unique else "INDEX"
                indexes.append(f"CREATE {kind} {q(iname)} ON {q(name)} ({', '.join(map(q, icols))});")
        for n, expr in enumerate(checks_of(create_sql), 1):
            lines.append(f"    CONSTRAINT {q(f'CK_{name}_{n}')} CHECK ({expr})")
        create.append(f"CREATE TABLE {q(name)} (\n" + ",\n".join(lines) + "\n);")

        groups = {}
        for fid, seq, parent, frm, to, _upd, on_delete, _ in db.execute(
                f"PRAGMA foreign_key_list('{name}')").fetchall():
            groups.setdefault(fid, {"parent": parent, "from": [], "to": [], "del": on_delete})
            groups[fid]["from"].append(frm)
            groups[fid]["to"].append(to)
        for n, fid in enumerate(sorted(groups, reverse=True), 1):    # declaration order
            g = groups[fid]
            if not g["to"][0]:
                g["to"] = [c[1] for c in sorted(db.execute(
                    f"PRAGMA table_info('{g['parent']}')").fetchall(), key=lambda c: c[5]) if c[5]]
            action = g["del"]
            if action in ("CASCADE", "SET NULL") and not graph.try_add(g["parent"], name):
                downgraded.append(f"{name}.{','.join(g['from'])} -> {g['parent']} ({action})")
                action = "NO ACTION"
            fks.append(f"ALTER TABLE {q(name)} ADD CONSTRAINT {q(f'FK_{name}_{n}')} "
                       f"FOREIGN KEY ({', '.join(map(q, g['from']))}) REFERENCES {q(g['parent'])} "
                       f"({', '.join(map(q, g['to']))}) ON DELETE {action};")

    inserts = re.findall(r"^INSERT INTO .*?;", src, flags=re.S | re.M)

    out = [
        "-- =====================================================================",
        "--  CodeBreak: Requiem  -  SQL Server version of database/schema.sql",
        "--  GENERATED by database/export_sqlserver.py. Edit schema.sql, then rerun it.",
        "--  Load:  sqlcmd -S localhost -E -b -i database/schema_sqlserver.sql",
        "--  Rerunning drops and recreates this schema's tables (data in them is lost).",
        "--",
        "--  Cascading deletes changed to NO ACTION (SQL Server allows one cascade path per table):",
        *[f"--    {d}" for d in downgraded],
        "-- =====================================================================",
        "",
        "SET ANSI_NULLS ON;",
        "SET QUOTED_IDENTIFIER ON;          -- needed for the filtered unique indexes",
        "GO",
        f"IF DB_ID(N'{DB_NAME}') IS NULL CREATE DATABASE {q(DB_NAME)};",
        "GO",
        f"USE {q(DB_NAME)};",
        "GO",
        "",
        "-- ---------- clear an earlier load ----------",
        "DROP VIEW IF EXISTS [v_character_rank];",
        "DROP VIEW IF EXISTS [v_character_select];",
        "DECLARE @drop NVARCHAR(MAX) = N'';",
        "SELECT @drop += N'ALTER TABLE ' + QUOTENAME(OBJECT_NAME(parent_object_id)) + N' DROP CONSTRAINT ' + QUOTENAME(name) + N';'",
        "FROM sys.foreign_keys WHERE OBJECT_NAME(parent_object_id) IN (" +
        ", ".join(f"N'{n}'" for n in names) + ");",
        "EXEC sp_executesql @drop;",
        *[f"DROP TABLE IF EXISTS {q(n)};" for n in names],
        "GO",
        "",
        "-- ---------- tables ----------",
        *create,
        "",
        "-- ---------- lookup rows ----------",
        *inserts,
        "",
        "-- ---------- foreign keys ----------",
        *fks,
        "",
        "-- ---------- indexes ----------",
        *indexes,
        "GO",
        "",
        "-- ---------- views ----------",
        "CREATE VIEW [v_character_rank] AS",
        "SELECT pc.[character_id], pc.[name],",
        "       COALESCE((SELECT TOP 1 r.[rank_id] FROM [rank] r",
        "                 JOIN [quest] qu ON qu.[grants_rank_id] = r.[rank_id]",
        "                 JOIN [character_quest] cq ON cq.[quest_id] = qu.[quest_id]",
        "                  AND cq.[character_id] = pc.[character_id] AND cq.[status] = 'COMPLETED'",
        "                 ORDER BY r.[ladder_order] DESC), 'initiate') AS [rank_id]",
        "FROM [player_character] pc;",
        "GO",
        "CREATE VIEW [v_character_select] AS",
        "SELECT pc.[slot_no], pc.[name], cc.[display_name] AS [class_name], pc.[level],",
        "       pc.[playtime_seconds], w.[display_name] AS [last_town]",
        "FROM [player_character] pc",
        "JOIN [character_class] cc ON cc.[class_id] = pc.[class_id]",
        "LEFT JOIN [waypoint] w ON w.[waypoint_id] = pc.[last_town_id];",
        "GO",
        "",
    ]
    (HERE / "schema_sqlserver.sql").write_text("\n".join(out), encoding="utf-8")
    print(f"schema_sqlserver.sql: {len(names)} tables, {len(fks)} foreign keys, "
          f"{len(downgraded)} cascades changed to NO ACTION")
    for d in downgraded:
        print("  ", d)


if __name__ == "__main__":
    main()
