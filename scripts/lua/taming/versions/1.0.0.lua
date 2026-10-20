-- @name    Taming
-- @author  LandorGerrano
-- @version 1.0.0
-- @tags    helpers

Messages.Print("=================================",60)
Messages.Print("Tamer Assistant Script v3.2.0",68)
Messages.Print("Status: Scanning for nearby creatures",89)
Messages.Print("=================================",60)

local autoRelease=true
local showAlreadyTamedOverhead=true
local repeatAfterTame=true
local showStatusMessages=true
local statusMessageInterval=5
local releaseGumpId=3432224886
local releaseButtonId=1
local releaseScanRange=12
local tameRange=2
local ignoreScanRange=10
local releaseRetryDelay=2

TamedSerials=TamedSerials or {}
PendingReleases=PendingReleases or {}

local tamedShownCache={}
local tameSkipShownCache={}
local lastStatusPrint=os.clock()
local tamedCount=0

local function FollowerCount()
    local ok,value=pcall(function() return Player.Followers end)
        if ok and tonumber(value) then return tonumber(value) end
        ok,value=pcall(function() return Player.FollowerCount end)
            if ok and tonumber(value) then return tonumber(value) end
            return nil
        end

        local function FindVisibleMobile(serial,range)
            local nearby=Mobiles.FindByFilter({rangemax=range,dead=false,human=false}) or {}
            for _,mob in ipairs(nearby) do
                if mob.Serial==serial then return mob end
            end
            return nil
        end

        local function CloseReleaseGump()
            if Gumps.HasGump(releaseGumpId) then
                Gumps.Close(releaseGumpId)
                Pause(150)
            end
        end

        local function HandleReleaseTarget(serial)
            if Targeting.WaitForTarget(250) then
                local mob=FindVisibleMobile(serial,releaseScanRange)
                if not mob then
                    -- Do not consume the cursor on a wrong mobile. Self-target clears
                    -- the stale cursor and the release stays queued for a later retry.
                    pcall(function() Targeting.TargetSerial(Player.Serial) end)
                        Pause(150)
                        return false
                    end
                    pcall(function() Targeting.TargetSerial(serial) end)
                        Pause(250)
                        return true
                    end
                    return false
                end

                local function WaitForFollowerDrop(beforeCount,timeoutMs)
                    if beforeCount==nil then return nil,nil end
                    local waited=0
                    while waited<timeoutMs do
                        local now=FollowerCount()
                        if now~=nil and now<beforeCount then return true,now end
                        Pause(100)
                        waited=waited+100
                    end
                    return false,FollowerCount()
                end

                local function QueueRelease(mob)
                    PendingReleases[mob.Serial]={
                        serial=mob.Serial,
                        name=mob.Name or "",
                        nextTry=0,
                        attempts=0,
                        followersAfterTame=FollowerCount()
                    }
                end

                local function TryPendingRelease(entry)
                    local mob=FindVisibleMobile(entry.serial,releaseScanRange)
                    if not mob then
                        entry.nextTry=os.clock()+releaseRetryDelay
                        return false,"out_of_range"
                    end

                    local before=FollowerCount()
                    if entry.followersAfterTame and before and before<entry.followersAfterTame then
                        return true,"already_released"
                    end

                    entry.attempts=(entry.attempts or 0)+1
                    entry.name=mob.Name or entry.name or ""
                    Messages.Print("Release retry "..entry.attempts..": "..entry.name,20)

                    CloseReleaseGump()
                    Player.Say(entry.name.." release")

                    -- Some release commands open a target cursor instead of the confirmation
                    -- gump. If that happens, explicitly target the queued animal by serial.
                    HandleReleaseTarget(entry.serial)

                    if not Gumps.WaitForGump(releaseGumpId,3500) then
                        -- The target cursor can arrive late, so check once more before giving up.
                        if HandleReleaseTarget(entry.serial) then
                            Gumps.WaitForGump(releaseGumpId,2500)
                        end
                    end

                    if Gumps.HasGump(releaseGumpId) then
                        local pressed=pcall(function() Gumps.PressButton(releaseGumpId,releaseButtonId) end)
                            if pressed then
                                Pause(350)
                                local dropped,after=WaitForFollowerDrop(before,5000)
                                if dropped==true then
                                    Messages.Print("Release confirmed. Followers: "..before.." -> "..after,68)
                                    return true,"followers_dropped"
                                elseif dropped==nil then
                                    Messages.Print("Release gump confirmed; follower counter unavailable.",68)
                                    return true,"gump_confirmed"
                                end
                            end
                        end

                        -- Clean up any target left by an interrupted or out-of-range command.
                        if Targeting.WaitForTarget(150) then
                            pcall(function() Targeting.TargetSerial(Player.Serial) end)
                            end
                            CloseReleaseGump()
                            entry.nextTry=os.clock()+releaseRetryDelay
                            Messages.Print("Release not confirmed; kept in retry queue.",38)
                            return false,"not_confirmed"
                        end

                        local function ProcessPendingReleases()
                            for serial,entry in pairs(PendingReleases) do
                                if os.clock()>=(entry.nextTry or 0) then
                                    local released,reason=TryPendingRelease(entry)
                                    if released then
                                        PendingReleases[serial]=nil
                                        Messages.Print("Pending release completed: "..(entry.name or tostring(serial)),68)
                                    elseif reason=="out_of_range" then
                                        -- Keep queued silently until this exact serial becomes visible.
                                    end
                                    return true
                                end
                            end
                            return false
                        end

                        Journal.Clear()

                        while true do
                            -- Releases always have priority over finding a new animal. A failed release
                            -- is never forgotten merely because the animal ran away or pathing failed.
                            local processingRelease=autoRelease and ProcessPendingReleases()

                            if showAlreadyTamedOverhead then
                                local nearby=Mobiles.FindByFilter({rangemax=ignoreScanRange,dead=false,human=false}) or {}
                                local now=os.clock()
                                for _,mob in ipairs(nearby) do
                                    if TamedSerials[mob.Serial] then
                                        local lastShown=tamedShownCache[mob.Serial] or 0
                                        if now-lastShown>=3 then
                                            local text=PendingReleases[mob.Serial] and "Tamed - release pending" or "Already Tamed... Skipping"
                                            Messages.Overhead(text,38,mob.Serial)
                                            tamedShownCache[mob.Serial]=now
                                        end
                                    end
                                end
                            end

                            if processingRelease then
                                Pause(150)
                            else
                                local all=Mobiles.FindByFilter({rangemax=tameRange,dead=false,human=false}) or {}
                                local untamed={}
                                for _,mob in ipairs(all) do
                                    if not TamedSerials[mob.Serial] and not PendingReleases[mob.Serial] then
                                        table.insert(untamed,mob)
                                    end
                                end
                                table.sort(untamed,function(a,b) return a.Distance<b.Distance end)

                                    if showStatusMessages and os.clock()-lastStatusPrint>=statusMessageInterval then
                                        Messages.Print("Still scanning for tameable creatures...",89)
                                        lastStatusPrint=os.clock()
                                    end

                                    if #untamed==0 then
                                        Pause(200)
                                    else
                                        local target=untamed[1]
                                        local success=false
                                        Messages.Print("Attempting to tame: "..(target.Name or "Unknown"),33)

                                        for retry=1,3 do
                                            -- Re-check range before every attempt. Do not start a skill if
                                            -- the exact serial has already run away.
                                            local visible=FindVisibleMobile(target.Serial,tameRange)
                                            if not visible then
                                                Messages.Print("Target left taming range; will scan again later.",38)
                                                break
                                            end

                                            Journal.Clear()
                                            Skills.Use("Animal Taming")
                                            if Targeting.WaitForTarget(2000) then
                                                Targeting.TargetSerial(target.Serial)
                                            else
                                                Messages.Print("Taming target cursor failed.",38)
                                                break
                                            end

                                            local elapsed=0
                                            while elapsed<15000 do
                                                if Journal.Contains("It seems to accept you as master") or Journal.Contains("That wasn't even challenging.") then
                                                    success=true
                                                    tamedCount=tamedCount+1
                                                    TamedSerials[target.Serial]={name=target.Name,time=os.time()}
                                                    Messages.Print("Tamed successfully! ("..tamedCount.." total)",68)
                                                    if autoRelease then
                                                        QueueRelease(target)
                                                        Messages.Print("Release queued for exact serial.",20)
                                                        -- Try immediately, but leave the entry queued if the
                                                        -- animal moves or the confirmation cannot complete.
                                                        ProcessPendingReleases()
                                                    end
                                                    break
                                                elseif Journal.Contains("That animal looks tame already.") then
                                                    TamedSerials[target.Serial]={name=target.Name,time=os.time()}
                                                    local now=os.clock()
                                                    if now-(tameSkipShownCache[target.Serial] or 0)>=3 then
                                                        Messages.Print("Already tame - skipping target.",38)
                                                        tameSkipShownCache[target.Serial]=now
                                                    end
                                                    break
                                                elseif Journal.Contains("You fail to tame the creature.") then
                                                    Messages.Print("Taming failed. Trying again...",20)
                                                    break
                                                elseif Journal.Contains("You seem to anger the beast") then
                                                    Messages.Print("The beast was angered.",20)
                                                    Pause(200)
                                                    break
                                                elseif Journal.Contains("That is too far away.") then
                                                    Messages.Print("Target moved out of range; attempt aborted safely.",38)
                                                    break
                                                end
                                                Pause(50)
                                                elapsed=elapsed+50
                                            end
                                            if success then break end
                                        end

                                        if success then
                                            Messages.Print("Tame complete; release remains monitored.",68)
                                            if not repeatAfterTame then return end
                                        end
                                        Pause(250)
                                    end
                                end
                            end
