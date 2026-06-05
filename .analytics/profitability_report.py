#!/usr/bin/env python3
"""Generate a crafting profitability report from WoW addon data.

Usage:
    python3 profitability_report.py              # rebuild DB + generate report
    python3 profitability_report.py --no-rebuild  # report only (skip DB rebuild)
"""

import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DB_PATH = SCRIPT_DIR / "wow_addon_data.sqlite"
REPORT_PATH = SCRIPT_DIR / "profitability_report.md"
AH_CUT = 0.05


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def gold(copper: int | float) -> str:
    """Format copper as a gold string with commas."""
    g = copper / 10000
    if abs(g) >= 1:
        return f"{g:,.0f}g"
    return f"{g:,.1f}g"


def signed_gold(copper: int | float) -> str:
    g = copper / 10000
    return f"{g:>+,.0f}g"


def get_unit_price(c, item_name, item_id):
    """Latest unit price from bought/vendor transactions."""
    row = c.execute("""
        SELECT amount, quantity, type FROM transactions
        WHERE (item_id = ? OR item = ?)
        AND type IN ('bought', 'vendor')
        ORDER BY timestamp DESC LIMIT 1
    """, (item_id, item_name)).fetchone()
    if row:
        qty = row[1] if row[1] and row[1] > 0 else 1
        return row[0] / qty, row[2]
    return None, None


def get_sale_price(c, item_name):
    """Latest gross sale price."""
    row = c.execute("""
        SELECT gross FROM transactions
        WHERE item = ? AND type = 'sold'
        ORDER BY timestamp DESC LIMIT 1
    """, (item_name,)).fetchone()
    return row[0] if row else None


# ---------------------------------------------------------------------------
# Report sections
# ---------------------------------------------------------------------------

def section_overview(c) -> str:
    lines = ["## Overview\n"]

    row = c.execute("SELECT count(*) FROM recipes").fetchone()
    lines.append(f"- **{row[0]}** recipes in database")

    row = c.execute("SELECT count(*) FROM transactions").fetchone()
    lines.append(f"- **{row[0]}** transactions tracked")

    lines.append("")
    lines.append("| Type | Count | Total Gold |")
    lines.append("|------|------:|-----------:|")
    for row in c.execute("""
        SELECT type, count(*), sum(amount)
        FROM transactions GROUP BY type ORDER BY type
    """):
        lines.append(f"| {row[0]} | {row[1]} | {gold(row[2])} |")

    lines.append("")
    lines.append("### P&L by Character\n")
    lines.append("| Character | Earned | Spent (AH) | Spent (Vendor) | Net |")
    lines.append("|-----------|-------:|-----------:|---------------:|----:|")
    for row in c.execute("""
        SELECT character,
               sum(CASE WHEN type='sold' THEN amount ELSE 0 END),
               sum(CASE WHEN type='bought' THEN amount ELSE 0 END),
               sum(CASE WHEN type='vendor' THEN amount ELSE 0 END)
        FROM transactions GROUP BY character ORDER BY character
    """):
        earned, spent_ah, spent_v = row[1], row[2], row[3]
        net = earned - spent_ah - spent_v
        lines.append(f"| {row[0]} | {gold(earned)} | {gold(spent_ah)} | {gold(spent_v)} | {signed_gold(net)} |")

    return "\n".join(lines)


def get_missive_price(c, missive_name):
    """Latest price for a missive from transaction history."""
    row = c.execute("""
        SELECT amount, quantity FROM transactions
        WHERE item = ? AND type = 'bought'
        ORDER BY timestamp DESC LIMIT 1
    """, (missive_name,)).fetchone()
    if row:
        qty = row[1] if row[1] and row[1] > 0 else 1
        return row[0] / qty
    return None


# Missive assignments per tool
MISSIVE_ASSIGNMENTS = {
    "Thalassian Blacksmith's Hammer":    "Thalassian Missive of Resourcefulness",
    "Thalassian Blacksmith's Toolbox":   "Thalassian Missive of Resourcefulness",
    "Thalassian Leatherworker's Knife":  "Thalassian Missive of Resourcefulness",
    "Thalassian Leatherworker's Toolset":"Thalassian Missive of Resourcefulness",
    "Thalassian Needle Set":             "Thalassian Missive of Resourcefulness",
    "Thalassian Pickaxe":                "Thalassian Missive of Finesse",
    "Thalassian Sickle":                 "Thalassian Missive of Finesse",
    "Thalassian Skinning Knife":         "Thalassian Missive of Finesse",
}


PROFESSION_TOOLS = [
    "Thalassian Blacksmith's Hammer",
    "Thalassian Blacksmith's Toolbox",
    "Thalassian Leatherworker's Knife",
    "Thalassian Leatherworker's Toolset",
    "Thalassian Needle Set",
    "Thalassian Pickaxe",
    "Thalassian Sickle",
    "Thalassian Skinning Knife",
]


def section_profession_gear(c) -> str:
    lines = ["## Blacksmithing Profession Gear Profitability\n"]
    lines.append("*Assumes Missive of Finesse on gathering tools, Missive of Resourcefulness on crafting tools.*\n")

    # Cache missive prices
    missive_prices = {}
    for missive in set(MISSIVE_ASSIGNMENTS.values()):
        missive_prices[missive] = get_missive_price(c, missive)

    placeholders = ",".join("?" * len(PROFESSION_TOOLS))
    recipes = c.execute(f"""
        SELECT output_item_id, recipe_name FROM recipes
        WHERE recipe_name IN ({placeholders})
        ORDER BY recipe_name
    """, PROFESSION_TOOLS).fetchall()

    # Summary table
    lines.append("| Recipe | Reagent Cost | Sale Price | Profit (after 5% AH) | Status |")
    lines.append("|--------|------------:|-----------:|---------------------:|--------|")

    details = []

    for item_id, name in recipes:
        reagents = c.execute("""
            SELECT slot_index, quantity, reagent_item_id, reagent_name
            FROM reagents WHERE output_item_id = ?
            ORDER BY slot_index, reagent_item_id
        """, (item_id,)).fetchall()

        slots = {}
        for slot_idx, qty, rid, rname in reagents:
            if slot_idx not in slots:
                slots[slot_idx] = []
            slots[slot_idx].append((qty, rid, rname))

        total_cost = 0
        missing = []
        detail_lines = []

        for slot_idx in sorted(slots):
            options = slots[slot_idx]
            qty = options[0][0]
            best_price, best_name, best_src = None, None, None

            for _, rid, rname in options:
                price, src = get_unit_price(c, rname, rid)
                if price is not None and (best_price is None or price < best_price):
                    best_price = price
                    best_name = rname or f"ID:{rid}"
                    best_src = src

            if best_price is not None:
                slot_cost = best_price * qty
                total_cost += slot_cost
                src_tag = "vendor" if best_src == "vendor" else "AH"
                detail_lines.append(
                    f"| {qty}x {best_name} | {gold(best_price)} | {gold(slot_cost)} | {src_tag} |"
                )
            else:
                rname = options[0][2] or f"ID:{options[0][1]}"
                missing.append(rname)
                detail_lines.append(f"| {qty}x {rname} | ?? | ?? | no data |")

        # Add missive cost
        missive_name = MISSIVE_ASSIGNMENTS.get(name)
        missive_cost = missive_prices.get(missive_name) if missive_name else None
        if missive_cost is not None:
            total_cost += missive_cost
            missive_short = missive_name.replace("Thalassian Missive of ", "")
            detail_lines.append(
                f"| 1x {missive_name} | {gold(missive_cost)} | {gold(missive_cost)} | AH |"
            )
        elif missive_name:
            missive_short = missive_name.replace("Thalassian Missive of ", "")
            missing.append(missive_name)
            detail_lines.append(f"| 1x {missive_name} | ?? | ?? | no data |")

        sale_price = get_sale_price(c, name)

        if sale_price and not missing:
            profit = sale_price * (1 - AH_CUT) - total_cost
            status = "profitable" if profit > 0 else "loss"
            lines.append(f"| {name} | {gold(total_cost)} | {gold(sale_price)} | {signed_gold(profit)} | {status} |")
        elif sale_price and missing:
            profit = sale_price * (1 - AH_CUT) - total_cost
            lines.append(f"| {name} | {gold(total_cost)}+ | {gold(sale_price)} | {signed_gold(profit)} max | incomplete |")
        elif not missing:
            lines.append(f"| {name} | {gold(total_cost)} | ?? | ?? | no sale data |")
        else:
            lines.append(f"| {name} | {gold(total_cost)}+ | ?? | ?? | incomplete |")

        # Build detail block
        detail_block = [f"### {name}\n"]
        detail_block.append("| Reagent | Unit Price | Slot Cost | Source |")
        detail_block.append("|---------|----------:|---------:|--------|")
        detail_block.extend(detail_lines)
        cost_str = gold(total_cost) + ("*" if missing else "")
        detail_block.append(f"| **Total reagent cost** | | **{cost_str}** | |")
        detail_block.append("")
        if sale_price:
            net = sale_price * (1 - AH_CUT)
            profit = net - total_cost
            detail_block.append(f"- Sale price: **{gold(sale_price)}**")
            detail_block.append(f"- AH cut (5%): {gold(sale_price * AH_CUT)}")
            detail_block.append(f"- Net after AH: {gold(net)}")
            incomplete = " *(reagent cost incomplete)*" if missing else ""
            detail_block.append(f"- **Profit: {signed_gold(profit)}**{incomplete}")
        else:
            detail_block.append("- *No sale history — check AH for current listing prices*")
        if missing:
            detail_block.append(f"- Missing prices: {', '.join(missing)}")
        detail_block.append("")
        details.append("\n".join(detail_block))

    lines.append("")
    lines.append("---\n")
    lines.append("### Detailed Breakdowns\n")
    lines.extend(details)

    return "\n".join(lines)


LEATHERWORKING_GEAR = [
    "Apprentice Smith's Apron",
    "Chemist's Cap",
    "Apprentice Jeweler's Apron",
    "Tinker's Handguard",
    "Hideworker's Cover",
    "Skinner's Backpack",
    "Eversong Botanist's Satchel",
    "Skinner's Cap",
]


def section_leatherworking_gear(c) -> str:
    lines = ["## Leatherworking Profession Gear Profitability\n"]

    placeholders = ",".join("?" * len(LEATHERWORKING_GEAR))
    recipes = c.execute(f"""
        SELECT output_item_id, recipe_name FROM recipes
        WHERE recipe_name IN ({placeholders})
        ORDER BY recipe_name
    """, LEATHERWORKING_GEAR).fetchall()

    # Summary table
    lines.append("| Recipe | Reagent Cost | Sale Price | Profit (after 5% AH) | Status |")
    lines.append("|--------|------------:|-----------:|---------------------:|--------|")

    details = []

    for item_id, name in recipes:
        reagents = c.execute("""
            SELECT slot_index, quantity, reagent_item_id, reagent_name
            FROM reagents WHERE output_item_id = ?
            ORDER BY slot_index, reagent_item_id
        """, (item_id,)).fetchall()

        slots = {}
        for slot_idx, qty, rid, rname in reagents:
            if slot_idx not in slots:
                slots[slot_idx] = []
            slots[slot_idx].append((qty, rid, rname))

        total_cost = 0
        missing = []
        detail_lines = []

        for slot_idx in sorted(slots):
            options = slots[slot_idx]
            qty = options[0][0]
            best_price, best_name, best_src = None, None, None

            for _, rid, rname in options:
                price, src = get_unit_price(c, rname, rid)
                if price is not None and (best_price is None or price < best_price):
                    best_price = price
                    best_name = rname or f"ID:{rid}"
                    best_src = src

            if best_price is not None:
                slot_cost = best_price * qty
                total_cost += slot_cost
                src_tag = "vendor" if best_src == "vendor" else "AH"
                detail_lines.append(
                    f"| {qty}x {best_name} | {gold(best_price)} | {gold(slot_cost)} | {src_tag} |"
                )
            else:
                rname = options[0][2] or f"ID:{options[0][1]}"
                missing.append(rname)
                detail_lines.append(f"| {qty}x {rname} | ?? | ?? | no data |")

        sale_price = get_sale_price(c, name)

        if sale_price and not missing:
            profit = sale_price * (1 - AH_CUT) - total_cost
            status = "profitable" if profit > 0 else "loss"
            lines.append(f"| {name} | {gold(total_cost)} | {gold(sale_price)} | {signed_gold(profit)} | {status} |")
        elif sale_price and missing:
            profit = sale_price * (1 - AH_CUT) - total_cost
            lines.append(f"| {name} | {gold(total_cost)}+ | {gold(sale_price)} | {signed_gold(profit)} max | incomplete |")
        elif not missing:
            lines.append(f"| {name} | {gold(total_cost)} | ?? | ?? | no sale data |")
        else:
            lines.append(f"| {name} | {gold(total_cost)}+ | ?? | ?? | incomplete |")

        # Build detail block
        detail_block = [f"### {name}\n"]
        detail_block.append("| Reagent | Unit Price | Slot Cost | Source |")
        detail_block.append("|---------|----------:|---------:|--------|")
        detail_block.extend(detail_lines)
        cost_str = gold(total_cost) + ("*" if missing else "")
        detail_block.append(f"| **Total reagent cost** | | **{cost_str}** | |")
        detail_block.append("")
        if sale_price:
            net = sale_price * (1 - AH_CUT)
            profit = net - total_cost
            detail_block.append(f"- Sale price: **{gold(sale_price)}**")
            detail_block.append(f"- AH cut (5%): {gold(sale_price * AH_CUT)}")
            detail_block.append(f"- Net after AH: {gold(net)}")
            incomplete = " *(reagent cost incomplete)*" if missing else ""
            detail_block.append(f"- **Profit: {signed_gold(profit)}**{incomplete}")
        else:
            detail_block.append("- *No sale history — check AH for current listing prices*")
        if missing:
            detail_block.append(f"- Missing prices: {', '.join(missing)}")
        detail_block.append("")
        details.append("\n".join(detail_block))

    lines.append("")
    lines.append("---\n")
    lines.append("### Detailed Breakdowns\n")
    lines.extend(details)

    return "\n".join(lines)


ALL_REPORT_RECIPES = PROFESSION_TOOLS + LEATHERWORKING_GEAR


def section_reagent_prices(c) -> str:
    lines = ["## Reagent Price Reference\n"]
    lines.append("Latest known prices for reagents used in reported recipes.\n")
    lines.append("| Reagent | Unit Price | Source | Last Purchased |")
    lines.append("|---------|----------:|--------|----------------|")

    # Collect unique reagent names across all reported recipes
    seen_names = {}
    placeholders = ",".join("?" * len(ALL_REPORT_RECIPES))
    for row in c.execute(f"""
        SELECT DISTINCT rg.reagent_item_id, rg.reagent_name
        FROM reagents rg
        JOIN recipes r ON rg.output_item_id = r.output_item_id
        WHERE r.recipe_name IN ({placeholders})
        ORDER BY rg.reagent_name
    """, ALL_REPORT_RECIPES):
        rid, rname = row
        display = rname or f"ID:{rid}"
        if display not in seen_names:
            seen_names[display] = (rid, rname)

    for display in sorted(seen_names):
        rid, rname = seen_names[display]
        price, src = get_unit_price(c, rname, rid)

        if price is not None:
            tx = c.execute("""
                SELECT timestamp FROM transactions
                WHERE (item_id = ? OR item = ?)
                AND type IN ('bought', 'vendor')
                ORDER BY timestamp DESC LIMIT 1
            """, (rid, rname)).fetchone()
            dt = datetime.fromtimestamp(tx[0], tz=timezone.utc).strftime("%m/%d %H:%M") if tx else "—"
            src_label = "vendor" if src == "vendor" else "AH"
            lines.append(f"| {display} | {gold(price)} | {src_label} | {dt} |")
        else:
            lines.append(f"| {display} | **??** | — | — |")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    rebuild = "--no-rebuild" not in sys.argv

    if rebuild:
        print("Rebuilding database...")
        subprocess.run(
            [sys.executable, str(SCRIPT_DIR / "wow_to_sqlite.py")],
            check=True,
        )

    if not DB_PATH.exists():
        print(f"Error: database not found at {DB_PATH}", file=sys.stderr)
        print("Run wow_to_sqlite.py first.", file=sys.stderr)
        sys.exit(1)

    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()

    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    report = [f"# WoW Crafting Profitability Report\n\n*Generated: {now}*\n"]
    report.append(section_overview(c))
    report.append("")
    report.append(section_profession_gear(c))
    report.append("")
    report.append(section_leatherworking_gear(c))
    report.append("")
    report.append(section_reagent_prices(c))
    report.append("")

    conn.close()

    REPORT_PATH.write_text("\n".join(report))
    print(f"Report written to {REPORT_PATH}")


if __name__ == "__main__":
    main()
