local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "Blizzard_AuctionHouseUI" then
        AUCTION_HOUSE_DEFAULT_FILTERS[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
        self:UnregisterEvent("ADDON_LOADED")
    end
end)