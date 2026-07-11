-- NextCast: shows the next spell a TBC Shadow Priest or Balance Druid
-- should cast on the current target, plus your damage-over-time debuffs
-- on the target with their remaining duration.

local ADDON_NAME = ...

local _, playerClass = UnitClass("player")
if playerClass ~= "PRIEST" and playerClass ~= "DRUID" then return end
local IS_PRIEST = playerClass == "PRIEST"

--------------------------------------------------------------------------
-- Spell data (rank-1 spell IDs; names resolved via GetSpellInfo so the
-- addon works in any locale and with any rank the player knows)
--------------------------------------------------------------------------

local SPELLS
if IS_PRIEST then
    SPELLS = {
        shadowform  = 15473,
        swp         = 589,   -- Shadow Word: Pain
        vt          = 34914, -- Vampiric Touch
        ve          = 15286, -- Vampiric Embrace
        mindblast   = 8092,
        swd         = 32379, -- Shadow Word: Death
        mindflay    = 15407,
        shadowfiend = 34433,
        dp          = 2944,  -- Devouring Plague (Undead racial)
        starshards  = 10797, -- Starshards (Night Elf racial)
        innerfocus  = 14751, -- Inner Focus (Discipline talent)
    }
else
    SPELLS = {
        moonkin   = 24858, -- Moonkin Form
        ff        = 770,   -- Faerie Fire
        is        = 5570,  -- Insect Swarm
        moonfire  = 8921,
        starfire  = 2912,
        wrath     = 5176,
        innervate = 29166,
    }
end

local spellName, spellIcon = {}, {}
for key, id in pairs(SPELLS) do
    local name, _, icon = GetSpellInfo(id)
    spellName[key] = name
    spellIcon[key] = icon
end

-- "Faerie Fire (Feral)" is a differently-named, mutually-exclusive twin
-- of Faerie Fire: a feral's application blocks ours, so it must count
-- as FF coverage or the FF suggestion locks onto a cast that can't land.
local ffFeralName = not IS_PRIEST and GetSpellInfo(16857) or nil

-- Spellbook knowledge, cached and refreshed on SPELLS_CHANGED rather than
-- re-queried every display update.
local known = {}
local function RefreshKnown()
    for key in pairs(SPELLS) do
        -- a spell is "known" if looking it up by name in the spellbook succeeds
        known[key] = spellName[key] ~= nil and GetSpellInfo(spellName[key]) ~= nil
    end
end
RefreshKnown()

local function IsKnown(key)
    return known[key]
end

-- Balance T5, Nordrassil Regalia: the 4-piece makes Starfire hit 10%
-- harder while your Moonfire or Insect Swarm ticks on the target. Per
-- sims that set bonus is the only case where weaving Insect Swarm beats
-- casting more Starfire, so the IS suggestion is gated on wearing it.
local T5_ITEMS = {
    [30231] = true, -- Nordrassil Chestpiece
    [30232] = true, -- Nordrassil Gauntlets
    [30233] = true, -- Nordrassil Headpiece
    [30234] = true, -- Nordrassil Wrath-Kilt
    [30235] = true, -- Nordrassil Wrath-Mantle
}
local hasT5 = false

local function RefreshT5()
    if IS_PRIEST then return end
    local pieces = 0
    for slot = 1, 17 do
        local id = GetInventoryItemID("player", slot)
        if id and T5_ITEMS[id] then pieces = pieces + 1 end
    end
    hasT5 = pieces >= 4
end

-- On druids the box is Balance-only: the rotation's spells are baseline
-- for every druid, so without this gate a resto or feral druid would
-- get DPS suggestions mid-heal. Moonkin Form — the 31-point talent — is
-- the "actually a boomkin" signal.
local function SpecActive()
    return IS_PRIEST or IsKnown("moonkin")
end

local GCD = 1.5

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9NextCast:|r " .. msg)
end

-- Live cast time (seconds) for a known spell; GetSpellInfo's cast time
-- already reflects current spell haste, so this shortens under Bloodlust etc.
local function CastTime(key)
    local castMS = select(4, GetSpellInfo(spellName[key]))
    if castMS and castMS > 0 then
        return castMS / 1000
    end
    return GCD
end

-- World latency in seconds, folded into DoT refresh windows so recasts
-- land on time at real ping, not just at zero.
local function Latency()
    local _, _, _, world = GetNetStats()
    return (world or 0) / 1000
end

-- Remaining cooldown for a spell, ignoring the GCD.
local function CooldownRemaining(key)
    local start, duration = GetSpellCooldown(spellName[key])
    if not start or start == 0 or duration <= GCD then return 0 end
    return (start + duration) - GetTime()
end

-- Mind Flay channel info: returns start/end times (seconds) while channeling.
local function MindFlayChannel()
    local name, _, _, startMS, endMS = UnitChannelInfo("player")
    if name and name == spellName.mindflay then
        return startMS / 1000, endMS / 1000
    end
end

-- What we're casting right now, as a spell key, plus how long until the
-- cast finishes. Lets the rotation assume the cast lands and suggest the
-- spell after it.
local function CurrentCast()
    local name, _, _, _, endMS = UnitCastingInfo("player")
    if not name then return nil, 0 end
    local lead = endMS / 1000 - GetTime()
    if lead < 0 then lead = 0 end
    for key, sName in pairs(spellName) do
        if sName == name then return key, lead end
    end
    return nil, lead
end

-- Spells whose cast just succeeded but whose aura may not have reached the
-- client yet (server round-trip). Treated as applied for a short grace
-- window so the suggestion doesn't flicker back to them; a resist means
-- the suggestion simply reappears when the window lapses. Debuff grace is
-- keyed to the target it was cast on, so tab-targeting a new mob gets its
-- suggestions immediately; pass anyTarget for self-buffs like Shadowform.
local CAST_GRACE = 0.4
local justCast = {}     -- key -> time of successful cast
local justCastGUID = {} -- key -> target GUID at that moment

local function RecentlyCast(key, anyTarget)
    local t = justCast[key]
    if not t or (GetTime() - t) >= CAST_GRACE then return false end
    if anyTarget then return true end
    return justCastGUID[key] == UnitGUID("target")
end

--------------------------------------------------------------------------
-- Bloodlust / burst items
--------------------------------------------------------------------------

local LUST_SPELLS = { 2825, 32182 } -- Bloodlust, Heroism
local lustNames = {}
for _, id in ipairs(LUST_SPELLS) do
    local name = GetSpellInfo(id)
    if name then lustNames[name] = true end
end

local DESTRUCTION_POTION = 22839
local FALLBACK_ICON = 134400
local TRINKET_SLOTS = { 13, 14 }

local GetItemCooldownFn = GetItemCooldown or (C_Container and C_Container.GetItemCooldown)
local GetItemIconFn = GetItemIcon or (C_Item and C_Item.GetItemIconByID)

local function ItemReady(start, duration, enable)
    if enable == 0 then return false end
    if not start or start == 0 then return true end
    return (start + duration) - GetTime() <= 0
end

--------------------------------------------------------------------------
-- Aura scanning
--------------------------------------------------------------------------
-- Each display update scans the target's debuffs and the player's buffs
-- exactly once; everything else reads from these caches. No tables are
-- allocated per update.

local dotKeys = IS_PRIEST
    and { "swp", "vt", "ve", "dp", "starshards" }
    or { "ff", "is", "moonfire" }

local trackedDebuffs = {}
for _, key in ipairs(dotKeys) do
    if spellName[key] then trackedDebuffs[spellName[key]] = true end
end

local debuffExpiry, debuffDuration = {}, {}
local hasForm, hasLust, hasInnerFocus, hasInnervate = false, false, false, false

local function ScanAuras()
    for name in pairs(debuffExpiry) do
        debuffExpiry[name] = nil
        debuffDuration[name] = nil
    end
    for i = 1, 40 do
        local dName, _, _, _, duration, expirationTime = UnitDebuff("target", i, "PLAYER")
        if not dName then break end
        if trackedDebuffs[dName] and not debuffExpiry[dName] then
            debuffExpiry[dName] = expirationTime or 0
            debuffDuration[dName] = duration or 0
        end
    end
    -- Faerie Fire doesn't stack, so anyone's counts — pick it up without
    -- the PLAYER filter (overwriting the filtered result is harmless:
    -- there is only ever one instance on the target). The feral variant
    -- blocks ours entirely, so it counts as coverage too, recorded under
    -- the regular FF name so the rotation and tracker both see it.
    if spellName.ff then
        for i = 1, 40 do
            local dName, _, _, _, duration, expirationTime = UnitDebuff("target", i)
            if not dName then break end
            if dName == spellName.ff or dName == ffFeralName then
                debuffExpiry[spellName.ff] = expirationTime or 0
                debuffDuration[spellName.ff] = duration or 0
                break
            end
        end
    end
    hasForm, hasLust, hasInnerFocus, hasInnervate = false, false, false, false
    for i = 1, 40 do
        local bName = UnitBuff("player", i)
        if not bName then break end
        if bName == spellName.shadowform or bName == spellName.moonkin then hasForm = true end
        if bName == spellName.innerfocus then hasInnerFocus = true end
        if bName == spellName.innervate then hasInnervate = true end
        if lustNames[bName] then hasLust = true end
    end
end

-- Remaining time (or nil) of my debuff on the target, from the last scan.
local function MyDebuffRemaining(name)
    local exp = debuffExpiry[name]
    if not exp then return nil end
    if exp > 0 then
        return exp - GetTime(), debuffDuration[name]
    end
    return math.huge, 0
end

--------------------------------------------------------------------------
-- Saved settings
--------------------------------------------------------------------------

local defaults = {
    locked = false,
    hidden = false,
    scale = 1,
    useSWD = true,
    useVE = false,
    useFiend = true,
    useLust = true,
    useClip = true,
    useOOM = true,
    useRacial = true,
    useFocus = true,
    useTTD = true,
    useReport = true,
    point = { "CENTER", 0, -120 },
}

local db

local function LoadDB()
    NextCastDB = NextCastDB or {}
    db = NextCastDB
    for k, v in pairs(defaults) do
        if db[k] == nil then
            if type(v) == "table" then
                db[k] = { v[1], v[2], v[3] }
            else
                db[k] = v
            end
        end
    end
    -- learned mob lifetimes, keyed "npcID-difficulty" (open-ended, so
    -- not part of the fixed defaults above)
    db.mobLife = db.mobLife or {}
end

--------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------

local ICON_SIZE = 40
local DOT_SIZE = 22
local DOT_SPACING = 3
local ROW_WIDTH = DOT_SIZE * 3 + DOT_SPACING * 2

local frame = CreateFrame("Frame", "NextCastFrame", UIParent)
frame:SetSize(ROW_WIDTH + 8, ICON_SIZE + DOT_SIZE + 14 + 17)
-- draw above action bars and other standard UI so nothing overlaps the text
frame:SetFrameStrata("HIGH")
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self)
    if not db.locked then self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- relativePoint can differ from point after StopMovingOrSizing, so it
    -- must be saved too; stored 4th to stay compatible with old 3-tuples
    local point, _, relPoint, x, y = self:GetPoint()
    db.point = { point, x, y, relPoint }
end)

frame.bg = frame:CreateTexture(nil, "BACKGROUND")
frame.bg:SetAllPoints()
frame.bg:SetColorTexture(0, 0, 0, 0.5)
frame.bg:Hide()

frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.label:SetPoint("BOTTOM", frame, "TOP", 0, 2)
frame.label:SetText("NextCast")
frame.label:Hide()

-- Main suggestion icon
frame.icon = frame:CreateTexture(nil, "ARTWORK")
frame.icon:SetSize(ICON_SIZE, ICON_SIZE)
frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

-- border sits on a lower layer and extends past the icon, so only its
-- 2px edge is visible; turns red as the Mind Flay "clip now" signal
frame.iconBorder = frame:CreateTexture(nil, "BORDER")
frame.iconBorder:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", -2, 2)
frame.iconBorder:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 2, -2)
frame.iconBorder:SetColorTexture(0, 0, 0, 0.8)

-- red wash over the suggestion when SW:D backlash could kill us
frame.danger = frame:CreateTexture(nil, "OVERLAY")
frame.danger:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", 0, 0)
frame.danger:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 0, 0)
frame.danger:SetColorTexture(1, 0, 0, 0.45)
frame.danger:Hide()

frame.clipText = frame:CreateFontString(nil, "OVERLAY")
frame.clipText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
frame.clipText:SetPoint("CENTER", frame.icon, "CENTER", 0, 0)
frame.clipText:SetText("CLIP")
frame.clipText:SetTextColor(1, 0.15, 0.15)
frame.clipText:Hide()

-- Burst pop-out: potion/trinket suggestion during Bloodlust/Heroism
frame.burst = CreateFrame("Frame", nil, frame)
frame.burst:SetSize(ICON_SIZE, ICON_SIZE)
frame.burst:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 8, 0)
frame.burst.border = frame.burst:CreateTexture(nil, "BORDER")
frame.burst.border:SetPoint("TOPLEFT", -2, 2)
frame.burst.border:SetPoint("BOTTOMRIGHT", 2, -2)
frame.burst.border:SetColorTexture(1, 0.6, 0, 0.9)
frame.burst.icon = frame.burst:CreateTexture(nil, "ARTWORK")
frame.burst.icon:SetAllPoints()
frame.burst.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
frame.burst.label = frame.burst:CreateFontString(nil, "OVERLAY")
frame.burst.label:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
frame.burst.label:SetPoint("BOTTOM", frame.burst, "BOTTOM", 0, 2)
frame.burst.label:SetText("USE!")
frame.burst.label:SetTextColor(1, 0.6, 0)
frame.burst.pulse = frame.burst:CreateAnimationGroup()
local burstAnim = frame.burst.pulse:CreateAnimation("Alpha")
burstAnim:SetFromAlpha(1)
burstAnim:SetToAlpha(0.4)
burstAnim:SetDuration(0.4)
frame.burst.pulse:SetLooping("BOUNCE")
frame.burst:Hide()

-- Estimated time until out of mana, shown under the debuff row in combat
frame.oomText = frame:CreateFontString(nil, "OVERLAY")
frame.oomText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
frame.oomText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 4)
frame.oomText:Hide()

-- Debuff tracker row: SW:P, VT, VE
local dotFrames = {}
for i, key in ipairs(dotKeys) do
    local dot = CreateFrame("Frame", nil, frame)
    dot:SetSize(DOT_SIZE, DOT_SIZE)

    dot.icon = dot:CreateTexture(nil, "ARTWORK")
    dot.icon:SetAllPoints()
    dot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    dot.icon:SetTexture(spellIcon[key])

    dot.cd = CreateFrame("Cooldown", nil, dot, "CooldownFrameTemplate")
    dot.cd:SetAllPoints()
    dot.cd:SetReverse(true)
    dot.cd:SetHideCountdownNumbers(true)
    dot.cd:SetDrawEdge(false)

    -- text lives on its own frame so it draws above the cooldown swirl
    dot.textFrame = CreateFrame("Frame", nil, dot)
    dot.textFrame:SetAllPoints()
    dot.textFrame:SetFrameLevel(dot.cd:GetFrameLevel() + 1)
    dot.text = dot.textFrame:CreateFontString(nil, "OVERLAY")
    dot.text:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    dot.text:SetPoint("CENTER", dot, "CENTER", 0, 0)

    dot.key = key
    dotFrames[i] = dot
end

-- A tracker slot is shown only for spells this character knows (racials
-- resolve per-race) and hasn't toggled off.
local function DotVisible(key)
    if not IsKnown(key) then return false end
    if key == "ve" and not db.useVE then return false end
    if (key == "dp" or key == "starshards") and not db.useRacial then return false end
    if key == "is" and not hasT5 then return false end
    return true
end

-- Anchor the visible tracker slots side by side and fit the frame width
-- to however many this character actually has (3 base + 1 racial).
local function LayoutDots()
    if not db then return end
    local shown = 0
    for _, dot in ipairs(dotFrames) do
        if DotVisible(dot.key) then
            dot:ClearAllPoints()
            dot:SetPoint("TOPLEFT", frame, "TOPLEFT",
                4 + shown * (DOT_SIZE + DOT_SPACING), -(4 + ICON_SIZE + 4))
            shown = shown + 1
        end
    end
    local rowWidth = math.max(shown * DOT_SIZE + math.max(shown - 1, 0) * DOT_SPACING, ICON_SIZE)
    frame:SetWidth(rowWidth + 8)
end

--------------------------------------------------------------------------
-- Rotation logic
--------------------------------------------------------------------------

local function ManaPct()
    local max = UnitPowerMax("player", 0)
    if max == 0 then return 100 end
    return UnitPower("player", 0) / max * 100
end

-- Time-until-OOM: projected from the average net drain since combat
-- started (mana anchored on PLAYER_REGEN_DISABLED). A whole-fight average
-- bakes in spell costs, Spirit Tap, VT returns, fiend, and mp5, and it is
-- stable — a short sliding window swings wildly as bursty casts enter and
-- leave it. Converges as the fight goes on.
local oomStartTime, oomStartMana = 0, 0

local function OOMReset()
    oomStartTime = GetTime()
    oomStartMana = UnitPower("player", 0)
end

-- Seconds until OOM at the fight-average drain rate, or nil early in the
-- fight or while mana is flat/climbing.
local function TimeToOOM()
    if oomStartTime == 0 then return nil end
    local elapsed = GetTime() - oomStartTime
    if elapsed < 8 then return nil end
    local mana = UnitPower("player", 0)
    local rate = (oomStartMana - mana) / elapsed
    if rate < 1 then return nil end
    return mana / rate
end

-- Shadow Word: Death backlash safety. Estimates the worst case the spell
-- could hit us for — max base damage of the known rank plus shadow spell
-- power (0.429 coefficient), amplified ~1.6x for talents/target debuffs
-- (Shadowform, Darkness, Shadow Weaving, Misery, curses) and 1.5x for a
-- crit. When current health doesn't clear that with a 10% margin, the
-- SW:D suggestion still shows but gets a red danger overlay.
local SWD_COEFF = 0.429
local SWD_AMP = 1.6
local SWD_CRIT = 1.5
local SWD_MARGIN = 1.1

-- Devouring Plague is a DPS gain but very mana-hungry: only suggest it
-- while mana is comfortably above this percentage.
local DP_MANA_PCT = 60

-- Shadowfiend/Innervate is the emergency mana button: hold it until mana
-- is actually low so its return isn't wasted on a near-full bar.
local FIEND_MANA_PCT = 20

-- Moonfire has Devouring Plague's problem in miniature: real DPS, ugly
-- mana efficiency — only suggest it while mana is comfortable.
local MF_MANA_PCT = 60

local function SWDMaxBase()
    if IsPlayerSpell then
        if IsPlayerSpell(32996) then return 664 end -- Rank 2
        if IsPlayerSpell(32379) then return 522 end -- Rank 1
    end
    return 664 -- rank unknown: assume the bigger hit
end

local function SWDSafe()
    local sp = GetSpellBonusDamage and GetSpellBonusDamage(6) or 0 -- 6 = shadow
    local worstBacklash = (SWDMaxBase() + SWD_COEFF * sp) * SWD_AMP * SWD_CRIT
    return UnitHealth("player") > worstBacklash * SWD_MARGIN
end

-- Target time-to-die: same ring-buffer approach as the OOM estimator,
-- pointed at the target's health. The buffer resets whenever the target
-- GUID changes, so each mob gets its own estimate.
local TTD_WINDOW = 10
local TTD_SAMPLE_EVERY = 0.5
local TTD_SLOTS = math.floor(TTD_WINDOW / TTD_SAMPLE_EVERY) + 1
local ttdTimes, ttdHealths = {}, {}
local ttdIndex, ttdLastSample = 0, 0
local ttdGUID

local function TTDReset()
    for i = 1, TTD_SLOTS do
        ttdTimes[i] = nil
        ttdHealths[i] = nil
    end
    ttdLastSample = 0
end

local function TTDSample()
    local guid = UnitGUID("target")
    if guid ~= ttdGUID then
        ttdGUID = guid
        TTDReset()
    end
    if not guid then return end
    local now = GetTime()
    if now - ttdLastSample < TTD_SAMPLE_EVERY then return end
    ttdLastSample = now
    ttdIndex = (ttdIndex % TTD_SLOTS) + 1
    ttdTimes[ttdIndex] = now
    ttdHealths[ttdIndex] = UnitHealth("target")
end

-- Seconds until the target dies at the current damage rate, or nil when
-- there's too little data or its health isn't dropping.
local function TimeToDie()
    local now = GetTime()
    local oldestT, oldestH
    for i = 1, TTD_SLOTS do
        local t = ttdTimes[i]
        if t and now - t <= TTD_WINDOW and (not oldestT or t < oldestT) then
            oldestT, oldestH = t, ttdHealths[i]
        end
    end
    if not oldestT or now - oldestT < 3 then return nil end
    local hp = UnitHealth("target")
    local rate = (oldestH - hp) / (now - oldestT)
    if rate <= 0 then return nil end
    return hp / rate
end

--------------------------------------------------------------------------
-- Mob lifetime learning
--------------------------------------------------------------------------
-- The live TTD estimate needs a few seconds of health samples, so it's
-- blind exactly when the DoT decision matters most: the opening GCDs of
-- a trash pull. Instead, learn how long each mob type actually lives —
-- first combat-log appearance to UNIT_DIED, averaged per npc id and
-- instance difficulty in SavedVariables. On the next pull of that mob
-- type, the DoT gates know from second zero whether a DoT will pay off.
-- The live estimate still wins once it has data; this fills the cold
-- start.

local LIFE_MIN_SAMPLES = 2 -- don't trust an average of one kill
local LIFE_EMA = 0.3       -- weight of each new kill in the running average
local LIFE_MAX_AGE = 900   -- forget mobs with no death this long after first seen

local mobFirstSeen = {} -- mob GUID -> first combat-log appearance (GetTime)

-- Entries survive combat drops on purpose — wiping them at combat edges
-- recorded phase-transition fragments as whole boss lifetimes. Evaded
-- or abandoned mobs age out instead (spawn GUIDs are never reused).
local function LifePrune()
    local cutoff = GetTime() - LIFE_MAX_AGE
    for guid, born in pairs(mobFirstSeen) do
        if born < cutoff then
            mobFirstSeen[guid] = nil
        end
    end
end

-- Hostile (or neutral) NPC — excludes players, pets, and friendly
-- creatures like totems, so incidental damage traffic can't count them.
local HOSTILE_NPC_MASK = COMBATLOG_OBJECT_REACTION_HOSTILE + COMBATLOG_OBJECT_REACTION_NEUTRAL
local function IsHostileNPC(guid, flags)
    return flags and bit.band(flags, HOSTILE_NPC_MASK) ~= 0
        and (guid:find("Creature", 1, true) == 1 or guid:find("Vehicle", 1, true) == 1)
end

-- Lifetime records are keyed npcID-difficulty: the same npc id lives
-- longer on heroic than on normal.
local function NpcKey(guid)
    if guid:find("Creature", 1, true) == 1 or guid:find("Vehicle", 1, true) == 1 then
        local npcID = select(6, strsplit("-", guid))
        if npcID then
            return npcID .. "-" .. (select(3, GetInstanceInfo()) or 0)
        end
    end
end

local function LifeMobSeen(guid, now)
    if not mobFirstSeen[guid] then
        mobFirstSeen[guid] = now
    end
end

local function LifeMobDied(guid, now)
    local born = mobFirstSeen[guid]
    mobFirstSeen[guid] = nil
    if not born or not (db and db.mobLife) then return end
    local sample = now - born
    if sample < 1 then return end
    local key = NpcKey(guid)
    if not key then return end
    local e = db.mobLife[key]
    if not e then
        db.mobLife[key] = { t = sample, n = 1 }
    else
        -- clamp each sample's influence rather than discarding outliers:
        -- one mob that sat in crowd control can't poison the average,
        -- but a wrong average (bad first sample, group got faster or
        -- slower) still drifts back to reality over a few kills
        local capped = math.min(math.max(sample, e.t / 3), e.t * 3)
        e.t = e.t + (capped - e.t) * LIFE_EMA
        e.n = e.n + 1
    end
end

-- Expected seconds of life left in the current target, from its learned
-- lifetime minus how long it has already been in the fight.
local function LearnedTTD()
    local guid = UnitGUID("target")
    if not guid then return nil end
    local key = NpcKey(guid)
    local e = key and db.mobLife[key]
    if not e or e.n < LIFE_MIN_SAMPLES then return nil end
    local born = mobFirstSeen[guid]
    local remaining = e.t - (born and (GetTime() - born) or 0)
    -- a mob that has outlived its learned average has falsified the
    -- prediction for this fight — no gate beats a wrong gate
    if remaining <= 0 then return nil end
    return remaining
end

-- Vampiric Embrace only pays off on long fights — trash dies too fast
-- for the group healing to matter. Raid bosses show as level -1 (skull)
-- and world bosses carry the "worldboss" classification, but TBC 5-man
-- bosses (normal AND heroic) are plain numeric-level elites — Murmur is
-- "72 Elite" — so inside a 5-man, treat an elite 2+ levels above the
-- player as a boss. The rare 72-elite trash mob this also matches is an
-- acceptable false positive; raids aren't included since their bosses
-- are already skull and their trash shouldn't qualify.
local function IsBossTarget()
    local lvl = UnitLevel("target")
    if lvl == -1 or UnitClassification("target") == "worldboss" then
        return true
    end
    local _, instanceType = GetInstanceInfo()
    return instanceType == "party"
        and UnitClassification("target") == "elite"
        and lvl >= UnitLevel("player") + 2
end

-- Balance Druid priority: Moonkin Form, keep Faerie Fire up, Moonfire
-- while mana is healthy, Insect Swarm only with 4pc T5, Innervate on
-- bosses when running dry, Starfire filler (Wrath before Starfire is
-- trained).
local function DruidNextSpell(castingKey, lead, ttd)
    if IsKnown("moonkin") and not RecentlyCast("moonkin", true)
        and not hasForm then
        return "moonkin"
    end

    if IsKnown("ff") and not RecentlyCast("ff") and (not ttd or ttd > 5) then
        local remaining = MyDebuffRemaining(spellName.ff)
        if not remaining or remaining <= lead + Latency() then
            return "ff"
        end
    end

    if IsKnown("moonfire") and not RecentlyCast("moonfire")
        and ManaPct() >= MF_MANA_PCT
        and (not ttd or ttd > 6) then
        local remaining = MyDebuffRemaining(spellName.moonfire)
        if not remaining or remaining <= lead + Latency() then
            return "moonfire"
        end
    end

    -- Insect Swarm is a DPS loss next to more Starfire — Nature damage
    -- that misses Moonfury, Curse of Shadow, and crit — except with 4pc
    -- T5, where it cheaply keeps the +10% Starfire buff active (notably
    -- when low mana has gated Moonfire off above).
    if hasT5 and IsKnown("is") and not RecentlyCast("is")
        and (not ttd or ttd > 6) then
        local remaining = MyDebuffRemaining(spellName.is)
        if not remaining or remaining <= lead + Latency() then
            return "is"
        end
    end

    -- Innervate mirrors the Shadowfiend rules (and shares its toggle):
    -- boss fights only, held until mana is actually low.
    if db.useFiend and IsKnown("innervate")
        and UnitAffectingCombat("player")
        and IsBossTarget()
        and not hasInnervate
        and ManaPct() <= FIEND_MANA_PCT
        and CooldownRemaining("innervate") <= lead then
        return "innervate"
    end

    if IsKnown("starfire") then
        return "starfire"
    end
    if IsKnown("wrath") then
        return "wrath"
    end
    return nil
end

-- Decide the next spell. `castingKey` is the spell currently being cast
-- (assumed to land, so it's skipped), and `lead` is the time until that
-- cast finishes — cooldowns/DoTs are evaluated as of that moment, so the
-- suggestion is what to press NEXT, not what's happening now.
local function NextSpell(castingKey, lead)
    lead = lead or 0
    -- DoTs are gated on the target living long enough to pay for their
    -- GCD; no estimate (nil) means no gating. The live estimate wins
    -- when it has data, learned mob lifetimes cover the opening seconds.
    local ttd = TimeToDie() or LearnedTTD()

    if not IS_PRIEST then
        return DruidNextSpell(castingKey, lead, ttd)
    end

    if IsKnown("shadowform") and not RecentlyCast("shadowform", true)
        and not hasForm then
        return "shadowform"
    end

    -- Vampiric Touch: refresh when remaining time won't outlast its cast,
    -- using the live haste-adjusted cast time.
    if IsKnown("vt") and castingKey ~= "vt" and not RecentlyCast("vt")
        and (not ttd or ttd > 8) then
        local remaining = MyDebuffRemaining(spellName.vt)
        if not remaining or remaining < lead + CastTime("vt") + Latency() then
            return "vt"
        end
    end

    if IsKnown("swp") and not RecentlyCast("swp") and (not ttd or ttd > 6) then
        local remaining = MyDebuffRemaining(spellName.swp)
        if not remaining or remaining <= lead + Latency() then
            return "swp"
        end
    end

    if db.useVE and IsKnown("ve") and not RecentlyCast("ve")
        and IsBossTarget()
        and (not ttd or ttd > 10)
        and not MyDebuffRemaining(spellName.ve) then
        return "ve"
    end

    if IsKnown("mindblast") and castingKey ~= "mindblast"
        and CooldownRemaining("mindblast") <= lead + 0.3 then
        return "mindblast"
    end

    if db.useSWD and IsKnown("swd") and CooldownRemaining("swd") <= lead + 0.3 then
        return "swd"
    end

    -- Racial DoTs: instants, so one GCD buys a long DoT — worth casting
    -- above Mind Flay per standard TBC priority. Devouring Plague's huge
    -- mana cost makes it the first cut when mana runs thin, hence the
    -- mana gate; its 3-minute cooldown is too precious to burn on trash
    -- right before a boss, hence the boss gate.
    if db.useRacial and IsKnown("dp") and not RecentlyCast("dp")
        and IsBossTarget()
        and ManaPct() >= DP_MANA_PCT
        and (not ttd or ttd > 12)
        and CooldownRemaining("dp") <= lead + 0.3
        and not MyDebuffRemaining(spellName.dp) then
        return "dp"
    end

    if db.useRacial and IsKnown("starshards") and not RecentlyCast("starshards")
        and (not ttd or ttd > 8)
        and CooldownRemaining("starshards") <= lead + 0.3
        and not MyDebuffRemaining(spellName.starshards) then
        return "starshards"
    end

    -- Boss-only: on trash you can drink between packs, and burning the
    -- 5-minute cooldown there risks not having it for the boss pull.
    if db.useFiend and IsKnown("shadowfiend")
        and UnitAffectingCombat("player")
        and IsBossTarget()
        and ManaPct() <= FIEND_MANA_PCT
        and CooldownRemaining("shadowfiend") <= lead then
        return "shadowfiend"
    end

    if IsKnown("mindflay") then
        return "mindflay"
    end

    return nil
end

-- During Bloodlust/Heroism: Destruction Potion first, then any equipped
-- on-use trinket that is ready. Returns an icon texture or nil.
local function BurstSuggestion()
    if not db.useLust or not hasLust then return nil end

    if GetItemCooldownFn and GetItemCount(DESTRUCTION_POTION) > 0 then
        if ItemReady(GetItemCooldownFn(DESTRUCTION_POTION)) then
            return (GetItemIconFn and GetItemIconFn(DESTRUCTION_POTION)) or FALLBACK_ICON
        end
    end

    for _, slot in ipairs(TRINKET_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link and GetItemSpell(link) then -- has an on-use effect
            if ItemReady(GetInventoryItemCooldown("player", slot)) then
                return GetInventoryItemTexture("player", slot)
            end
        end
    end
    return nil
end

-- True when we should end the current Mind Flay channel early: the 2nd
-- tick has fired and the rotation wants something better than more flay.
local function ShouldClip(key)
    if not db.useClip or not key or key == "mindflay" then return false end
    local chStart, chEnd = MindFlayChannel()
    if not chStart then return false end
    local tick = (chEnd - chStart) / 3
    return (GetTime() - chStart) >= (tick * 2 - 0.05)
end

--------------------------------------------------------------------------
-- Fight report
--------------------------------------------------------------------------
-- Report tracking runs only between PLAYER_REGEN_DISABLED and _ENABLED
-- (gated on report.active; the combat-log event itself stays registered
-- for lifetime learning). After fights of REPORT_MIN_SECONDS or longer,
-- a one-line summary is printed: DoT uptime, mana returned to the group
-- via VT, VE healing, cast counts.

local REPORT_MIN_SECONDS = 30

local playerGUID

-- What the report tracks, per class: DoT uptimes and cast counts.
local REPORT_DOTS = IS_PRIEST and { "swp", "vt" } or { "is", "moonfire" }
local REPORT_CASTS = IS_PRIEST and { "mindblast", "swd" } or { "starfire", "wrath" }
local REPORT_LABELS = {
    swp = "SW:P", vt = "VT", mindblast = "MB", swd = "SW:D",
    is = "IS", moonfire = "MF", starfire = "SF", wrath = "Wrath",
}

local dotBySpellName = {}
for _, key in ipairs(REPORT_DOTS) do
    if spellName[key] then dotBySpellName[spellName[key]] = key end
end

local report = {
    active = false,
    start = 0,
    vtMana = 0,
    veHeal = 0,
    casts = {},
    dots = {},
}
for _, key in ipairs(REPORT_DOTS) do
    report.dots[key] = { guids = {}, n = 0, since = 0, total = 0 }
end
for _, key in ipairs(REPORT_CASTS) do
    report.casts[key] = 0
end

local function StartReport()
    report.active = true
    report.start = GetTime()
    report.vtMana, report.veHeal = 0, 0
    for key in pairs(report.casts) do
        report.casts[key] = 0
    end
    for _, d in pairs(report.dots) do
        wipe(d.guids)
        d.n, d.since, d.total = 0, 0, 0
    end
end

-- Uptime is "time at least one mob carries my DoT": a per-GUID set with a
-- running counter, accumulating whenever the counter is above zero.
local function DotApplied(d, guid, now)
    if not d.guids[guid] then
        d.guids[guid] = true
        d.n = d.n + 1
        if d.n == 1 then d.since = now end
    end
end

local function DotRemoved(d, guid, now)
    if d.guids[guid] then
        d.guids[guid] = nil
        d.n = d.n - 1
        if d.n == 0 then d.total = d.total + (now - d.since) end
    end
end

local function HandleCombatLog(_, subevent, _, sourceGUID, _, sourceFlags, _, destGUID, _, destFlags, _, _, spellN, _, amount)
    local now = GetTime()
    -- Lifetime learning runs on every event, in combat or not, so a
    -- mob's 'born' stamp reflects when the FIGHT started — not when we
    -- personally entered combat after drinking through half the pull.
    if subevent == "UNIT_DIED" then
        LifeMobDied(destGUID, now)
        if report.active then
            for _, d in pairs(report.dots) do
                DotRemoved(d, destGUID, now)
            end
        end
        return
    end
    -- Any damage traffic (either direction, landed or missed, from
    -- anyone) stamps a hostile NPC's entry into the fight.
    if subevent:find("_DAMAGE", 1, true) or subevent:find("_MISSED", 1, true) then
        if IsHostileNPC(destGUID, destFlags) then
            LifeMobSeen(destGUID, now)
        elseif IsHostileNPC(sourceGUID, sourceFlags) then
            LifeMobSeen(sourceGUID, now)
        end
    end
    if not report.active then return end
    if sourceGUID ~= playerGUID then return end
    if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
        local key = dotBySpellName[spellN]
        if key then DotApplied(report.dots[key], destGUID, now) end
    elseif subevent == "SPELL_AURA_REMOVED" then
        local key = dotBySpellName[spellN]
        if key then DotRemoved(report.dots[key], destGUID, now) end
    elseif subevent == "SPELL_ENERGIZE" then
        if spellN == spellName.vt and amount then
            report.vtMana = report.vtMana + amount
        end
    elseif subevent == "SPELL_PERIODIC_HEAL" or subevent == "SPELL_HEAL" then
        if spellN == spellName.ve and amount then
            report.veHeal = report.veHeal + amount
        end
    end
end

local function FinishReport()
    if not report.active then return end
    report.active = false
    local now = GetTime()
    local dur = now - report.start
    for _, d in pairs(report.dots) do
        if d.n > 0 then
            d.total = d.total + (now - d.since)
            d.n = 0
            wipe(d.guids)
        end
    end
    if not db or not db.useReport or dur < REPORT_MIN_SECONDS then return end
    if not SpecActive() then return end
    local sawAction = false
    for _, count in pairs(report.casts) do
        if count > 0 then sawAction = true end
    end
    for _, d in pairs(report.dots) do
        if d.total > 0 then sawAction = true end
    end
    if not sawAction then return end
    local parts = {}
    parts[#parts + 1] = string.format("fight %d:%02d", math.floor(dur / 60), math.floor(dur % 60))
    for _, key in ipairs(REPORT_DOTS) do
        -- IS only counts as part of the rotation with 4pc T5; without
        -- it, "IS 0%" would scold players for following the addon's
        -- own advice not to cast it
        if IsKnown(key) and (key ~= "is" or hasT5) then
            parts[#parts + 1] = string.format("%s %d%%", REPORT_LABELS[key], report.dots[key].total / dur * 100)
        end
    end
    if report.vtMana > 0 then
        parts[#parts + 1] = string.format("VT mana to group %d", report.vtMana)
    end
    if report.veHeal > 0 then
        parts[#parts + 1] = string.format("VE healing %d", report.veHeal)
    end
    for _, key in ipairs(REPORT_CASTS) do
        if IsKnown(key) then
            parts[#parts + 1] = string.format("%s %d", REPORT_LABELS[key], report.casts[key])
        end
    end
    Print(table.concat(parts, " | "))
end

--------------------------------------------------------------------------
-- Display update
--------------------------------------------------------------------------

local function HasValidTarget()
    return UnitExists("target")
        and UnitCanAttack("player", "target")
        and not UnitIsDead("target")
end

local function FormatTime(seconds)
    if seconds >= 60 then
        return string.format("%dm", math.ceil(seconds / 60))
    elseif seconds >= 10 then
        return string.format("%d", seconds)
    else
        return string.format("%.1f", seconds)
    end
end

local function UpdateDots()
    for _, dot in ipairs(dotFrames) do
        if not DotVisible(dot.key) then
            dot:Hide()
        else
            dot:Show()
            local remaining, duration = MyDebuffRemaining(spellName[dot.key])
            if remaining and remaining > 0 then
                dot.icon:SetDesaturated(false)
                dot.icon:SetAlpha(1)
                if remaining ~= math.huge and duration and duration > 0 then
                    -- start time is constant for a given application, so
                    -- only push a new cooldown when the aura was refreshed
                    local start = GetTime() - (duration - remaining)
                    if not dot.cdStart or math.abs(start - dot.cdStart) > 0.01
                        or duration ~= dot.cdDur then
                        dot.cdStart, dot.cdDur = start, duration
                        dot.cd:SetCooldown(start, duration)
                    end
                    dot.text:SetText(FormatTime(remaining))
                    if remaining < 3 then
                        dot.text:SetTextColor(1, 0.2, 0.2)
                    else
                        dot.text:SetTextColor(1, 1, 1)
                    end
                else
                    dot.cdStart, dot.cdDur = nil, nil
                    dot.cd:Clear()
                    dot.text:SetText("")
                end
            else
                dot.icon:SetDesaturated(true)
                dot.icon:SetAlpha(0.35)
                dot.cdStart, dot.cdDur = nil, nil
                dot.cd:Clear()
                dot.text:SetText("")
            end
        end
    end
end

local function UpdateDisplay()
    if not db then return end
    if db.hidden or not SpecActive() then
        frame:Hide()
        return
    end
    frame:Show()
    if not db.locked then
        frame.bg:Show()
        frame.label:Show()
    else
        frame.bg:Hide()
        frame.label:Hide()
    end

    ScanAuras()
    TTDSample()

    local valid = HasValidTarget()
    local key, clipKey
    local chStart, chEnd = MindFlayChannel()
    if chStart then
        -- Channeling: the displayed suggestion assumes we finish the
        -- channel, while the clip decision only considers spells ready
        -- right now — never cut a channel for something still on cooldown.
        key = NextSpell("mindflay", math.max(chEnd - GetTime(), 0))
        clipKey = NextSpell(nil, 0)
    else
        local castingKey, lead = CurrentCast()
        key = NextSpell(castingKey, lead)
    end

    -- With no attackable target the aura checks come up empty, so this
    -- naturally suggests the opener — shown dimmed until a target exists.
    if key then
        frame.icon:SetTexture(spellIcon[key])
        frame.icon:SetDesaturated(not valid)
        frame.icon:SetAlpha(valid and 1 or 0.45)
    else
        frame.icon:SetTexture(nil)
    end

    if key == "swd" and not SWDSafe() then
        frame.danger:Show()
    else
        frame.danger:Hide()
    end

    if valid and ShouldClip(clipKey) then
        frame.clipText:Show()
        frame.iconBorder:SetColorTexture(1, 0.15, 0.15, 1)
    else
        frame.clipText:Hide()
        frame.iconBorder:SetColorTexture(0, 0, 0, 0.8)
    end

    local burstIcon = BurstSuggestion()
    -- Inner Focus pairing: its +25% crit is wasted on DoTs (they can't
    -- crit in TBC) but the free cast is worth the most on the priciest
    -- DoT — so alert when IF is ready and the suggestion is DP or SW:P.
    if not burstIcon and db.useFocus and IsKnown("innerfocus")
        and not hasInnerFocus and not RecentlyCast("innerfocus", true)
        and CooldownRemaining("innerfocus") <= 0
        -- on Undead, hold IF for the pricier Devouring Plague unless DP
        -- is still a ways out
        and (key == "dp" or (key == "swp"
            and (not IsKnown("dp") or CooldownRemaining("dp") > 30))) then
        burstIcon = spellIcon.innerfocus
    end
    local burstPreview = false
    if not burstIcon and not db.locked then
        -- unlocked placement preview: static and faded, never pulsing
        burstIcon = (GetItemIconFn and GetItemIconFn(DESTRUCTION_POTION)) or FALLBACK_ICON
        burstPreview = true
    end
    if burstIcon then
        frame.burst.icon:SetTexture(burstIcon)
        frame.burst:SetAlpha(burstPreview and 0.45 or 1)
        frame.burst:Show()
        if burstPreview then
            frame.burst.pulse:Stop()
        elseif not frame.burst.pulse:IsPlaying() then
            frame.burst.pulse:Play()
        end
    else
        frame.burst.pulse:Stop()
        frame.burst:Hide()
    end

    -- bottom line: target time-to-die and time-until-OOM, colored per part
    local ttdStr
    if db.useTTD and valid then
        local ttd = TimeToDie()
        if ttd and ttd < 600 then
            local c = ttd < 8 and "|cffff3333" or (ttd < 20 and "|cffffd633" or "|cffe6e6e6")
            ttdStr = c .. "TTD " .. FormatTime(ttd) .. "|r"
        end
    end
    local oomStr
    if db.useOOM and UnitAffectingCombat("player") then
        local ttoom = TimeToOOM()
        if ttoom and ttoom < 600 then
            local c = ttoom < 10 and "|cffff3333" or (ttoom < 30 and "|cffffd633" or "|cffe6e6e6")
            oomStr = string.format("%sOOM %d:%02d|r", c, math.floor(ttoom / 60), math.floor(ttoom % 60))
        end
    end
    if ttdStr or oomStr then
        frame.oomText:SetText(ttdStr and oomStr and (ttdStr .. "  " .. oomStr) or ttdStr or oomStr)
        frame.oomText:SetAlpha(1)
        frame.oomText:Show()
    elseif not db.locked then
        -- unlocked placement preview
        frame.oomText:SetText("|cffe6e6e6TTD 14  OOM 1:42|r")
        frame.oomText:SetAlpha(0.45)
        frame.oomText:Show()
    else
        frame.oomText:Hide()
    end

    UpdateDots()
end

--------------------------------------------------------------------------
-- Events / OnUpdate
--------------------------------------------------------------------------

local elapsed = 0
frame:SetScript("OnUpdate", function(_, e)
    elapsed = elapsed + e
    if elapsed >= 0.1 then
        elapsed = 0
        UpdateDisplay()
    end
end)

-- The 10 Hz OnUpdate above is the sole display driver; events only refresh
-- caches (or, for target swaps, trigger one immediate update for snappiness).
-- High-frequency combat events like UNIT_AURA are deliberately not watched —
-- the next tick picks those changes up within 100ms at no extra cost.
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("SPELLS_CHANGED")
-- always on (not just in combat) so mob lifetime learning sees fights
-- that started before the player's own combat did
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
if not IS_PRIEST then
    events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    -- equipment data isn't reliable until PLAYER_ENTERING_WORLD, so the
    -- T5 scan from ADDON_LOADED gets a login-complete redo
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
end
events:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        LoadDB()
        RefreshKnown()
        RefreshT5()
        LayoutDots()
        playerGUID = UnitGUID("player")
        frame:ClearAllPoints()
        frame:SetPoint(db.point[1], UIParent, db.point[4] or db.point[1], db.point[2], db.point[3])
        frame:SetScale(db.scale)
        frame:EnableMouse(not db.locked)
        events:UnregisterEvent("ADDON_LOADED")
        UpdateDisplay()
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateDisplay()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- combat just started: drop idle-time samples so the drain rate
        -- reflects the fight, not the pre-pull standing around
        OOMReset()
        StartReport()
    elseif event == "PLAYER_REGEN_ENABLED" then
        LifePrune()
        FinishReport()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HandleCombatLog(CombatLogGetCurrentEventInfo())
    elseif event == "SPELLS_CHANGED" then
        RefreshKnown()
        LayoutDots()
    elseif event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "PLAYER_ENTERING_WORLD" then
        RefreshT5()
        LayoutDots()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- arg3 is the rank-specific spell id; match by name
        local name = GetSpellInfo(arg3)
        if name then
            for key, sName in pairs(spellName) do
                if sName == name then
                    justCast[key] = GetTime()
                    justCastGUID[key] = UnitGUID("target")
                    if report.active and report.casts[key] then
                        report.casts[key] = report.casts[key] + 1
                    end
                    break
                end
            end
        end
    end
end)

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------

SLASH_NEXTCAST1 = "/nextcast"
SLASH_NEXTCAST2 = "/nc"
SlashCmdList.NEXTCAST = function(input)
    local cmd, arg = input:match("^(%S*)%s*(%S*)$")
    cmd = cmd:lower()

    if cmd == "unlock" then
        db.locked = false
        db.hidden = false
        frame:EnableMouse(true)
        Print("Unlocked — drag the box to move it. /nc lock when done.")
    elseif cmd == "lock" then
        db.locked = true
        frame:EnableMouse(false)
        Print("Locked in place.")
    elseif cmd == "hide" then
        db.hidden = true
        Print("Hidden. /nc show to bring it back.")
    elseif cmd == "show" then
        db.hidden = false
        Print("Shown.")
    elseif cmd == "reset" then
        db.point = { defaults.point[1], defaults.point[2], defaults.point[3] }
        frame:ClearAllPoints()
        frame:SetPoint(db.point[1], UIParent, db.point[1], db.point[2], db.point[3])
        Print("Position reset.")
    elseif cmd == "scale" then
        local n = tonumber(arg)
        if n and n >= 0.5 and n <= 3 then
            db.scale = n
            frame:SetScale(n)
            Print("Scale set to " .. n .. ".")
        else
            Print("Usage: /nc scale 0.5–3")
        end
    -- priest-only toggles fall through to the help text on a druid
    elseif cmd == "swd" and IS_PRIEST then
        db.useSWD = not db.useSWD
        Print("Shadow Word: Death suggestions " .. (db.useSWD and "|cff00ff00on|r" or "|cffff0000off|r") .. ".")
    elseif cmd == "ve" and IS_PRIEST then
        db.useVE = not db.useVE
        LayoutDots()
        Print("Vampiric Embrace in the boss rotation " .. (db.useVE and "|cff00ff00on|r" or "|cffff0000off|r") .. ".")
    elseif cmd == "racial" and IS_PRIEST then
        db.useRacial = not db.useRacial
        LayoutDots()
        Print("Racial DoT suggestions (Devouring Plague/Starshards) " .. (db.useRacial and "|cff00ff00on|r" or "|cffff0000off|r") .. ".")
    elseif cmd == "focus" and IS_PRIEST then
        db.useFocus = not db.useFocus
        Print("Inner Focus pairing alerts " .. (db.useFocus and "|cff00ff00on|r" or "|cffff0000off|r") .. ".")
    elseif cmd == "ttd" then
        db.useTTD = not db.useTTD
        Print("Time-to-die display " .. (db.useTTD and "|cff00ff00on|r" or "|cffff0000off|r") .. ".")
    elseif cmd == "report" then
        db.useReport = not db.useReport
        Print("Post-fight reports " .. (db.useReport and "|cff00ff00on|r" or "|cffff0000off|r") .. ".")
    elseif cmd == "mana" or cmd == "fiend" then -- "fiend" kept as an alias
        db.useFiend = not db.useFiend
        Print("Low-mana cooldown (" .. (IS_PRIEST and "Shadowfiend" or "Innervate") .. ") suggestions " .. (db.useFiend and "|cff00ff00on|r" or "|cffff0000off|r") .. ".")
    elseif cmd == "lust" then
        db.useLust = not db.useLust
        Print("Potion/trinket alerts during Bloodlust/Heroism " .. (db.useLust and "|cff00ff00on|r" or "|cffff0000off|r") .. ".")
    elseif cmd == "clip" and IS_PRIEST then
        db.useClip = not db.useClip
        Print("Mind Flay clip indicator " .. (db.useClip and "|cff00ff00on|r" or "|cffff0000off|r") .. ".")
    elseif cmd == "oom" then
        db.useOOM = not db.useOOM
        Print("Time-until-OOM display " .. (db.useOOM and "|cff00ff00on|r" or "|cffff0000off|r") .. ".")
    else
        Print("Commands:")
        Print("  /nc unlock — move the box (then /nc lock)")
        Print("  /nc hide | show — hide or show the box")
        Print("  /nc reset — reset position")
        Print("  /nc scale <0.5–3> — resize")
        if IS_PRIEST then
            Print("  /nc swd — toggle Shadow Word: Death suggestions")
            Print("  /nc ve — add Vampiric Embrace to the boss rotation (off by default)")
            Print("  /nc racial — toggle racial DoT suggestions (DP/Starshards)")
            Print("  /nc focus — toggle Inner Focus pairing alerts")
            Print("  /nc clip — toggle the Mind Flay clip indicator")
        end
        Print("  /nc mana — toggle the low-mana cooldown suggestion (" .. (IS_PRIEST and "Shadowfiend" or "Innervate") .. ")")
        Print("  /nc lust — toggle potion/trinket alerts during Lust/Heroism")
        Print("  /nc oom — toggle the time-until-OOM display")
        Print("  /nc ttd — toggle the target time-to-die display")
        Print("  /nc report — toggle post-fight reports")
    end
    UpdateDisplay()
end
