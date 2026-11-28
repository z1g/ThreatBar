--[[
  ThreatBar — player-only threat data bar for WoW Forever.

  EllesmereUI already has the full group threat meter. This is the ElvUI
  DataBar: one StatusBar for YOUR threat on the current target, movable and
  resizable so it can sit on the cast bar.

  No COMBAT_LOG_EVENT. Data is UnitDetailedThreatSituation("player", "target").
  Forever usually hands those values over readable; a secret value is skipped
  (comparing a secret is ADDON_ACTION_BLOCKED, not a Lua error).
]]

local PREFIX = "|cff0cd29fThreatBar|r: "
local WHITE = "Interface\\Buttons\\WHITE8X8"
local SCREAM_FILE = "Interface\\AddOns\\ThreatBar\\wilhelm.ogg"
local MIN_W, MIN_H, MAX_W, MAX_H = 80, 8, 600, 48
local DEFAULT_W, DEFAULT_H = 260, 18
local TICK = 0.2
local SCREAM_CD = 4

ThreatBarDB = ThreatBarDB or {}

local frame, bar, text, bg, grip, eventFrame, skin
local aggR, aggG, aggB, lowR, lowG, lowB
local testUntil = 0
local testPct = 80
local elapsed = 0
local screamWasHot = false
local screamAt = 0

local function Secret(v)
  return v ~= nil and issecretvalue and issecretvalue(v)
end

local function Readable(v)
  return not Secret(v) and v ~= nil
end

local function Print(msg, ...)
  if select("#", ...) > 0 then
    msg = msg:format(...)
  end
  print(PREFIX .. msg)
end

local function Defaults()
  if type(ThreatBarDB) ~= "table" then ThreatBarDB = {} end
  if ThreatBarDB.width == nil then ThreatBarDB.width = DEFAULT_W end
  if ThreatBarDB.height == nil then ThreatBarDB.height = DEFAULT_H end
  if ThreatBarDB.locked == nil then ThreatBarDB.locked = false end
  if ThreatBarDB.shown == nil then ThreatBarDB.shown = true end
  if ThreatBarDB.displayText == nil then ThreatBarDB.displayText = true end
  if ThreatBarDB.hideOutOfCombat == nil then ThreatBarDB.hideOutOfCombat = true end
  if ThreatBarDB.scream == nil then ThreatBarDB.scream = true end
  ThreatBarDB.width = math.max(MIN_W, math.min(MAX_W, tonumber(ThreatBarDB.width) or DEFAULT_W))
  ThreatBarDB.height = math.max(MIN_H, math.min(MAX_H, tonumber(ThreatBarDB.height) or DEFAULT_H))
end

-- Blizzard status colours: 0 low, 1 gaining, 2 losing/tank losing, 3 tanking.
local function ThreatColor(status, isTanking)
  if Readable(status) and type(status) == "number" and GetThreatStatusColor then
    local r, g, b = GetThreatStatusColor(status)
    if r then return r, g, b end
  end
  if type(isTanking) == "boolean" then
    if not aggR then
      if GetThreatStatusColor then
        aggR, aggG, aggB = GetThreatStatusColor(3)
        lowR, lowG, lowB = GetThreatStatusColor(0)
      end
      aggR, aggG, aggB = aggR or 1, aggG or 0, aggB or 0
      lowR, lowG, lowB = lowR or 0.3, lowG or 1, lowB or 0
    end
    if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
      local fold = C_CurveUtil.EvaluateColorValueFromBoolean
      return fold(isTanking, aggR, lowR), fold(isTanking, aggG, lowG), fold(isTanking, aggB, lowB)
    end
    if isTanking then return aggR, aggG, aggB end
    return lowR, lowG, lowB
  end
  return 0.7, 0.7, 0.7
end

local function Unsnap(tex)
  if not tex then return end
  if EllesmereUI and EllesmereUI.PP and EllesmereUI.PP.DisablePixelSnap then
    EllesmereUI.PP.DisablePixelSnap(tex)
  elseif tex.SetSnapToPixelGrid then
    tex:SetSnapToPixelGrid(false)
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
  end
end

-- Match EllesmereUI's player cast bar fill (same catalogue as unit-frame health).
-- Forever profile here: castBarTexture = "blizzard" (UI-CastingBar-Fill atlas).
local function ApplyEUIFill()
  if not bar then return end

  local function UseAtlas(atlas)
    if not atlas or atlas == "" then return false end
    bar:SetStatusBarTexture(WHITE)
    local fill = bar:GetStatusBarTexture()
    if not (fill and fill.SetAtlas) then return false end
    fill:SetAtlas(atlas, true)
    if fill.SetHorizTile then fill:SetHorizTile(false) end
    Unsnap(fill)
    return true
  end

  local function UsePath(path)
    if not path then return false end
    bar:SetStatusBarTexture(path)
    local fill = bar:GetStatusBarTexture()
    if fill then
      if fill.SetHorizTile then fill:SetHorizTile(false) end
      Unsnap(fill)
    end
    return true
  end

  local uf = EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI._ModuleNS.EllesmereUIUnitFrames
  local cb = uf and uf.frames and uf.frames.player and uf.frames.player.Castbar
  if cb and cb.GetStatusBarTexture then
    local src = cb:GetStatusBarTexture()
    if src then
      local atlas = src.GetAtlas and src:GetAtlas()
      if Readable(atlas) and UseAtlas(atlas) then return end
      local path = src.GetTexture and src:GetTexture()
      if Readable(path) and UsePath(path) then return end
    end
  end

  local key = "blizzard"
  local p = EllesmereUIDB and EllesmereUIDB.EllesmereUIUnitFrames
  if type(p) == "table" then
    local slot = p._styleSlots and (p._styleSlots.forever or p._styleSlots.eui)
    local own = (slot and slot.castBarTexture) or p.castBarTexture
    local health = (slot and slot.healthBarTexture) or p.healthBarTexture
    if own and own ~= "inherit" then
      key = own
    elseif health then
      key = health
    end
  end

  if key == "blizzard" then
    if UseAtlas("UI-CastingBar-Fill") then return end
  end

  local path = WHITE
  if EllesmereUI and EllesmereUI.BuildBarTextureTables and EllesmereUI.ResolveTexturePath then
    local tex = EllesmereUI.BuildBarTextureTables(true)
    path = EllesmereUI.ResolveTexturePath(tex, key, WHITE) or WHITE
  end
  UsePath(path)
end

local function ApplyFallbackSkin(f)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = WHITE,
      edgeFile = WHITE,
      edgeSize = 1,
    })
    f:SetBackdropColor(0.06, 0.06, 0.06, 0.85)
    f:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
  end
end

local function SavePoint()
  if not frame then return end
  local left, bottom = frame:GetLeft(), frame:GetBottom()
  if not Readable(left) or not Readable(bottom) then return end
  ThreatBarDB.point, ThreatBarDB.relPoint = "BOTTOMLEFT", "BOTTOMLEFT"
  ThreatBarDB.x, ThreatBarDB.y = left, bottom
end

local function Layout()
  if not frame then return end
  frame:SetSize(ThreatBarDB.width, ThreatBarDB.height)
  if grip then
    if ThreatBarDB.locked then grip:Hide() else grip:Show() end
  end
end

local function SetVisible(show)
  if not frame then return end
  if show then frame:Show() else frame:Hide() end
end

local function Testing()
  return testUntil > 0 and GetTime() < testUntil
end

-- Status 1 = not tanking, higher threat than the current tank (about to pull).
-- Status 3 / isTanking = you already have aggro (solo or tanking) — stay quiet.
local function IsTankingUs(isTanking)
  if not Readable(isTanking) then return nil end
  return isTanking == true or isTanking == 1
end

local function OtherPlayerOrPetHasAggro()
  if not UnitExists("targettarget") then return false end
  local okU, same = pcall(function()
    return UnitIsUnit and UnitIsUnit("targettarget", "player")
  end)
  if okU and same then return false end
  local okP, isP = pcall(UnitIsPlayer, "targettarget")
  if okP and isP == true then return true end
  local okC, isC = pcall(UnitPlayerControlled, "targettarget")
  if okC and isC == true then return true end
  return false
end

local function PlayWilhelm()
  if not pcall(PlaySoundFile, SCREAM_FILE, "Master") then
    pcall(PlaySoundFile, SCREAM_FILE)
  end
end

local function MaybeScream(isTanking, status)
  if ThreatBarDB.scream == false then
    screamWasHot = false
    return
  end
  local aboutToPull = (IsTankingUs(isTanking) == false)
    and Readable(status) and type(status) == "number" and status == 1
    and OtherPlayerOrPetHasAggro()
  if aboutToPull and not screamWasHot then
    local now = GetTime()
    if now - screamAt >= SCREAM_CD then
      screamAt = now
      PlayWilhelm()
    end
  end
  screamWasHot = aboutToPull and true or false
end

local function ShouldShow(hasThreat)
  if ThreatBarDB.shown == false then return false end
  if not ThreatBarDB.locked or Testing() then return true end
  if ThreatBarDB.hideOutOfCombat and not UnitAffectingCombat("player") then
    return false
  end
  return hasThreat
end

local function Paint(pct, status, isTanking, hasThreat)
  if not bar then return end
  local show = ShouldShow(hasThreat)
  SetVisible(show)
  if not show then return end

  if Readable(pct) and type(pct) == "number" then
    bar:SetValue(pct)
  elseif Testing() then
    bar:SetValue(testPct)
  else
    bar:SetValue(0)
  end

  local r, g, b = ThreatColor(status, isTanking)
  if Testing() and not hasThreat then
    r, g, b = ThreatColor(2, false)
  end
  bar:SetStatusBarColor(r, g, b, 0.9)

  if text then
    if ThreatBarDB.displayText then
      if Testing() and not hasThreat then
        text:SetFormattedText("%.0f%%", testPct)
      elseif type(pct) == "number" then
        -- SetFormattedText accepts a secret percent (EUI PaintThreatPct).
        text:SetFormattedText("%.0f%%", pct)
      else
        text:SetText("")
      end
      text:Show()
    else
      text:Hide()
    end
  end
end

local function Update()
  if Testing() and GetTime() >= testUntil then
    testUntil = 0
  end

  local hasThreat = false
  local isTanking, status, pct
  if UnitExists("target") then
    isTanking, status, pct = UnitDetailedThreatSituation("player", "target")
    if type(pct) == "number" and (Secret(pct) or pct ~= 0) then
      hasThreat = true
    elseif Readable(isTanking) and isTanking then
      hasThreat = true
    end
  end

  if Testing() and not hasThreat then
    Paint(testPct, 2, false, true)
    return
  end
  Paint(pct, status, isTanking, hasThreat)
  MaybeScream(isTanking, status)
end

local function BuildFrame()
  frame = CreateFrame("Frame", "ThreatBarFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  if frame.SetResizeBounds then
    frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  else
    frame:SetMinResize(MIN_W, MIN_H)
    frame:SetMaxResize(MAX_W, MAX_H)
  end
  frame:EnableMouse(true)
  frame:SetFrameStrata("MEDIUM")
  frame:SetFrameLevel(50)
  ApplyFallbackSkin(frame)

  if ThreatBarDB.point then
    frame:SetPoint(
      ThreatBarDB.point, UIParent, ThreatBarDB.relPoint or ThreatBarDB.point,
      ThreatBarDB.x or 0, ThreatBarDB.y or 0
    )
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
  end

  bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture(WHITE)
  bg:SetVertexColor(0.08, 0.08, 0.08, 0.55)

  bar = CreateFrame("StatusBar", "ThreatBarStatus", frame)
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("BOTTOMRIGHT", -1, 1)
  bar:SetMinMaxValues(0, 100)
  bar:SetValue(0)
  ApplyEUIFill()
  bar:SetStatusBarColor(0.3, 1, 0, 0.9)

  text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("CENTER")
  text:SetJustifyH("CENTER")
  text:SetText("")
  frame.Text = text

  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function()
    if not ThreatBarDB.locked then frame:StartMoving() end
  end)
  frame:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    SavePoint()
  end)

  grip = CreateFrame("Button", nil, frame)
  grip:SetSize(12, 12)
  grip:SetPoint("BOTTOMRIGHT", 0, 0)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function()
    if ThreatBarDB.locked then return end
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if Readable(left) and Readable(bottom) then
      frame:ClearAllPoints()
      frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    end
    frame:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    SavePoint()
  end)
  frame.Grip = grip

  frame:SetScript("OnSizeChanged", function(self, w, h)
    if not Readable(w) or not Readable(h) then return end
    ThreatBarDB.width = math.max(MIN_W, math.min(MAX_W, w))
    ThreatBarDB.height = math.max(MIN_H, math.min(MAX_H, h))
  end)

  frame:SetScript("OnEnter", function()
    if not ThreatBarDB.displayText then
      GameTooltip:SetOwner(frame, "ANCHOR_TOP")
      GameTooltip:SetText("Threat")
      GameTooltip:Show()
    end
  end)
  frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  Layout()
end

local function SkinWithEUI()
  if not (EllesmereUI and EllesmereUI.RegisterSkin) then return end
  EllesmereUI.RegisterSkin("ThreatBar", function(S)
    skin = S
    if not frame then return end
    if S.Panel then
      S.Panel(frame)
    elseif S.Shell then
      S.Shell(frame, { noTopBar = true })
    end
    if frame.Text and S.Font then S.Font(frame.Text) end
    ApplyEUIFill()
    if S.OnLooksChanged then
      S.OnLooksChanged(function()
        if frame and frame.Text and S.Font then S.Font(frame.Text) end
        ApplyEUIFill()
      end)
    end
  end)
end

eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")

eventFrame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    Defaults()
    BuildFrame()
    SkinWithEUI()
    ApplyEUIFill()
    Update()
    Print("loaded. /threatbar  —  unlock, drag onto your cast bar, then /threatbar lock.")
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then
    ApplyEUIFill()
  end
  Update()
end)

eventFrame:SetScript("OnUpdate", function(_, dt)
  if not UnitAffectingCombat("player") and not Testing() and ThreatBarDB.locked then
    elapsed = 0
    return
  end
  elapsed = elapsed + dt
  if elapsed < TICK then return end
  elapsed = 0
  Update()
end)

SLASH_THREATBAR1 = "/threatbar"
SLASH_THREATBAR2 = "/tbar"
SlashCmdList.THREATBAR = function(msg)
  Defaults()
  msg = strtrim(msg or ""):lower()
  if msg == "" or msg == "toggle" then
    ThreatBarDB.shown = not (ThreatBarDB.shown ~= false)
    if ThreatBarDB.shown == false then
      SetVisible(false)
      Print("hidden.")
    else
      Update()
      Print("shown.")
    end
    return
  end
  if msg == "lock" then
    ThreatBarDB.locked = not ThreatBarDB.locked
    Layout()
    Update()
    Print(ThreatBarDB.locked and "locked." or "unlocked — drag the bar, drag the bottom-right corner to resize.")
    return
  end
  if msg == "text" then
    ThreatBarDB.displayText = not ThreatBarDB.displayText
    Update()
    Print(ThreatBarDB.displayText and "percent text on." or "percent text off.")
    return
  end
  if msg == "combat" then
    ThreatBarDB.hideOutOfCombat = not ThreatBarDB.hideOutOfCombat
    Update()
    Print(ThreatBarDB.hideOutOfCombat and "hides out of combat." or "stays visible out of combat.")
    return
  end
  if msg == "test" then
    testUntil = GetTime() + 10
    testPct = 80
    ThreatBarDB.shown = true
    Update()
    Print("test at 80%% for 10 seconds — place it on the cast bar, then /threatbar lock.")
    return
  end
  if msg == "scream test" or msg == "wilhelm test" then
    PlayWilhelm()
    Print("scream test. file=%s", SCREAM_FILE)
    return
  end
  if msg == "scream" or msg == "wilhelm" then
    ThreatBarDB.scream = not (ThreatBarDB.scream ~= false)
    Print(ThreatBarDB.scream and "Wilhelm on." or "Wilhelm off.")
    return
  end
  if msg == "reset" then
    ThreatBarDB.point, ThreatBarDB.relPoint, ThreatBarDB.x, ThreatBarDB.y = nil, nil, nil, nil
    ThreatBarDB.width, ThreatBarDB.height = DEFAULT_W, DEFAULT_H
    ThreatBarDB.shown = true
    if frame then
      frame:ClearAllPoints()
      frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
      Layout()
    end
    Update()
    Print("reset position and size.")
    return
  end
  Print("/threatbar        — show/hide")
  Print("/threatbar lock   — lock dragging and resizing")
  Print("/threatbar test   — show 80%% for 10s so you can place it")
  Print("/threatbar text   — toggle percent text")
  Print("/threatbar combat — toggle hide-out-of-combat")
  Print("/tbar wilhelm      — toggle Wilhelm (on by default)")
  Print("/tbar wilhelm test — play wilhelm.ogg")
  Print("/threatbar reset  — default size and position")
end
