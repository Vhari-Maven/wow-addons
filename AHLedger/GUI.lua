local ROW_HEIGHT = 20
local VISIBLE_ROWS = 15
local FILTER_ALL = "all"
local FILTER_SOLD = "sold"
local FILTER_BOUGHT = "bought"
local FILTER_VENDOR = "vendor"
local FILTER_EXPIRED = "expired"

local TYPE_COLORS = {
    sold = { r = 0.2, g = 0.8, b = 0.2 },
    bought = { r = 0.9, g = 0.3, b = 0.3 },
    vendor = { r = 0.6, g = 0.5, b = 0.9 },
    expired = { r = 0.9, g = 0.8, b = 0.2 },
}

local TYPE_LABELS = {
    sold = "SOLD",
    bought = "BOUGHT",
    vendor = "VENDOR",
    expired = "EXPIRED",
}

local currentFilter = FILTER_ALL

-- Get filtered transactions (newest first)
local function GetFilteredTransactions()
    local results = {}
    local transactions = AHLedgerDB and AHLedgerDB.transactions or {}

    for i = #transactions, 1, -1 do
        local tx = transactions[i]
        if currentFilter == FILTER_ALL or tx.type == currentFilter then
            table.insert(results, tx)
        end
    end
    return results
end

-- Calculate summary totals
local function GetSummary()
    local totalSold, totalBought, totalVendor, totalFees = 0, 0, 0, 0
    local transactions = AHLedgerDB and AHLedgerDB.transactions or {}

    for _, tx in ipairs(transactions) do
        if tx.type == "sold" then
            totalSold = totalSold + tx.amount
            totalFees = totalFees + (tx.consignment or 0) + (tx.deposit or 0)
        elseif tx.type == "bought" then
            totalBought = totalBought + tx.amount
        elseif tx.type == "vendor" then
            totalVendor = totalVendor + tx.amount
        end
    end
    return totalSold, totalBought, totalVendor, totalSold - totalBought - totalVendor, totalFees
end

-- Format timestamp
local function FormatTimestamp(ts)
    return date("%m/%d %H:%M", ts)
end

-- Show tooltip with transaction details on row hover
local function ShowRowTooltip(row, tx)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(tx.item, 1, 1, 1)
    if tx.quantity and tx.quantity > 1 then
        GameTooltip:AddDoubleLine("Quantity:", tx.quantity, 0.7, 0.7, 0.7, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")

    if tx.type == "sold" then
        if tx.gross then
            GameTooltip:AddDoubleLine("Sale price:", AHLedger:FormatMoney(tx.gross), 0.7, 0.7, 0.7, 1, 1, 1)
        end
        if tx.consignment and tx.consignment > 0 then
            GameTooltip:AddDoubleLine("AH cut:", "-" .. AHLedger:FormatMoney(tx.consignment), 0.7, 0.7, 0.7, 0.9, 0.3, 0.3)
        end
        if tx.deposit and tx.deposit > 0 then
            GameTooltip:AddDoubleLine("Deposit:", AHLedger:FormatMoney(tx.deposit), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
        end
        GameTooltip:AddDoubleLine("Net received:", AHLedger:FormatMoney(tx.amount), 0.7, 0.7, 0.7, 0.2, 0.8, 0.2)
        if tx.quantity and tx.quantity > 1 then
            GameTooltip:AddDoubleLine("Per unit:", AHLedger:FormatMoney(math.floor(tx.amount / tx.quantity)), 0.7, 0.7, 0.7, 0.2, 0.8, 0.2)
        end
        if tx.buyer then
            GameTooltip:AddDoubleLine("Buyer:", tx.buyer, 0.7, 0.7, 0.7, 1, 1, 1)
        end
    elseif tx.type == "bought" then
        GameTooltip:AddDoubleLine("Price paid:", AHLedger:FormatMoney(tx.amount), 0.7, 0.7, 0.7, 0.9, 0.3, 0.3)
        if tx.quantity and tx.quantity > 1 then
            GameTooltip:AddDoubleLine("Per unit:", AHLedger:FormatMoney(math.floor(tx.amount / tx.quantity)), 0.7, 0.7, 0.7, 0.9, 0.3, 0.3)
        end
        if tx.seller then
            GameTooltip:AddDoubleLine("Seller:", tx.seller, 0.7, 0.7, 0.7, 1, 1, 1)
        end
    elseif tx.type == "vendor" then
        GameTooltip:AddDoubleLine("Vendor cost:", AHLedger:FormatMoney(tx.amount), 0.7, 0.7, 0.7, 0.6, 0.5, 0.9)
        if tx.quantity and tx.quantity > 1 then
            GameTooltip:AddDoubleLine("Per unit:", AHLedger:FormatMoney(math.floor(tx.amount / tx.quantity)), 0.7, 0.7, 0.7, 0.6, 0.5, 0.9)
        end
    elseif tx.type == "expired" then
        GameTooltip:AddLine("Auction expired unsold", 0.9, 0.8, 0.2)
    end

    if tx.character then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Character:", tx.character, 0.7, 0.7, 0.7, 0.6, 0.6, 0.6)
    end

    GameTooltip:Show()
end

-- Build the main frame
local function CreateGUI()
    local gui = CreateFrame("Frame", "AHLedgerFrame", UIParent, "BasicFrameTemplateWithInset")
    gui:SetSize(520, 440)
    gui:SetPoint("CENTER")
    gui:SetMovable(true)
    gui:SetResizable(true)
    gui:SetClampedToScreen(true)
    gui:EnableMouse(true)
    gui:RegisterForDrag("LeftButton")
    gui:SetScript("OnDragStart", gui.StartMoving)
    gui:SetScript("OnDragStop", gui.StopMovingOrSizing)
    gui:Hide()
    table.insert(UISpecialFrames, "AHLedgerFrame")

    if gui.SetResizeBounds then
        gui:SetResizeBounds(420, 300, 800, 600)
    end

    gui.TitleText:SetText("AH Ledger")

    -- Summary bar
    local summary = gui:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summary:SetPoint("TOPLEFT", gui.InsetBg, "TOPLEFT", 8, -8)
    summary:SetPoint("TOPRIGHT", gui.InsetBg, "TOPRIGHT", -8, -8)
    summary:SetJustifyH("LEFT")
    gui.summary = summary

    -- Filter buttons
    local filterY = -28
    local filters = { FILTER_ALL, FILTER_SOLD, FILTER_BOUGHT, FILTER_VENDOR, FILTER_EXPIRED }
    local filterLabels = { All = "All", sold = "Sold", bought = "Bought", vendor = "Vendor", expired = "Expired" }
    gui.filterButtons = {}

    local lastButton = nil
    for _, filter in ipairs(filters) do
        local btn = CreateFrame("Button", nil, gui, "UIPanelButtonTemplate")
        btn:SetSize(60, 22)
        if lastButton then
            btn:SetPoint("LEFT", lastButton, "RIGHT", 4, 0)
        else
            btn:SetPoint("TOPLEFT", gui.InsetBg, "TOPLEFT", 8, filterY)
        end
        btn:SetText(filterLabels[filter] or filter)
        btn:SetScript("OnClick", function()
            currentFilter = filter
            AHLedger:RefreshGUI()
        end)
        gui.filterButtons[filter] = btn
        lastButton = btn
    end

    -- Clear button (right-aligned)
    local clearBtn = CreateFrame("Button", nil, gui, "UIPanelButtonTemplate")
    clearBtn:SetSize(60, 22)
    clearBtn:SetPoint("TOPRIGHT", gui.InsetBg, "TOPRIGHT", -8, filterY)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        StaticPopup_Show("AHLEDGER_CONFIRM_CLEAR")
    end)

    -- Column headers
    local headerY = filterY - 28
    local headers = {
        { text = "Date", point = 8 },
        { text = "Type", point = 100 },
        { text = "Item", point = 170 },
        { text = "Amount", point = 410 },
    }

    for _, h in ipairs(headers) do
        local label = gui:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", gui.InsetBg, "TOPLEFT", h.point, headerY)
        label:SetTextColor(0.7, 0.7, 0.7)
        label:SetText(h.text)
    end

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "AHLedgerScrollFrame", gui, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", gui.InsetBg, "TOPLEFT", 4, headerY - 18)
    scrollFrame:SetPoint("BOTTOMRIGHT", gui.InsetBg, "BOTTOMRIGHT", -24, 4)
    gui.scrollFrame = scrollFrame

    -- Create row frames
    gui.rows = {}
    for i = 1, VISIBLE_ROWS do
        local row = CreateFrame("Frame", nil, gui)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 4, -((i - 1) * ROW_HEIGHT))
        row:SetPoint("RIGHT", scrollFrame, "RIGHT", 0, 0)
        row:EnableMouse(true)

        -- Alternating row background
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if i % 2 == 0 then
            bg:SetColorTexture(1, 1, 1, 0.03)
        else
            bg:SetColorTexture(0, 0, 0, 0)
        end

        row.dateText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.dateText:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.dateText:SetWidth(85)
        row.dateText:SetJustifyH("LEFT")

        row.typeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.typeText:SetPoint("LEFT", row, "LEFT", 96, 0)
        row.typeText:SetWidth(65)
        row.typeText:SetJustifyH("LEFT")

        row.itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.itemText:SetPoint("LEFT", row, "LEFT", 166, 0)
        row.itemText:SetWidth(235)
        row.itemText:SetJustifyH("LEFT")

        row.amountText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.amountText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.amountText:SetWidth(100)
        row.amountText:SetJustifyH("RIGHT")

        -- Tooltip on hover
        row:SetScript("OnEnter", function(self)
            if self.tx then
                ShowRowTooltip(self, self.tx)
            end
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        gui.rows[i] = row
    end

    -- Scroll handler
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function()
            AHLedger:UpdateRows()
        end)
    end)

    return gui
end

function AHLedger:UpdateRows()
    local gui = self.GUI
    if not gui then return end

    local filtered = GetFilteredTransactions()
    local offset = FauxScrollFrame_GetOffset(gui.scrollFrame)

    FauxScrollFrame_Update(gui.scrollFrame, #filtered, VISIBLE_ROWS, ROW_HEIGHT)

    for i = 1, VISIBLE_ROWS do
        local row = gui.rows[i]
        local idx = offset + i
        local tx = filtered[idx]

        if tx then
            row.tx = tx
            row.dateText:SetText(FormatTimestamp(tx.timestamp))

            local color = TYPE_COLORS[tx.type] or { r = 1, g = 1, b = 1 }
            local label = TYPE_LABELS[tx.type] or tx.type
            row.typeText:SetText(label)
            row.typeText:SetTextColor(color.r, color.g, color.b)

            if tx.quantity and tx.quantity > 1 then
                row.itemText:SetText(tx.item .. " x" .. tx.quantity)
            else
                row.itemText:SetText(tx.item)
            end

            if tx.amount and tx.amount > 0 then
                row.amountText:SetText(AHLedger:FormatGold(tx.amount))
                local color = TYPE_COLORS[tx.type] or { r = 1, g = 1, b = 1 }
                row.amountText:SetTextColor(color.r, color.g, color.b)
            else
                row.amountText:SetText("-")
                row.amountText:SetTextColor(0.5, 0.5, 0.5)
            end

            row:Show()
        else
            row.tx = nil
            row:Hide()
        end
    end
end

function AHLedger:RefreshGUI()
    local gui = self.GUI
    if not gui then return end

    -- Update summary
    local totalSold, totalBought, totalVendor, net, totalFees = GetSummary()
    local netColor = net >= 0 and "|cFF00CC00" or "|cFFCC0000"
    gui.summary:SetText(string.format(
        "Sold: |cFF00CC00%s|r  Bought: |cFFCC0000%s|r  Vendor: |cFF9980E6%s|r  Net: %s%s|r",
        self:FormatGold(totalSold),
        self:FormatGold(totalBought),
        self:FormatGold(totalVendor),
        netColor,
        self:FormatGold(net)
    ))

    -- Update filter button highlights
    for filter, btn in pairs(gui.filterButtons) do
        if filter == currentFilter then
            btn:SetEnabled(false)
        else
            btn:SetEnabled(true)
        end
    end

    self:UpdateRows()
end

function AHLedger:ToggleGUI()
    if not self.GUI then
        self.GUI = CreateGUI()
    end

    if self.GUI:IsShown() then
        self.GUI:Hide()
    else
        self:RefreshGUI()
        self.GUI:Show()
    end
end