-- Silent Aim | Lua | Synapse X / KRNL / any UNC executor
-- Hooks workspace:Raycast and Raycast-equivalent to redirect bullet origin/direction
-- toward nearest valid target without moving the camera — shots land, crosshair stays put

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera           = workspace.CurrentCamera
local LocalPlayer      = Players.LocalPlayer

-- ── CONFIG ──────────────────────────────────────────────────────────────────
local CFG = {
    Enabled     = true,
    TargetPart  = "Head",          -- "Head" | "HumanoidRootPart" | "UpperTorso"
    MaxDistance = 500,             -- studs — ignore targets beyond this
    TeamCheck   = true,            -- skip same-team players
    WallCheck   = true,            -- skip occluded targets
    FOVRadius   = 150,             -- screen-pixel FOV circle radius (0 = infinite)
    ShowFOV     = true,            -- draw FOV circle on screen
}

-- ── FOV CIRCLE (DrawingLib) ──────────────────────────────────────────────────
local fovCircle
if CFG.ShowFOV and Drawing then
    fovCircle = Drawing.new("Circle")
    fovCircle.Visible   = true
    fovCircle.Thickness = 1
    fovCircle.Radius    = CFG.FOVRadius
    fovCircle.Color     = Color3.fromRGB(255, 255, 255)
    fovCircle.Filled    = false
    fovCircle.NumSides  = 64

    RunService.RenderStepped:Connect(function()
        fovCircle.Position = Vector2.new(Camera.ViewportSize.X / 2,
                                         Camera.ViewportSize.Y / 2)
        fovCircle.Radius   = CFG.FOVRadius
        fovCircle.Visible  = CFG.Enabled and CFG.ShowFOV
    end)
end

-- ── HELPERS ──────────────────────────────────────────────────────────────────

-- World position → screen position; returns nil if behind camera
local function worldToScreen(pos)
    local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
    if not onScreen then return nil end
    return Vector2.new(screenPos.X, screenPos.Y)
end

-- Screen distance from viewport center to a world position
local function screenDist(worldPos)
    local sp = worldToScreen(worldPos)
    if not sp then return math.huge end
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    return (sp - center).Magnitude
end

local function getTargetPart(char)
    return char:FindFirstChild(CFG.TargetPart)
        or char:FindFirstChild("HumanoidRootPart")
end

local function isAlive(char)
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function isBehindWall(origin, targetPos, targetChar)
    local dir  = (targetPos - origin)
    local ray  = Ray.new(origin, dir)
    local hit  = workspace:FindPartOnRayWithIgnoreList(
        ray, { LocalPlayer.Character, Camera }, false, true
    )
    if not hit then return false end
    return not targetChar:IsAncestorOf(hit)
end

-- Returns the best target Character or nil
local function getBestTarget()
    local best     = nil
    local bestDist = CFG.FOVRadius > 0 and CFG.FOVRadius or math.huge

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        if CFG.TeamCheck and plr.Team == LocalPlayer.Team then continue end

        local char = plr.Character
        if not char or not isAlive(char) then continue end

        local part = getTargetPart(char)
        if not part then continue end

        local camPos = Camera.CFrame.Position
        if (part.Position - camPos).Magnitude > CFG.MaxDistance then continue end

        if CFG.WallCheck and isBehindWall(camPos, part.Position, char) then
            continue
        end

        local dist = screenDist(part.Position)
        if dist < bestDist then
            bestDist = dist
            best     = char
        end
    end

    return best
end

-- ── SILENT AIM CORE ──────────────────────────────────────────────────────────
-- Hook workspace.FindPartOnRayWithWhitelist / Raycast to intercept bullet traces.
-- Most Roblox guns use one of three patterns:
--   1. workspace:Raycast(origin, direction, params)          ← modern
--   2. workspace:FindPartOnRayWithIgnoreList(ray, blacklist) ← legacy
--   3. workspace:FindPartOnRay(ray, ignore)                  ← oldest
-- We hook all three. The hook replaces the direction/ray endpoint so the
-- bullet travels toward the target part instead of wherever the gun aimed.

local oldRaycast = workspace.Raycast

workspace.Raycast = function(ws, origin, direction, params)
    if not CFG.Enabled then
        return oldRaycast(ws, origin, direction, params)
    end

    local target = getBestTarget()
    if target then
        local part = getTargetPart(target)
        if part then
            -- preserve magnitude so max-distance checks inside gun scripts pass
            local mag       = direction.Magnitude
            local newDir    = (part.Position - origin).Unit * mag
            return oldRaycast(ws, origin, newDir, params)
        end
    end

    return oldRaycast(ws, origin, direction, params)
end

local oldFPOIL = workspace.FindPartOnRayWithIgnoreList

workspace.FindPartOnRayWithIgnoreList = function(ws, ray, blacklist, ...)
    if not CFG.Enabled then
        return oldFPOIL(ws, ray, blacklist, ...)
    end

    local target = getBestTarget()
    if target then
        local part = getTargetPart(target)
        if part then
            local mag    = ray.Direction.Magnitude
            local newDir = (part.Position - ray.Origin).Unit * mag
            ray          = Ray.new(ray.Origin, newDir)
        end
    end

    return oldFPOIL(ws, ray, blacklist, ...)
end

local oldFPOR = workspace.FindPartOnRay

workspace.FindPartOnRay = function(ws, ray, ignore, ...)
    if not CFG.Enabled then
        return oldFPOR(ws, ray, ignore, ...)
    end

    local target = getBestTarget()
    if target then
        local part = getTargetPart(target)
        if part then
            local mag    = ray.Direction.Magnitude
            local newDir = (part.Position - ray.Origin).Unit * mag
            ray          = Ray.new(ray.Origin, newDir)
        end
    end

    return oldFPOR(ws, ray, ignore, ...)
end

-- ── TOGGLE ───────────────────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.P then   -- P = toggle silent aim
        CFG.Enabled = not CFG.Enabled
    end
end)