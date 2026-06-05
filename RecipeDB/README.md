# RecipeDB

A WoW addon that scans your professions and builds a recipe-to-reagent database. Designed as a data source for other addons (like AH Ledger) to look up crafting costs.

## How it works

Every time you open a profession window, RecipeDB automatically scans all recipes using `C_TradeSkillUI.GetAllRecipeIDs()` and `C_TradeSkillUI.GetRecipeSchematic()`. It builds a reverse lookup table mapping output itemID to recipe details and reagent requirements, then persists it in saved variables.

The database grows incrementally — each profession you open adds its recipes. Previously scanned recipes are skipped for performance.

## Commands

| Command | Action |
|---------|--------|
| `/rdb` | Show help |
| `/rdb scan` | Force rescan of the currently open profession |
| `/rdb stats` | Show how many recipes are in the database |
| `/rdb clear` | Clear all saved recipe data |

## Public API

Other addons can use these functions:

```lua
-- Get recipe and reagent info for a crafted item
-- Returns table with recipeID, recipeName, outputQuantityMin/Max, reagents
-- Returns nil if item is not in the database
local recipe = RecipeDB:GetRecipeForItem(itemID)

-- Quick check if an item has a known recipe
local craftable = RecipeDB:IsCraftable(itemID)
```

### Recipe data structure

```lua
{
    recipeID = 12345,           -- spell ID of the recipe
    recipeName = "Recipe Name",
    outputQuantityMin = 1,
    outputQuantityMax = 1,
    reagents = {                -- array of reagent slots
        {
            quantity = 5,       -- how many needed
            options = {         -- acceptable items (quality tiers)
                { itemID = 111, itemName = "Reagent Rank 1" },
                { itemID = 222, itemName = "Reagent Rank 2" },
                { itemID = 333, itemName = "Reagent Rank 3" },
            },
        },
    },
}
```

## Limitations

- Only scans recipes for professions you open in-game — it cannot discover recipes you haven't viewed
- `GetAllRecipeIDs()` returns both learned and unlearned recipes, so the database may include recipes your character doesn't know
- Reagent names may be nil on first scan if the item cache hasn't loaded them yet; they are backfilled on next addon load

## Install

Copy the `RecipeDB` folder into your WoW AddOns directory:

```
Interface/AddOns/RecipeDB/
```

## Files

- `RecipeDB.toc` — Addon metadata and saved variables declaration
- `Core.lua` — Profession scanning, recipe storage, public API, slash commands

## Compatibility

- Interface: 120001 (Midnight 12.0.1)

## Saved Data

Recipe data is stored in `RecipeDBData` (account-wide) in:

```
WTF/Account/<account>/SavedVariables/RecipeDB.lua
```
