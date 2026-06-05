# .analytics

Offline Python scripts that convert WoW SavedVariables into a SQLite database and generate a crafting profitability report.

## Scripts

### wow_to_sqlite.py

Parses `RecipeDB.lua` and `AHLedger.lua` from the WTF SavedVariables directory and loads them into `wow_addon_data.sqlite`.

```bash
python3 wow_to_sqlite.py              # rebuild DB (default path)
python3 wow_to_sqlite.py /path/to.db  # custom output path
```

- Recreates the DB from scratch on each run (deletes existing file)
- Reads from `WTF/Account/JIMMYDAVIS/SavedVariables/`
- Tables: `recipes`, `reagents`, `transactions`
- Views: `sales`, `purchases`, `vendor_purchases`, `expired_listings`

### profitability_report.py

Generates `profitability_report.md` with crafting cost analysis for Thalassian profession tools.

```bash
python3 profitability_report.py              # rebuild DB + generate report
python3 profitability_report.py --no-rebuild # report only (skip DB rebuild)
```

Report sections:
- **Overview** — transaction counts, totals by type, P&L by character
- **Profession Gear Profitability** — summary table + detailed reagent breakdowns for each Thalassian tool
- **Reagent Price Reference** — latest known prices for all reagents used

Assumes Missive of Finesse on gathering tools (Pickaxe, Sickle, Skinning Knife) and Missive of Resourcefulness on crafting tools (Hammer, Toolbox, LW Knife, LW Toolset, Needle Set). Missive prices are pulled from AHLedger transaction history.

## Data Flow

```
WoW client logout/reload
  -> WTF/Account/JIMMYDAVIS/SavedVariables/AHLedger.lua
  -> WTF/Account/JIMMYDAVIS/SavedVariables/RecipeDB.lua
     |
     v
wow_to_sqlite.py  ->  wow_addon_data.sqlite
     |
     v
profitability_report.py  ->  profitability_report.md
```

## Requirements

- Python 3.10+ (uses `int | float` type union syntax)
- No third-party dependencies (stdlib only: sqlite3, re, pathlib, subprocess)
