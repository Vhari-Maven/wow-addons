# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a World of Warcraft retail AddOns directory (`Interface/AddOns/`). It contains custom addons authored by jamesdavis alongside several third-party addons.

## Custom Addons (the code we maintain)

### AHExpansionFilter
- Single-file addon (`AHExpansionFilter.lua`, 9 lines)
- Defaults the Auction House "Current Expansion Only" filter to checked by modifying `AUCTION_HOUSE_DEFAULT_FILTERS` when `Blizzard_AuctionHouseUI` loads

### AHLedger
- Two-file addon: `Core.lua` (data/events/slash commands) and `GUI.lua` (scroll frame UI)
- Scans mailbox via `MAIL_INBOX_UPDATE` event to record AH sales, purchases, and expired auctions
- Uses three mail APIs per item: `GetInboxInvoiceInfo` (financials), `GetInboxItem` (itemID, quantity), `GetInboxItemLink` (full item link)
- Stores data in `AHLedgerDB` (account-wide SavedVariable) with composite-key deduplication
- Each transaction stores: type, item name, itemID, itemLink, quantity, amounts, fees, buyer/seller, character, timestamp
- GUI shows quantity in item column ("Item x5"), per-unit prices in tooltip for multi-item transactions
- Slash command: `/ahl` (toggle GUI), `/ahl clear` (wipe data with confirmation dialog)
- Minimap compartment button via `AddonCompartmentFunc`
- Optional dependency on RecipeDB for future crafting cost integration

### RecipeDB
- Single-file addon (`Core.lua`) providing a recipe database for other addons
- Auto-scans recipes on `TRADE_SKILL_SHOW` via `C_TradeSkillUI.GetAllRecipeIDs()` + `GetRecipeSchematic()`
- Builds a reverse lookup: output itemID -> recipe details + reagent requirements
- Incremental: grows as you open different professions, skips already-scanned recipes
- Stores reagent slots with all quality-tier options (multiple acceptable items per slot)
- Backfills nil reagent names on load from item cache
- Public API: `RecipeDB:GetRecipeForItem(itemID)`, `RecipeDB:IsCraftable(itemID)`
- Slash command: `/rdb` (help), `/rdb scan`, `/rdb stats`, `/rdb clear`
- Data persisted in `RecipeDBData` SavedVariable

### Cross-addon communication
- AHLedger declares `OptionalDeps: RecipeDB` in its TOC so RecipeDB loads first
- RecipeDB exposes a global `RecipeDB` table that AHLedger can read directly (shared Lua environment)

### .analytics (offline Python scripts)
- `wow_to_sqlite.py` — parses RecipeDB + AHLedger SavedVariables into `wow_addon_data.sqlite`
- `profitability_report.py` — generates `profitability_report.md` with crafting cost analysis for Thalassian profession tools
- Assumes Missive of Finesse on gathering tools, Missive of Resourcefulness on crafting tools
- Missive and reagent prices are pulled from AHLedger transaction history (latest purchase)
- Run `python3 profitability_report.py` to rebuild DB + generate report; add `--no-rebuild` to skip DB rebuild
- Python 3.10+, no third-party dependencies
- See `.analytics/README.md` for full details

## Third-Party Addons (do not modify)

AccWideUILayoutSelection, DejaCharacterStats, Leatrix_Plus, TomTom — these are installed from external sources.

## WoW Addon Development

- Language: **Lua 5.1** (sandboxed, no file I/O, no `loadstring` in secure contexts)
- Current interface version: **120001** (Midnight 12.0.1)
- Reference doc: `wow-addon-api.md` in this directory covers TOC format, events, frame API, saved variables, and Midnight-specific restrictions
- API reference: https://warcraft.wiki.gg/wiki/World_of_Warcraft_API

### Addon Structure Conventions
- Folder name and `.toc` filename must match exactly
- `.toc` lists files loaded top-to-bottom; `## SavedVariables` declares persisted globals
- Event-driven architecture: create frames, register events, handle in `OnEvent` script
- `ADDON_LOADED` event (with addon name check) is the initialization entry point
- Pure Lua UI construction (no XML) — use `CreateFrame()`, `CreateFontString()`, etc.

### SavedVariables Location
- Saved data lives in `WTF/Account/JIMMYDAVIS/SavedVariables/<AddonName>.lua`
- Written by the WoW client on logout/reload — edits to these files only take effect if made while WoW is closed or before `/reload`

### Testing
There is no automated test framework. Addons are tested in-game by reloading the UI (`/reload`) and verifying behavior manually.

### Midnight 12.0.0 Restrictions
Combat log events, cooldowns, auras, unit identity, and chat are restricted/opaque during encounters. New addons should not rely on combat data. See Section 6 of `wow-addon-api.md`.
