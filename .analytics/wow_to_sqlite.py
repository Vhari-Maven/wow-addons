#!/usr/bin/env python3
"""Convert WoW SavedVariables (RecipeDB + AHLedger) into a SQLite database."""

import re
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ADDONS_DIR = SCRIPT_DIR.parent if SCRIPT_DIR.name == ".analytics" else SCRIPT_DIR
WTF_DIR = ADDONS_DIR.parent.parent / "WTF" / "Account" / "JIMMYDAVIS" / "SavedVariables"
DEFAULT_DB = SCRIPT_DIR / "wow_addon_data.sqlite"


# ---------------------------------------------------------------------------
# Lua parser
# ---------------------------------------------------------------------------

def parse_lua_table(text: str, root_var: str) -> dict:
    """Minimal recursive parser for WoW SavedVariables Lua tables."""
    pos = 0

    def skip_ws():
        nonlocal pos
        while pos < len(text) and text[pos] in " \t\r\n":
            pos += 1

    def expect(ch):
        nonlocal pos
        skip_ws()
        if text[pos] != ch:
            raise ValueError(f"Expected '{ch}' at pos {pos}, got '{text[pos]}'")
        pos += 1

    def parse_string():
        nonlocal pos
        skip_ws()
        quote = text[pos]
        pos += 1
        start = pos
        while text[pos] != quote:
            if text[pos] == "\\":
                pos += 1
            pos += 1
        s = text[start:pos]
        pos += 1
        return s

    def parse_number():
        nonlocal pos
        skip_ws()
        start = pos
        if text[pos] == "-":
            pos += 1
        while pos < len(text) and (text[pos].isdigit() or text[pos] == "."):
            pos += 1
        num_str = text[start:pos]
        return int(num_str) if "." not in num_str else float(num_str)

    def parse_value():
        nonlocal pos
        skip_ws()
        ch = text[pos]
        if ch == "{":
            return parse_table()
        elif ch in ('"', "'"):
            return parse_string()
        elif ch == "-" or ch.isdigit():
            return parse_number()
        elif text[pos : pos + 4] == "true":
            pos += 4
            return True
        elif text[pos : pos + 5] == "false":
            pos += 5
            return False
        elif text[pos : pos + 3] == "nil":
            pos += 3
            return None
        else:
            raise ValueError(f"Unexpected char '{ch}' at pos {pos}")

    def parse_table():
        nonlocal pos
        expect("{")
        result = {}
        array_index = 1
        while True:
            skip_ws()
            if pos >= len(text) or text[pos] == "}":
                break
            if text[pos] == "[":
                pos += 1
                key = parse_value()
                expect("]")
                expect("=")
                val = parse_value()
                result[key] = val
            elif text[pos] == "{":
                val = parse_table()
                result[array_index] = val
                array_index += 1
            else:
                start = pos
                while text[pos] not in " \t\r\n=":
                    pos += 1
                key = text[start:pos]
                expect("=")
                val = parse_value()
                result[key] = val
            skip_ws()
            if pos < len(text) and text[pos] == ",":
                pos += 1
        expect("}")
        return result

    match = re.search(rf"{re.escape(root_var)}\s*=\s*", text)
    if not match:
        raise ValueError(f"Could not find {root_var} table in Lua file")
    pos = match.end()
    return parse_table()


def table_to_list(tbl: dict) -> list:
    """Convert a Lua table with integer keys to a Python list."""
    if not tbl:
        return []
    return [tbl[k] for k in sorted(k for k in tbl if isinstance(k, int))]


# ---------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------

SCHEMA = """
CREATE TABLE IF NOT EXISTS recipes (
    output_item_id   INTEGER PRIMARY KEY,
    recipe_id        INTEGER NOT NULL,
    recipe_name      TEXT NOT NULL,
    output_qty_min   INTEGER NOT NULL DEFAULT 1,
    output_qty_max   INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS reagents (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    output_item_id   INTEGER NOT NULL REFERENCES recipes(output_item_id),
    slot_index       INTEGER NOT NULL,
    quantity          INTEGER NOT NULL,
    reagent_item_id  INTEGER NOT NULL,
    reagent_name     TEXT,
    UNIQUE(output_item_id, slot_index, reagent_item_id)
);

CREATE INDEX IF NOT EXISTS idx_reagents_output ON reagents(output_item_id);
CREATE INDEX IF NOT EXISTS idx_reagents_item   ON reagents(reagent_item_id);

CREATE TABLE IF NOT EXISTS transactions (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    key              TEXT UNIQUE NOT NULL,
    type             TEXT NOT NULL,
    item             TEXT NOT NULL,
    item_id          INTEGER,
    item_link        TEXT,
    quantity         INTEGER,
    character        TEXT,
    timestamp        INTEGER,
    datetime         TEXT,
    gross            INTEGER,
    amount           INTEGER NOT NULL,
    consignment      INTEGER,
    deposit          INTEGER,
    buyer            TEXT,
    seller           TEXT
);

CREATE INDEX IF NOT EXISTS idx_tx_type ON transactions(type);
CREATE INDEX IF NOT EXISTS idx_tx_item ON transactions(item);
CREATE INDEX IF NOT EXISTS idx_tx_character ON transactions(character);
CREATE INDEX IF NOT EXISTS idx_tx_timestamp ON transactions(timestamp);

CREATE VIEW IF NOT EXISTS sales AS
    SELECT *, round(gross / 10000.0, 2) AS gross_gold,
           round(amount / 10000.0, 2) AS net_gold,
           CASE WHEN quantity > 0 THEN round(gross * 1.0 / quantity / 10000.0, 2) END AS unit_price_gold
    FROM transactions WHERE type = 'sold';

CREATE VIEW IF NOT EXISTS purchases AS
    SELECT *, round(amount / 10000.0, 2) AS total_gold,
           CASE WHEN quantity > 0 THEN round(amount * 1.0 / quantity / 10000.0, 2) END AS unit_price_gold
    FROM transactions WHERE type = 'bought';

CREATE VIEW IF NOT EXISTS vendor_purchases AS
    SELECT *, round(amount / 10000.0, 2) AS total_gold,
           CASE WHEN quantity > 0 THEN round(amount * 1.0 / quantity / 10000.0, 2) END AS unit_price_gold
    FROM transactions WHERE type = 'vendor';

CREATE VIEW IF NOT EXISTS expired_listings AS
    SELECT * FROM transactions WHERE type = 'expired';
"""


# ---------------------------------------------------------------------------
# Importers
# ---------------------------------------------------------------------------

def import_recipes(conn: sqlite3.Connection, data: dict):
    recipes = data.get("recipes", {})
    recipe_rows = []
    reagent_rows = []

    for item_id, recipe in recipes.items():
        if not isinstance(item_id, int):
            continue
        recipe_rows.append((
            item_id,
            recipe.get("recipeID", 0),
            recipe.get("recipeName", "Unknown"),
            recipe.get("outputQuantityMin", 1),
            recipe.get("outputQuantityMax", 1),
        ))

        for slot_idx, slot in sorted(
            ((k, v) for k, v in recipe.get("reagents", {}).items() if isinstance(k, int))
        ):
            qty = slot.get("quantity", 1)
            for option in table_to_list(slot.get("options", {})):
                reagent_rows.append((
                    item_id,
                    slot_idx,
                    qty,
                    option.get("itemID", 0),
                    option.get("itemName"),
                ))

    conn.executemany(
        "INSERT OR REPLACE INTO recipes VALUES (?, ?, ?, ?, ?)",
        recipe_rows,
    )
    conn.executemany(
        "INSERT OR REPLACE INTO reagents (output_item_id, slot_index, quantity, reagent_item_id, reagent_name) VALUES (?, ?, ?, ?, ?)",
        reagent_rows,
    )
    conn.commit()
    return len(recipe_rows), len(reagent_rows)


def import_transactions(conn: sqlite3.Connection, data: dict):
    txns = data.get("transactions", {})
    rows = []

    for txn in table_to_list(txns):
        ts = txn.get("timestamp")
        dt = datetime.fromtimestamp(ts, tz=timezone.utc).isoformat() if ts else None

        rows.append((
            txn.get("key", ""),
            txn.get("type", ""),
            txn.get("item", ""),
            txn.get("itemID"),
            txn.get("itemLink"),
            txn.get("quantity"),
            txn.get("character"),
            ts,
            dt,
            txn.get("gross"),
            txn.get("amount", 0),
            txn.get("consignment"),
            txn.get("deposit"),
            txn.get("buyer"),
            txn.get("seller"),
        ))

    conn.executemany(
        """INSERT OR REPLACE INTO transactions
           (key, type, item, item_id, item_link, quantity, character,
            timestamp, datetime, gross, amount, consignment, deposit, buyer, seller)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        rows,
    )
    conn.commit()
    return len(rows)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    db_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DB

    if db_path.exists():
        db_path.unlink()

    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA journal_mode=WAL")
    conn.executescript(SCHEMA)

    # RecipeDB
    recipe_lua = WTF_DIR / "RecipeDB.lua"
    if recipe_lua.exists():
        print(f"Parsing {recipe_lua.name}...")
        data = parse_lua_table(recipe_lua.read_text(), "RecipeDBData")
        n_recipes, n_reagents = import_recipes(conn, data)
        print(f"  {n_recipes} recipes, {n_reagents} reagent options")
    else:
        print(f"Skipping RecipeDB (not found: {recipe_lua})")

    # AHLedger
    ledger_lua = WTF_DIR / "AHLedger.lua"
    if ledger_lua.exists():
        print(f"Parsing {ledger_lua.name}...")
        data = parse_lua_table(ledger_lua.read_text(), "AHLedgerDB")
        n_txns = import_transactions(conn, data)
        print(f"  {n_txns} transactions")
    else:
        print(f"Skipping AHLedger (not found: {ledger_lua})")

    conn.close()
    print(f"\nDone -> {db_path}")


if __name__ == "__main__":
    main()
