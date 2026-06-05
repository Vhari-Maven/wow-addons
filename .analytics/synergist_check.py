#!/usr/bin/env python3
"""Check if crafting Wondrous Synergist is profitable using our data."""

import sqlite3
import os

DB_PATH = os.path.join(os.path.dirname(__file__), "wow_addon_data.sqlite")
COPPER_PER_GOLD = 10000


def copper_to_gold(c):
    return c / COPPER_PER_GOLD if c else 0


def main():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row

    # --- Find the recipe ---
    recipe = conn.execute(
        "SELECT * FROM recipes WHERE recipe_name LIKE '%synerg%'"
    ).fetchone()
    if not recipe:
        print("No recipe found for Wondrous Synergist in RecipeDB.")
        conn.close()
        return

    oid = recipe["output_item_id"]
    print(f"Recipe: {recipe['recipe_name']} (itemID {oid}, recipeID {recipe['recipe_id']})")
    print(f"Output: {recipe['output_qty_min']}-{recipe['output_qty_max']}")

    # --- Sales history (match by item name since item_id can be NULL) ---
    print("\n=== Sales History ===")
    sales = conn.execute(
        """SELECT gross, amount, consignment, deposit, quantity, datetime, character
           FROM transactions
           WHERE item LIKE '%Wondrous Synergist%' AND type = 'sold'
           ORDER BY datetime"""
    ).fetchall()
    if sales:
        for s in sales:
            gross_g = copper_to_gold(s["gross"])
            net_g = copper_to_gold(s["amount"])
            cut_g = copper_to_gold(s["consignment"])
            print(f"  {s['datetime'][:10]}: sold {s['quantity']}x for {gross_g:,.0f}g "
                  f"(net {net_g:,.0f}g after {cut_g:,.0f}g AH cut) — {s['character']}")
    else:
        print("  No sales found.")

    # --- Purchase history ---
    print("\n=== Purchase History ===")
    purchases = conn.execute(
        """SELECT amount, quantity, datetime, character
           FROM transactions
           WHERE item LIKE '%Wondrous Synergist%' AND type = 'bought'
           ORDER BY datetime"""
    ).fetchall()
    if purchases:
        for p in purchases:
            total_g = copper_to_gold(p["amount"])
            print(f"  {p['datetime'][:10]}: bought {p['quantity']}x for {total_g:,.0f}g — {p['character']}")
    else:
        print("  No purchases found.")

    # --- Reagent cost breakdown ---
    # Group by slot_index and pick the cheapest option per slot
    print("\n=== Reagent Cost Breakdown ===")
    reagents = conn.execute(
        "SELECT * FROM reagents WHERE output_item_id = ? ORDER BY slot_index, reagent_item_id",
        (oid,),
    ).fetchall()

    # Group by slot
    slots = {}
    for rg in reagents:
        si = rg["slot_index"]
        slots.setdefault(si, []).append(dict(rg))

    total_cost = 0
    missing_reagents = []

    for si in sorted(slots):
        options = slots[si]
        qty = options[0]["quantity"]

        # Find cheapest option with price data
        best = None
        for opt in options:
            rid = opt["reagent_item_id"]
            name = opt["reagent_name"] or f"itemID:{rid}"

            # Try purchase price by item_id
            price_row = conn.execute(
                """SELECT amount, quantity FROM transactions
                   WHERE item_id = ? AND type = 'bought'
                   ORDER BY datetime DESC LIMIT 1""",
                (rid,),
            ).fetchone()
            if not price_row:
                # Try by name
                price_row = conn.execute(
                    """SELECT amount, quantity FROM transactions
                       WHERE item = ? AND type = 'bought'
                       ORDER BY datetime DESC LIMIT 1""",
                    (name,),
                ).fetchone()
            if not price_row:
                # Try vendor purchases
                price_row = conn.execute(
                    """SELECT amount, quantity FROM transactions
                       WHERE (item_id = ? OR item = ?) AND type = 'vendor'
                       ORDER BY datetime DESC LIMIT 1""",
                    (rid, name),
                ).fetchone()

            if price_row:
                unit_copper = price_row["amount"] / price_row["quantity"]
                unit_gold = copper_to_gold(unit_copper)
                if best is None or unit_gold < best[1]:
                    best = (name, unit_gold, "AH/vendor")

        if best:
            slot_cost = best[1] * qty
            total_cost += slot_cost
            print(f"  Slot {si}: {qty}x {best[0]} @ {best[1]:,.1f}g = {slot_cost:,.1f}g")
        else:
            names = [o["reagent_name"] or f"itemID:{o['reagent_item_id']}" for o in options]
            missing_reagents.append((si, qty, names))
            print(f"  Slot {si}: {qty}x {' / '.join(names)} — NO PRICE DATA")

    print(f"\n  Reagent cost (known): {total_cost:,.1f}g")
    if missing_reagents:
        print(f"  WARNING: {len(missing_reagents)} reagent slot(s) missing price data")

    # --- Profitability ---
    print("\n=== Profitability ===")
    if sales:
        avg_net = sum(s["amount"] for s in sales) / sum(s["quantity"] for s in sales)
        avg_net_g = copper_to_gold(avg_net)
        avg_gross = sum(s["gross"] for s in sales) / sum(s["quantity"] for s in sales)
        avg_gross_g = copper_to_gold(avg_gross)

        print(f"  Avg sale (gross): {avg_gross_g:,.0f}g")
        print(f"  Avg sale (net after AH cut): {avg_net_g:,.0f}g")
        print(f"  Known reagent cost: {total_cost:,.1f}g")
        if not missing_reagents:
            profit = avg_net_g - total_cost
            print(f"  Profit per craft: {profit:+,.0f}g {'— PROFITABLE' if profit > 0 else '— LOSS'}")
        else:
            remaining = avg_net_g - total_cost
            print(f"  Budget remaining for unknown reagents: {remaining:+,.0f}g")
            print(f"  (Profitable if missing reagents cost less than {remaining:,.0f}g total)")
    else:
        print("  No sale data to calculate profitability.")

    conn.close()


if __name__ == "__main__":
    main()
