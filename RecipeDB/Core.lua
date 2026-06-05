RecipeDB = {}

local MIDNIGHT_EXPANSION_ID = 11
local scanRetried = false

-- Public API: look up reagents by output item ID
-- Returns: { recipeID, recipeName, reagents = { { itemID, itemName, quantity }, ... } } or nil
function RecipeDB:GetRecipeForItem(itemID)
    if not RecipeDBData or not RecipeDBData.recipes then return nil end
    return RecipeDBData.recipes[itemID]
end

-- Public API: check if an item is craftable
function RecipeDB:IsCraftable(itemID)
    return self:GetRecipeForItem(itemID) ~= nil
end

-- Check if an item belongs to the Midnight expansion
-- Returns true if Midnight, false if confirmed non-Midnight, nil if item not cached yet
local function IsMidnightItem(itemID)
    local _, _, _, _, _, _, _, _, _, _, _, _, _, _, expansionID = C_Item.GetItemInfo(itemID)
    if expansionID == nil then return nil end -- not cached yet, unknown
    return expansionID == MIDNIGHT_EXPANSION_ID
end

-- Scan all recipes from the currently open profession
local function ScanProfessionRecipes()
    local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
    if not recipeIDs or #recipeIDs == 0 then return end

    local newCount = 0
    local pendingCount = 0

    for _, recipeSpellID in ipairs(recipeIDs) do
        local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeSpellID, false)

        if schematic and schematic.outputItemID and schematic.outputItemID > 0 then
            -- Skip if we already have this item mapped
            if not RecipeDBData.recipes[schematic.outputItemID] then
                -- Only store confirmed Midnight expansion recipes
                local isMidnight = IsMidnightItem(schematic.outputItemID)
                if isMidnight == nil then
                    -- Not cached yet — request load and retry in a second pass
                    C_Item.RequestLoadItemDataByID(schematic.outputItemID)
                    pendingCount = pendingCount + 1
                elseif isMidnight == false then
                    -- confirmed non-Midnight, skip
                else
                    local reagents = {}

                    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
                        if slot.required and slot.reagents and #slot.reagents > 0 then
                            -- Each slot can accept multiple reagent options (e.g., quality tiers)
                            -- Store all options so the consumer can match what they have
                            local options = {}
                            for _, reagent in ipairs(slot.reagents) do
                                if reagent.itemID then
                                    local reagentName = C_Item.GetItemNameByID(reagent.itemID)
                                    table.insert(options, {
                                        itemID = reagent.itemID,
                                        itemName = reagentName, -- may be nil if not cached yet
                                    })
                                end
                            end

                            if #options > 0 then
                                table.insert(reagents, {
                                    quantity = slot.quantityRequired or 1,
                                    options = options,
                                })
                            end
                        end
                    end

                    if #reagents > 0 then
                        RecipeDBData.recipes[schematic.outputItemID] = {
                            recipeID = recipeSpellID,
                            recipeName = schematic.name,
                            outputQuantityMin = schematic.quantityMin or 1,
                            outputQuantityMax = schematic.quantityMax or 1,
                            reagents = reagents,
                        }
                        newCount = newCount + 1
                    end
                end
            end
        end
    end

    if newCount > 0 then
        local total = 0
        for _ in pairs(RecipeDBData.recipes) do total = total + 1 end
        print(string.format("|cFF00FF00RecipeDB:|r Scanned %d new recipe(s). Total: %d", newCount, total))
    end

    -- If items were uncached, retry once after giving them time to load
    if pendingCount > 0 and not scanRetried then
        scanRetried = true
        C_Timer.After(2, ScanProfessionRecipes)
    end
end

-- Purge non-Midnight recipes from saved data
local function PurgeOldRecipes()
    if not RecipeDBData or not RecipeDBData.recipes then return end

    local purged = 0
    for itemID, _ in pairs(RecipeDBData.recipes) do
        -- Only purge if we're sure it's non-Midnight (nil = not cached, keep it)
        if IsMidnightItem(itemID) == false then
            RecipeDBData.recipes[itemID] = nil
            purged = purged + 1
        end
    end

    if purged > 0 then
        local remaining = 0
        for _ in pairs(RecipeDBData.recipes) do remaining = remaining + 1 end
        print(string.format("|cFF00FF00RecipeDB:|r Purged %d old recipe(s). %d Midnight recipe(s) remaining.", purged, remaining))
    end
end

-- Backfill any nil reagent names from a previous scan (items may not have been cached)
local function BackfillReagentNames()
    if not RecipeDBData or not RecipeDBData.recipes then return end

    for _, recipe in pairs(RecipeDBData.recipes) do
        for _, slot in ipairs(recipe.reagents) do
            for _, option in ipairs(slot.options) do
                if not option.itemName and option.itemID then
                    option.itemName = C_Item.GetItemNameByID(option.itemID)
                end
            end
        end
    end
end

-- Event handling
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("TRADE_SKILL_SHOW")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "RecipeDB" then
            if not RecipeDBData then
                RecipeDBData = { recipes = {} }
            end
            if not RecipeDBData.recipes then
                RecipeDBData.recipes = {}
            end
            PurgeOldRecipes()
            BackfillReagentNames()
            self:UnregisterEvent("ADDON_LOADED")
        end

    elseif event == "TRADE_SKILL_SHOW" then
        -- Delay slightly to let the profession UI populate its data
        scanRetried = false
        C_Timer.After(0.5, ScanProfessionRecipes)
    end
end)

-- Slash command to check status or force rescan
SLASH_RECIPEDB1 = "/rdb"
SlashCmdList["RECIPEDB"] = function(msg)
    msg = strtrim(msg):lower()

    if msg == "scan" then
        if C_TradeSkillUI.IsTradeSkillReady() then
            ScanProfessionRecipes()
        else
            print("|cFF00FF00RecipeDB:|r Open a profession window first.")
        end

    elseif msg == "clear" then
        RecipeDBData.recipes = {}
        print("|cFF00FF00RecipeDB:|r Database cleared.")

    elseif msg == "stats" then
        local count = 0
        if RecipeDBData and RecipeDBData.recipes then
            for _ in pairs(RecipeDBData.recipes) do count = count + 1 end
        end
        print(string.format("|cFF00FF00RecipeDB:|r %d Midnight recipe(s) in database.", count))

    else
        print("|cFF00FF00RecipeDB:|r Commands:")
        print("  /rdb scan - Force rescan of current profession")
        print("  /rdb stats - Show database size")
        print("  /rdb clear - Clear all saved recipe data")
    end
end
