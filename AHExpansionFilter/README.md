# AH Expansion Filter

A minimal WoW addon that defaults the Auction House "Current Expansion Only" filter to checked.

## What it does

Every time you open the Auction House Browse tab, the "Current Expansion Only" checkbox is enabled by default. You can still uncheck it manually if you need to search older expansion items.

## How it works

The addon modifies the `AUCTION_HOUSE_DEFAULT_FILTERS` table when `Blizzard_AuctionHouseUI` loads, setting `CurrentExpansionOnly` to `true`. This is a single-line change that affects the default state of the filter — no hooks, no polling, no overhead.

## Install

Copy the `AHExpansionFilter` folder into your WoW AddOns directory:

```
Interface/AddOns/AHExpansionFilter/
```

## Files

- `AHExpansionFilter.toc` - Addon metadata
- `AHExpansionFilter.lua` - 9 lines of Lua

## Compatibility

- Interface: 120001 (Midnight 12.0.1)
