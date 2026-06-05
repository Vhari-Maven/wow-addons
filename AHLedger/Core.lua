AHLedger = {}

-- Format copper into "Xg Xs Xc" string
function AHLedger:FormatMoney(copper)
    local gold = math.floor(math.abs(copper) / 10000)
    local silver = math.floor((math.abs(copper) % 10000) / 100)
    local cop = math.abs(copper) % 100
    local sign = copper < 0 and "-" or ""

    if gold > 0 then
        return string.format("%s%dg %ds %dc", sign, gold, silver, cop)
    elseif silver > 0 then
        return string.format("%s%ds %dc", sign, silver, cop)
    else
        return string.format("%s%dc", sign, cop)
    end
end

-- Format copper as gold only (truncate silver/copper)
function AHLedger:FormatGold(copper)
    local gold = math.floor(math.abs(copper) / 10000)
    local sign = copper < 0 and "-" or ""
    return string.format("%s%dg", sign, gold)
end

-- Track which mail IDs we've already recorded to avoid duplicates
local scannedMail = {}

local function BuildMailKey(invoiceType, itemName, bid, timestamp)
    return string.format("%s:%s:%d:%d", invoiceType or "", itemName or "", bid or 0, timestamp or 0)
end

local function ScanMailbox()
    local numItems = GetInboxNumItems()
    local newCount = 0

    for i = 1, numItems do
        local _, _, sender, subject, money, _, daysLeft, _, wasRead = GetInboxHeaderInfo(i)
        local invoiceType, itemName, playerName, bid, buyout, deposit, consignment = GetInboxInvoiceInfo(i)

        -- Get item details from the mail attachment
        local _, itemID, _, itemCount = GetInboxItem(i, 1)
        local itemLink = GetInboxItemLink(i, 1)
        local quantity = itemCount or 1

        if invoiceType then
            -- Build a key to deduplicate
            -- Use daysLeft as a rough proxy since we don't have a unique mail ID
            local key = BuildMailKey(invoiceType, itemName, bid, math.floor(daysLeft * 1000))

            if not scannedMail[key] and not AHLedger:HasTransaction(key) then
                local tx = {
                    key = key,
                    timestamp = time(),
                    character = UnitName("player"),
                    item = itemName or "Unknown",
                    itemID = itemID,
                    itemLink = itemLink,
                    quantity = quantity,
                }

                if invoiceType == "seller" or invoiceType == "seller_temp_invoice" then
                    tx.type = "sold"
                    tx.amount = bid - consignment -- net after AH cut
                    tx.gross = bid
                    tx.deposit = deposit
                    tx.consignment = consignment
                    tx.buyer = playerName
                elseif invoiceType == "buyer" then
                    tx.type = "bought"
                    tx.amount = bid
                    tx.seller = playerName
                end

                table.insert(AHLedgerDB.transactions, tx)
                scannedMail[key] = true
                newCount = newCount + 1
            end
        elseif sender and subject then
            -- Expired auctions come as mail with items but no invoice
            -- The subject line contains the item name for expired auctions
            local expiredItem = subject:match("Auction expired: (.+)")
            if expiredItem then
                local key = BuildMailKey("expired", expiredItem, 0, math.floor(daysLeft * 1000))

                if not scannedMail[key] and not AHLedger:HasTransaction(key) then
                    local tx = {
                        key = key,
                        type = "expired",
                        timestamp = time(),
                        character = UnitName("player"),
                        item = expiredItem,
                        itemID = itemID,
                        itemLink = itemLink,
                        amount = 0,
                        quantity = quantity,
                    }

                    table.insert(AHLedgerDB.transactions, tx)
                    scannedMail[key] = true
                    newCount = newCount + 1
                end
            end
        end
    end

    if newCount > 0 then
        print(string.format("|cFF00FF00AH Ledger:|r Recorded %d new transaction(s).", newCount))
        if AHLedger.GUI and AHLedger.GUI:IsShown() then
            AHLedger:RefreshGUI()
        end
    end
end

-- Check if we already have a transaction with this key in saved data
function AHLedger:HasTransaction(key)
    for _, tx in ipairs(AHLedgerDB.transactions) do
        if tx.key == key then
            return true
        end
    end
    return false
end

-- Rebuild the scannedMail cache from saved data on load
local function RebuildCache()
    for _, tx in ipairs(AHLedgerDB.transactions) do
        if tx.key then
            scannedMail[tx.key] = true
        end
    end
end

-- Vendor purchase tracking
local merchantOpen = false
local merchantCache = {} -- pre-cached item info keyed by merchant index

local function CacheMerchantItems()
    merchantCache = {}
    local numItems = GetMerchantNumItems()
    for i = 1, (numItems or 0) do
        local info = C_MerchantFrame.GetItemInfo(i)
        if info and info.name then
            merchantCache[i] = {
                name = info.name,
                price = info.price,
                stackCount = info.stackCount or 1,
                itemLink = GetMerchantItemLink(i),
                itemID = GetMerchantItemID(i),
            }
        end
    end
end

local function OnMerchantShow()
    merchantOpen = true
    CacheMerchantItems()
end

local function OnMerchantClosed()
    merchantOpen = false
    merchantCache = {}
end

local function OnBuyMerchantItem(index, quantity)
    if not merchantOpen then return end

    local cached = merchantCache[index]
    if not cached then return end

    quantity = quantity or 1

    local unitPrice = cached.price
    if cached.stackCount > 1 then
        unitPrice = math.floor(cached.price / cached.stackCount)
    end
    local totalCost = unitPrice * quantity

    local key = string.format("vendor:%s:%d:%d:%d", cached.name, totalCost, quantity, time())

    if not scannedMail[key] and not AHLedger:HasTransaction(key) then
        local tx = {
            key = key,
            type = "vendor",
            timestamp = time(),
            character = UnitName("player"),
            item = cached.name,
            itemID = cached.itemID,
            itemLink = cached.itemLink,
            quantity = quantity,
            amount = totalCost,
            seller = "Vendor",
        }

        table.insert(AHLedgerDB.transactions, tx)
        scannedMail[key] = true
        print(string.format("|cFF00FF00AH Ledger:|r Vendor purchase: %s x%d for %s",
            cached.name, quantity, AHLedger:FormatMoney(totalCost)))

        if AHLedger.GUI and AHLedger.GUI:IsShown() then
            AHLedger:RefreshGUI()
        end
    end
end

-- Event handling
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("MAIL_INBOX_UPDATE")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "AHLedger" then
            if not AHLedgerDB then
                AHLedgerDB = { transactions = {} }
            end
            if not AHLedgerDB.transactions then
                AHLedgerDB.transactions = {}
            end
            RebuildCache()
            hooksecurefunc("BuyMerchantItem", OnBuyMerchantItem)
            self:UnregisterEvent("ADDON_LOADED")
        end

    elseif event == "MAIL_INBOX_UPDATE" then
        ScanMailbox()
    elseif event == "MERCHANT_SHOW" then
        OnMerchantShow()
    elseif event == "MERCHANT_CLOSED" then
        OnMerchantClosed()
    end
end)

-- Slash commands
SLASH_AHLEDGER1 = "/ahl"
SlashCmdList["AHLEDGER"] = function(msg)
    msg = strtrim(msg):lower()
    if msg == "clear" then
        StaticPopup_Show("AHLEDGER_CONFIRM_CLEAR")
    else
        AHLedger:ToggleGUI()
    end
end

-- Clear confirmation dialog
StaticPopupDialogs["AHLEDGER_CONFIRM_CLEAR"] = {
    text = "Are you sure you want to clear all AH Ledger transaction data?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        AHLedgerDB.transactions = {}
        scannedMail = {}
        if AHLedger.GUI and AHLedger.GUI:IsShown() then
            AHLedger:RefreshGUI()
        end
        print("|cFF00FF00AH Ledger:|r Transaction history cleared.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Addon compartment
function AHLedger_OnAddonCompartmentClick()
    AHLedger:ToggleGUI()
end