local AHDashboard = {}

-- Format copper as a gold string
local function FormatGold(copper)
    local g = math.floor(math.abs(copper) / 10000)
    local sign = copper < 0 and "-" or ""
    return sign .. g .. "g"
end

-- Find the latest buy/vendor unit price for an item from AHLedger
local function GetLatestBuyPrice(itemID)
    if not AHLedgerDB or not AHLedgerDB.transactions then return nil end

    local bestTimestamp = 0
    local bestUnitPrice = nil

    for _, tx in ipairs(AHLedgerDB.transactions) do
        if tx.itemID == itemID and (tx.type == "bought" or tx.type == "vendor") then
            if tx.timestamp > bestTimestamp then
                bestTimestamp = tx.timestamp
                local qty = tx.quantity or 1
                bestUnitPrice = math.floor(tx.amount / qty)
            end
        end
    end

    return bestUnitPrice
end

-- Find the latest sale gross price for an item from AHLedger
-- Sold transactions don't have itemID (the AH mail has gold, not the item),
-- so we match by item name instead.
local function GetLatestSalePrice(itemID)
    if not AHLedgerDB or not AHLedgerDB.transactions then return nil end

    local itemName = C_Item.GetItemNameByID(itemID)
    if not itemName then return nil end

    local bestTimestamp = 0
    local bestGross = nil
    local bestQty = nil

    for _, tx in ipairs(AHLedgerDB.transactions) do
        if tx.type == "sold" and tx.item == itemName then
            if tx.timestamp > bestTimestamp then
                bestTimestamp = tx.timestamp
                bestGross = tx.gross or tx.amount
                bestQty = tx.quantity or 1
            end
        end
    end

    if bestGross then
        return math.floor(bestGross / bestQty)
    end
    return nil
end

-- Calculate total crafting cost for an item using RecipeDB + AHLedger prices
local function GetCraftingCost(itemID)
    if not RecipeDB or not RecipeDB.GetRecipeForItem then return nil end

    local recipe = RecipeDB:GetRecipeForItem(itemID)
    if not recipe or not recipe.reagents then return nil end

    local totalCost = 0

    for _, slot in ipairs(recipe.reagents) do
        local qty = slot.quantity or 1

        -- Find cheapest option that has a price
        local bestPrice = nil
        for _, option in ipairs(slot.options) do
            local price = GetLatestBuyPrice(option.itemID)
            if price and (not bestPrice or price < bestPrice) then
                bestPrice = price
            end
        end

        if not bestPrice then
            return nil -- missing price data for a reagent
        end

        totalCost = totalCost + (bestPrice * qty)
    end

    return totalCost
end

-- Add info lines to the tooltip
local function OnTooltipSetItem(tooltip, data)
    if tooltip ~= GameTooltip then return end
    if not data or not data.id then return end

    local itemID = data.id

    local salePrice = GetLatestSalePrice(itemID)
    local craftCost = GetCraftingCost(itemID)

    if not salePrice and not craftCost then return end

    tooltip:AddLine(" ")

    if salePrice then
        tooltip:AddDoubleLine("Last Sold:", FormatGold(salePrice), 0.5, 0.8, 1.0, 1, 1, 1)
    end

    if craftCost then
        tooltip:AddDoubleLine("Craft Cost:", FormatGold(craftCost), 0.5, 0.8, 1.0, 1, 1, 1)
    end

    if salePrice and craftCost then
        local profit = math.floor(salePrice * 0.95) - craftCost
        local r, g, b = 0.2, 1.0, 0.2
        if profit < 0 then r, g, b = 1.0, 0.2, 0.2 end
        tooltip:AddDoubleLine("Profit (after AH):", FormatGold(profit), 0.5, 0.8, 1.0, r, g, b)
    end

    tooltip:Show()
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)
