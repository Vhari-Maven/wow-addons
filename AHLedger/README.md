# AH Ledger

A lightweight WoW addon that tracks your Auction House transactions (sales, purchases, and expirations) by scanning your mailbox.

## Features

- Automatically records AH transactions when you open your mailbox
- Tracks sales (with net amount after AH cut), purchases, and expired auctions
- Tracks item quantity per transaction with per-unit price calculations
- Stores itemID and itemLink for each transaction (enables future features like item icons and crafting quality display)
- Scrollable transaction list with color-coded entries
- Filter by transaction type: All / Sold / Bought / Expired
- Summary bar showing total sold, total bought, net profit, and total AH fees
- Hover tooltip with full financial breakdown (sale price, AH cut, deposit, per-unit price, buyer/seller)
- Deduplicates transactions across sessions
- Account-wide saved variables (tracks across all characters)
- Minimap addon compartment button
- Optional integration with RecipeDB for crafting cost lookups (planned)

## Commands

| Command | Action |
|---------|--------|
| `/ahl` | Toggle the ledger window |
| `/ahl clear` | Clear all transaction history (with confirmation) |

## How it works

The addon listens for the `MAIL_INBOX_UPDATE` event and scans each mail using three API calls:

- `GetInboxInvoiceInfo(i)` — transaction type, item name, financial details
- `GetInboxItem(i, 1)` — itemID and stack count (quantity)
- `GetInboxItemLink(i, 1)` — full item link (encodes crafting quality, bonus IDs, crafter GUID)

AH mail comes in three flavors:

- **`seller`** / **`seller_temp_invoice`** — You sold an item. The invoice includes the sale price, AH commission, and deposit.
- **`buyer`** — You bought an item. The invoice includes the price paid.
- **Expired auctions** — Detected by matching the mail subject line pattern "Auction expired: ...".

Transactions are deduplicated using a composite key so the same mail won't be recorded twice across reloads or sessions.

## Transaction Data Fields

Each transaction stores:

| Field | Description |
|-------|-------------|
| `key` | Composite dedup key |
| `timestamp` | When the transaction was recorded |
| `character` | Character that received the mail |
| `type` | `sold`, `bought`, or `expired` |
| `item` | Item name |
| `itemID` | Numeric item ID |
| `itemLink` | Full item hyperlink string |
| `quantity` | Stack size / number of items |
| `amount` | Net copper amount (after AH cut for sales) |
| `gross` | Sale price before fees (sold only) |
| `deposit` | Listing deposit (sold only) |
| `consignment` | AH commission fee (sold only) |
| `buyer` / `seller` | Other party name (when available) |

## Install

Copy the `AHLedger` folder into your WoW AddOns directory:

```
Interface/AddOns/AHLedger/
```

## Files

- `AHLedger.toc` — Addon metadata, saved variables declaration, optional dependency on RecipeDB
- `Core.lua` — Mailbox scanning, event handling, data recording, slash commands
- `GUI.lua` — Transaction list frame, filters, summary, row tooltips

## Compatibility

- Interface: 120001 (Midnight 12.0.1)

## Saved Data

Transaction data is stored in `AHLedgerDB` (account-wide) in:

```
WTF/Account/<account>/SavedVariables/AHLedger.lua
```
