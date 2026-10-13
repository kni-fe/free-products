-- __                  __   ______                      __                     
--|  \                |  \ /      \                    |  \                    
-- | $$   __  _______   \$$|  $$$$$$\ ______            | $$ __    __   ______  
-- | $$  /  \|       \ |  \| $$_  \$$/      \           | $$|  \  |  \ |      \ 
-- | $$_/  $$| $$$$$$$\| $$| $$ \   |  $$$$$$\          | $$| $$  | $$  \$$$$$$
-- | $$   $$ | $$  | $$| $$| $$$$   | $$    $$          | $$| $$  | $$ /      $$
-- | $$$$$$\ | $$  | $$| $$| $$     | $$$$$$$$ __       | $$| $$__/ $$|  $$$$$$$
-- | $$  \$$\| $$  | $$| $$| $$      \$$     \|  \      | $$ \$$    $$ \$$    $$
--  \$$   \$$ \$$   \$$ \$$ \$$       \$$$$$$$ \$$       \$$  \$$$$$$   \$$$$$$$

local SCRIPT_ID = "knife_free_products"

do
    for _, id in ipairs({ SCRIPT_ID }) do
        local old = rawget(getgenv(), id)
        if type(old) == "table" and type(old.kill) == "function" then
            pcall(old.kill)
        end
    end
end

local Library = getgenv().AirFlow or getgenv().Library
if type(Library) ~= "table" or type(Library.CreateWindow) ~= "function" then
    if typeof(readfile) == "function" then
        for _, path in ipairs({ "AirFlowLibrary.luau", "Example.luau", "AirFlow.luau" }) do
            local ok, body = pcall(readfile, path)
            if ok and type(body) == "string" then
                local cut = body:find("return Library\nend%)%(%)")
                if cut then body = body:sub(1, cut + #"return Library\nend)()") end
                local fn = loadstring(body)
                if fn then
                    local ok2, res = pcall(fn)
                    if ok2 and type(res) == "table" and res.CreateWindow then
                        Library, getgenv().AirFlow = res, res
                        break
                    end
                    if type(getgenv().AirFlow) == "table" then
                        Library = getgenv().AirFlow
                        break
                    end
                end
            end
        end
    end
end
if type(Library) ~= "table" or type(Library.CreateWindow) ~= "function" then
    error("[knife] need airflow first")
end

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local SUPPORTED_GAMES = {
    { id = 115283052130481, name = "🔥Phonk Troll Tower🎵" },
    { id = 101754965994520, name = "Auto Wallhop Troll Tower 🔁" },
    { id = 84830451404494,  name = "[🏜️] Fly Tower" },
    { id = 92432535588391,  name = "Swing Tower" },
    { id = 105583156670137, name = "Balagbag Na Laser Tower" },
    { id = 77451737406508,  name = "Nakakainis Na Laser Tower" },
    { id = 131282168059446, name = "[✨1 ROBUX] Tower For Admin 6" },
    { id = 91667860784383,  name = "[30k+] PH Seaside Hangout" },
    { id = 114170744736335, name = "my block lad" },
    { id = 105306675431828, name = "1v1 IQ Race 🧠" },
    { id = 15789921122,     name = "🎈FUNNIEST EASY OBBY!" },
}

local placeMap = {} -- label -> placeId

local function placeLabel(entry)
    local tag = entry.id == game.PlaceId and " · HERE" or ""
    return (entry.name or ("Place " .. tostring(entry.id))) .. tag
end

local function supportedLabels()
    local opts = {}
    for _, entry in ipairs(SUPPORTED_GAMES) do
        table.insert(opts, placeLabel(entry))
    end
    return opts
end

local function rebuildPlaceMap(opts)
    table.clear(placeMap)
    for i, entry in ipairs(SUPPORTED_GAMES) do
        if opts and opts[i] then
            placeMap[opts[i]] = entry.id
        end
    end
end

local knownKinds = {}
local catalog = { gamepasses = {}, products = {} }
local nameById = {}
local priceById = {}
local excluded = {}

local State = {
    loop = false,
    loopDelay = 0.35,
    loopTarget = "Gamepasses",
    singleLoop = false,
    singleLoopId = nil,
    loopDelaySingle = 0.35,
    forceKind = "Auto",
    fireMode = "Classic", -- Classic | AllKinds
    spoofOwned = false,

    usePriceFilter = false,
    maxRobux = 0,
    log = {},
    logIndex = {},
    productLabel = nil,
    logLabel = nil,
    placeLabel = nil,
    productMap = {},
    logMap = {},
    placeMap = {},
    dead = false,
    window = nil,
}

local UI = {
    productDrop = nil,
    logDrop = nil,
    placeDrop = nil,
}

local function notify(title, content, typ)
    pcall(function()
        Library:Notify({
            Title = title or "knife.lua | free products",
            Content = content or "",
            Type = typ or "Success",
            Duration = 3,
        })
    end)
end

local function copyText(text)
    if typeof(setclipboard) == "function" then return pcall(setclipboard, tostring(text)) end
    if typeof(toclipboard) == "function" then return pcall(toclipboard, tostring(text)) end
    return false
end

local fireMap = {
    Product = function(id)
        MarketplaceService:SignalPromptProductPurchaseFinished(LocalPlayer.UserId, id, true)
    end,
    Gamepass = function(id)
        MarketplaceService:SignalPromptGamePassPurchaseFinished(LocalPlayer, id, true)
    end,
    Asset = function(id)
        MarketplaceService:SignalPromptPurchaseFinished(LocalPlayer, id, true)
    end,
    Bundle = function(id)
        MarketplaceService:SignalPromptBundlePurchaseFinished(LocalPlayer, id, true)
    end,
}

local function getInfo(kind, id)
    local types = {
        Product = Enum.InfoType.Product,
        Gamepass = Enum.InfoType.GamePass,
        Asset = Enum.InfoType.Asset,
        Bundle = Enum.InfoType.Bundle,
    }
    local t = types[kind]
    if not t then return nil end
    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(tonumber(id), t)
    end)
    return ok and info or nil
end

local function rememberName(id, name, kind, price)
    id = tostring(id)
    if name and name ~= "" then nameById[id] = name end
    if kind then knownKinds[id] = kind end
    if price ~= nil then priceById[id] = price end
end

local function displayName(id)
    return nameById[tostring(id)] or ("#" .. tostring(id))
end

local function detectKind(id)
    local known = knownKinds[tostring(id)]
    if known and fireMap[known] then
        return known
    end
    for _, kind in ipairs({ "Product", "Gamepass", "Asset" }) do
        if getInfo(kind, id) then
            knownKinds[tostring(id)] = kind
            return kind
        end
    end
    return "Product"
end

local function doFire(id, kindOverride)
    id = tonumber(id)
    if not id then return false, "bad id" end
    if excluded[tostring(id)] then return false, "excluded" end
    local kind = kindOverride or detectKind(id)
    if not fireMap[kind] then kind = "Product" end

    if not State or State.fireMode ~= "AllKinds" then
        local ok, err = pcall(fireMap[kind], id)
        if not ok then return false, err end
        knownKinds[tostring(id)] = kind
        return true, kind
    end

    for _, k in ipairs({ kind, "Gamepass", "Product", "Asset", "Bundle" }) do
        pcall(fireMap[k], id)
    end
    knownKinds[tostring(id)] = kind
    return true, kind
end

local function fireId(id, kindOverride)
    id = tonumber(id)
    if not id then
        notify("bad id", "Pick something from the list", "Error")
        return false
    end
    if excluded[tostring(id)] then
        local ex = excluded[tostring(id)]
        notify("skipped", (ex and ex.name or displayName(id)) .. " · " .. id, "Warning")
        return false
    end
    local force = State and State.forceKind
    if force and force ~= "Auto" then
        kindOverride = force
    end
    local ok, kind = doFire(id, kindOverride)
    if ok then
        notify("ok", ("%s · %s · %d"):format(tostring(kind), displayName(id), id), "Success")
        return true
    end
    notify("failed", tostring(kind), "Error")
    return false
end

local function setExclude(id, on, name, kind)
    id = tostring(id)
    if on then
        excluded[id] = { name = name or displayName(id), kind = kind or knownKinds[id] or "Gamepass" }
    else
        excluded[id] = nil
    end
end

local function priceOk(item)
    if not State.usePriceFilter then return true end
    local p = tonumber(item.price)
    if p == nil then return true end
    if State.maxRobux > 0 and p > State.maxRobux then return false end
    return true
end

local function listForTarget(target)
    target = target or State.loopTarget
    local list = {}
    local function push(item)
        if not item or not item.id then return end
        if excluded[tostring(item.id)] then return end
        if not priceOk(item) then return end
        table.insert(list, item)
    end
    if target == "Gamepasses" or target == "Both" then
        for _, item in ipairs(catalog.gamepasses) do push(item) end
    end
    if target == "Products" or target == "Both" then
        for _, item in ipairs(catalog.products) do push(item) end
    end
    return list
end

local function fireAll(target)
    local list = listForTarget(target)
    if #list == 0 then
        notify("empty", "Empty after excludes / filter", "Warning")
        return
    end
    local n = 0
    for _, item in ipairs(list) do
        if State.dead then break end
        if doFire(item.id, State.forceKind ~= "Auto" and State.forceKind or item.kind) then
            n += 1
        end
        task.wait(0.05)
    end
    notify("batch", ("%d / %d"):format(n, #list), "Success")
end

local function batchLoopWorker()
    while State.loop and not State.dead do
        local list = listForTarget()
        if #list == 0 then
            State.loop = false
            notify("loop", "Stopped — empty", "Warning")
            break
        end
        for _, item in ipairs(list) do
            if not State.loop or State.dead then break end
            doFire(item.id, State.forceKind ~= "Auto" and State.forceKind or item.kind)
            task.wait(math.max(0.05, State.loopDelay))
        end
    end
end

local function singleLoopWorker()
    while State.singleLoop and not State.dead do
        local id = State.singleLoopId
        if not id then
            State.singleLoop = false
            notify("loop", "No id selected", "Warning")
            break
        end
        local kind = knownKinds[tostring(id)]
        doFire(id, kind)
        task.wait(math.max(0.05, State.loopDelaySingle))
    end
end

local function productLabelOf(item)
    local r = item.price and ("R$" .. tostring(item.price)) or "—"
    local ex = excluded[tostring(item.id)] and " [EX]" or ""
    return string.format("%s · %s · %s%s", item.name or "?", r, tostring(item.id), ex)
end

local function refreshProductDrop()
    local opts, map = {}, {}
    for _, p in ipairs(catalog.gamepasses) do
        local label = productLabelOf(p)
        table.insert(opts, label)
        map[label] = p
    end
    for _, p in ipairs(catalog.products) do
        local label = productLabelOf(p)
        table.insert(opts, label)
        map[label] = p
    end
    State.productMap = map
    if UI.productDrop and UI.productDrop.Refresh then
        UI.productDrop:Refresh(opts, false, true)
        if opts[1] then
            State.productLabel = opts[1]
            pcall(function() UI.productDrop:Set(opts[1], true) end)
        end
    end
end

local function logLabelOf(e)
    local x = e.count > 1 and (" ×" .. e.count) or ""
    local r = e.price and (" · R$" .. e.price) or ""
    local ex = excluded[tostring(e.id)] and " [EX]" or ""
    return string.format("%s%s · %s · %s%s%s", e.name or "?", x, e.kind, tostring(e.id), r, ex)
end

local function refreshLogDrop()
    local opts, map = {}, {}
    for _, e in ipairs(State.log) do
        local label = logLabelOf(e)
        table.insert(opts, label)
        map[label] = e
    end
    State.logMap = map
    if UI.logDrop and UI.logDrop.Refresh then
        UI.logDrop:Refresh(opts, false, true)
        if opts[1] then
            State.logLabel = opts[1]
            pcall(function() UI.logDrop:Set(opts[1], true) end)
        end
    end
end

local function addLog(kind, id, name, price)
    rememberName(id, name, kind, price)
    local key = tostring(kind) .. ":" .. tostring(id)
    local existing = State.logIndex[key]
    if existing then
        existing.count += 1
        existing.t = os.clock()
        if name then existing.name = name end
        if price ~= nil then existing.price = price end
        for i, e in ipairs(State.log) do
            if e == existing then table.remove(State.log, i) break end
        end
        table.insert(State.log, 1, existing)
        refreshLogDrop()
        return existing
    end
    local entry = {
        key = key, kind = kind, id = id,
        name = name or displayName(id), price = price, count = 1, t = os.clock(),
    }
    State.logIndex[key] = entry
    table.insert(State.log, 1, entry)
    while #State.log > 80 do
        local rem = table.remove(State.log)
        if rem and State.logIndex[rem.key] == rem then State.logIndex[rem.key] = nil end
    end
    refreshLogDrop()
    return entry
end

local function currentProduct()
    local label = State.productLabel
    if label and State.productMap[label] then return State.productMap[label] end
    local first = catalog.gamepasses[1] or catalog.products[1]
    return first
end

local function currentLog()
    local label = State.logLabel
    if label and State.logMap[label] then return State.logMap[label] end
    return State.log[1]
end

local function currentPlaceId()
    local label = State and State.placeLabel
    if label and placeMap[label] then return placeMap[label] end
    local any = next(placeMap)
    if any then return placeMap[any] end
    return SUPPORTED_GAMES[1] and SUPPORTED_GAMES[1].id
end

local httpRequest = (typeof(request) == "function" and request)
    or (typeof(http_request) == "function" and http_request)

local function getJson(url)
    local body
    if httpRequest then
        local ok, res = pcall(httpRequest, { Url = url, Method = "GET" })
        if ok and type(res) == "table" and (res.StatusCode == 200 or res.Success) then
            body = res.Body
        end
    end
    if not body then
        local ok, res = pcall(function() return game:HttpGet(url) end)
        if ok then body = res end
    end
    if type(body) ~= "string" or body == "" then return nil end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, body)
    return ok and data or nil
end

local function nonEmpty(s)
    return type(s) == "string" and s ~= "" and s or nil
end

local function fetchGamepasses(universeId)
    local sources = {
        {
            hosts = { "apis.roblox.com", "apis.roproxy.com" },
            url = function(host, uid, cursor)
                local page = cursor and "&pageToken=" .. HttpService:UrlEncode(cursor) or ""
                return ("https://%s/game-passes/v1/universes/%d/game-passes?passView=Full&pageSize=100%s"):format(host, uid, page)
            end,
            parse = function(d)
                if type(d) ~= "table" or type(d.gamePasses) ~= "table" then return nil end
                local out = {}
                for _, p in ipairs(d.gamePasses) do
                    local pi = type(p.priceInformation) == "table" and p.priceInformation or {}
                    table.insert(out, {
                        id = p.id or p.gamePassId,
                        name = p.displayName or p.name,
                        price = p.price or pi.defaultPriceInRobux or pi.price,
                        kind = "Gamepass",
                    })
                end
                return out, nonEmpty(d.nextPageToken)
            end,
        },
        {
            hosts = { "games.roblox.com", "games.roproxy.com" },
            url = function(host, uid, cursor)
                local page = cursor and "&cursor=" .. HttpService:UrlEncode(cursor) or ""
                return ("https://%s/v1/games/%d/game-passes?limit=100&sortOrder=Asc%s"):format(host, uid, page)
            end,
            parse = function(d)
                if type(d) ~= "table" or type(d.data) ~= "table" then return nil end
                local out = {}
                for _, p in ipairs(d.data) do
                    table.insert(out, {
                        id = p.id, name = p.displayName or p.name, price = p.price, kind = "Gamepass",
                    })
                end
                return out, nonEmpty(d.nextPageCursor)
            end,
        },
    }
    for _, source in ipairs(sources) do
        for _, host in ipairs(source.hosts) do
            local all, cursor = source.parse(getJson(source.url(host, universeId)))
            if all then
                local pages = 1
                while cursor and pages < 25 do
                    local more, nextCursor = source.parse(getJson(source.url(host, universeId, cursor)))
                    if not more then break end
                    for _, item in ipairs(more) do table.insert(all, item) end
                    cursor = nextCursor
                    pages += 1
                end
                return all
            end
        end
    end
    return nil
end

local function fetchProducts()
    local ok, pages = pcall(function()
        return MarketplaceService:GetDeveloperProductsAsync()
    end)
    if not ok or not pages then return nil end
    local out = {}
    while true do
        for _, p in ipairs(pages:GetCurrentPage()) do
            table.insert(out, {
                id = p.ProductId or p.productId or p.DeveloperProductId,
                name = p.Name or p.name or p.DisplayName,
                price = p.PriceInRobux or p.price,
                kind = "Product",
            })
        end
        if pages.IsFinished then break end
        if not pcall(function() pages:AdvanceToNextPageAsync() end) then break end
    end
    return out
end

local function scanCatalog()
    notify("scan", "Loading…", "Warning")
    catalog.gamepasses, catalog.products = {}, {}
    local passes, products
    task.spawn(function()
        local uid = game.GameId
        if not uid or uid == 0 then
            local okU, body = pcall(function()
                return game:HttpGet("https://apis.roblox.com/universes/v1/places/" .. game.PlaceId .. "/universe")
            end)
            if not okU then
                okU, body = pcall(function()
                    return game:HttpGet("https://apis.roproxy.com/universes/v1/places/" .. game.PlaceId .. "/universe")
                end)
            end
            if okU and type(body) == "string" then
                local okJ, data = pcall(HttpService.JSONDecode, HttpService, body)
                if okJ and data and data.universeId then
                    uid = data.universeId
                end
            end
        end
        passes = fetchGamepasses(uid) or {}
    end)
    task.spawn(function() products = fetchProducts() or {} end)
    while passes == nil or products == nil do
        if State.dead then return end
        task.wait()
    end
    local function byPrice(a, b)
        return (tonumber(a.price) or 1e9) < (tonumber(b.price) or 1e9)
    end
    table.sort(passes, byPrice)
    table.sort(products, byPrice)
    for _, p in ipairs(passes) do
        if p.id then
            rememberName(p.id, p.name, "Gamepass", p.price)
            table.insert(catalog.gamepasses, p)
        end
    end
    for _, p in ipairs(products) do
        if p.id then
            rememberName(p.id, p.name, "Product", p.price)
            table.insert(catalog.products, p)
        end
    end
    refreshProductDrop()
    notify("scanned", ("%d passes · %d products"):format(#catalog.gamepasses, #catalog.products), "Success")
end

pcall(function()
    MarketplaceService.PromptGamePassPurchaseRequested:Connect(function(player, passId)
        if player ~= LocalPlayer then return end
        local info = getInfo("Gamepass", passId)
        addLog("Gamepass", passId, info and info.Name, info and (info.PriceInRobux or info.Price))
    end)
end)
pcall(function()
    MarketplaceService.PromptProductPurchaseRequested:Connect(function(player, productId)
        if player ~= LocalPlayer then return end
        local info = getInfo("Product", productId)
        addLog("Product", productId, info and info.Name, info and info.PriceInRobux)
    end)
end)
pcall(function()
    MarketplaceService.PromptPurchaseRequested:Connect(function(player, assetId)
        if player ~= LocalPlayer then return end
        addLog("Asset", assetId)
    end)
end)

pcall(function() Library:LoadFont({ Name = "ValleySans" }) end)

local Window = Library:CreateWindow({
    Name = "knife.lua | free products",
    LoadingSubtitle = "",
    ToggleUIKeybind = "RightShift",
    ConfigurationSaving = { Enabled = true, FolderName = "knife_fp" },
    ToggleButton = { Platform = "Both", Icon = "shopping-bag" },
    Backdrop = { Weather = "None", Tint = 0 },
    Home = {
        Tier = "Local",
        Stats = { "Players", "Session", "FPS", "Ping" },
    },
})
State.window = Window
pcall(function() Window:SetBackdrop(false) end)
pcall(function() Window:SetBackdropTint(0) end)

local TabProducts = Window:CreateTab({ Name = "shop", Icon = "ticket" })
local SubP = TabProducts:CreateSubTab({ Name = "main" })
local GList = SubP:AddLeftGroupbox({ Name = "stuff", Icon = "list" })
local GAct = SubP:AddRightGroupbox({ Name = "do it", Icon = "zap" })

GList:CreateButton({
    Name = "refresh",
    Style = "Primary",
    Icon = "search",
    Callback = function() task.spawn(scanCatalog) end,
})

UI.productDrop = GList:CreateDropdown({
    Name = "item",
    Desc = "type to search",
    Options = {},
    Flag = "PF_ProductPick",
    Callback = function(opt)
        local label = type(opt) == "table" and opt[1] or opt
        State.productLabel = label
        local item = State.productMap[label]
        if item then
            State.singleLoopId = item.id
        end
    end,
})

GAct:CreateDropdown({
    Name = "mode",
    Desc = "classic is the normal one",
    Options = { "Classic", "AllKinds" },
    CurrentOption = "Classic",
    Flag = "PF_FireMode",
    Callback = function(o)
        State.fireMode = type(o) == "table" and o[1] or o
    end,
})
GAct:CreateToggle({
    Name = "Spoof ownership",
    Desc = "Client UserOwnsGamePass only — off by default",
    CurrentValue = false,
    Flag = "PF_SpoofOwn",
    Callback = function(v) State.spoofOwned = v end,
})
GAct:CreateDropdown({
    Name = "type",
    Options = { "Auto", "Gamepass", "Product", "Asset", "Bundle" },
    CurrentOption = "Auto",
    Flag = "PF_ForceKind",
    Callback = function(o)
        State.forceKind = type(o) == "table" and o[1] or o
    end,
})
GAct:CreateButton({
    Name = "buy",
    Style = "Primary",
    Icon = "flame",
    Callback = function()
        local p = currentProduct()
        if not p then return notify("buy", "Scan & pick a pass", "Warning") end
        fireId(p.id, p.kind)
    end,
})
GAct:CreateButton({
    Name = "copy id",
    Icon = "copy",
    Callback = function()
        local p = currentProduct()
        if p and copyText(p.id) then
            notify("copied", (p.name or "") .. " · " .. tostring(p.id), "Success")
        end
    end,
})
GAct:CreateButton({
    Name = "Exclude (won’t fire)",
    Callback = function()
        local p = currentProduct()
        if not p then return end
        local id = tostring(p.id)
        if excluded[id] then
            setExclude(id, false)
            notify("skip", "Removed · " .. (p.name or id), "Success")
        else
            setExclude(id, true, p.name, p.kind)
            notify("skipped", (p.name or id) .. " · " .. id, "Warning")
        end
        refreshProductDrop()
        refreshLogDrop()
    end,
})
GAct:CreateToggle({
    Name = "keep buying",
    Desc = "same item over and over",
    CurrentValue = false,
    Flag = "PF_SingleLoop",
    Callback = function(on)
        State.singleLoop = on
        local p = currentProduct()
        if p then State.singleLoopId = p.id end
        if on then
            if not State.singleLoopId then
                State.singleLoop = false
                return notify("loop", "Pick a pass first", "Warning")
            end
            task.spawn(singleLoopWorker)
            notify("loop", "ON · " .. displayName(State.singleLoopId), "Success")
        else
            notify("loop", "OFF", "Warning")
        end
    end,
})
GAct:CreateSlider({
    Name = "wait",
    Range = { 0.05, 5 },
    Increment = 0.05,
    Suffix = "s",
    CurrentValue = 0.35,
    Flag = "PF_SingleDelay",
    Callback = function(v) State.loopDelaySingle = v end,
})
GAct:CreateButton({
    Name = "all passes",
    Callback = function() task.spawn(function() fireAll("Gamepasses") end) end,
})
GAct:CreateButton({
    Name = "all products",
    Callback = function() task.spawn(function() fireAll("Products") end) end,
})
GAct:CreateParagraph({
    Title = "heads up",
    Content = "some games check on server so this wont give u the item. gamepasses work more often.",
})

local GEx = SubP:AddLeftGroupbox({ Name = "skipped", Icon = "ban" })
GEx:CreateStatusList({
    Name = "list",
    MaxRows = 5,
    EmptyText = "nothing here",
    UpdateRate = 0.5,
    Update = function()
        local rows = {}
        for id, meta in pairs(excluded) do
            rows[#rows + 1] = {
                Text = meta.name or displayName(id),
                Value = string.format("%s · %s", meta.kind or "?", id),
                Tone = "Warning",
            }
        end
        table.sort(rows, function(a, b) return a.Text < b.Text end)
        return rows
    end,
})
GEx:CreateButton({
    Name = "clear",
    Callback = function()
        table.clear(excluded)
        refreshProductDrop()
        refreshLogDrop()
        notify("skip", "Cleared", "Success")
    end,
})

local TabLog = Window:CreateTab({ Name = "prompts", Icon = "scroll-text" })
local SubL = TabLog:CreateSubTab({ Name = "main" })
local GLog = SubL:AddLeftGroupbox({ Name = "caught", Icon = "bell" })
local GLogA = SubL:AddRightGroupbox({ Name = "do it", Icon = "play" })

GLog:CreateParagraph({
    Title = "how",
    Content = "search, click, buy",
})

UI.logDrop = GLog:CreateDropdown({
    Name = "pick one",
    Desc = "search",
    Options = {},
    Flag = "PF_LogPick",
    Callback = function(opt)
        local label = type(opt) == "table" and opt[1] or opt
        State.logLabel = label
        local e = State.logMap[label]
        if e then State.singleLoopId = e.id end
    end,
})

GLogA:CreateButton({
    Name = "buy",
    Style = "Primary",
    Icon = "flame",
    Callback = function()
        local e = currentLog()
        if not e then return notify("log", "No prompts yet — open a purchase", "Warning") end
        fireId(e.id, e.kind)
    end,
})
GLogA:CreateButton({
    Name = "copy id",
    Icon = "copy",
    Callback = function()
        local e = currentLog()
        if e and copyText(e.id) then
            notify("copied", (e.name or "") .. " · " .. tostring(e.id), "Success")
        end
    end,
})
GLogA:CreateButton({
    Name = "Exclude (won’t fire)",
    Callback = function()
        local e = currentLog()
        if not e then return end
        local id = tostring(e.id)
        if excluded[id] then
            setExclude(id, false)
            notify("skip", "Removed · " .. (e.name or id), "Success")
        else
            setExclude(id, true, e.name, e.kind)
            notify("skipped", (e.name or id) .. " · " .. id, "Warning")
        end
        refreshLogDrop()
        refreshProductDrop()
    end,
})
GLogA:CreateToggle({
    Name = "keep buying",
    Desc = "Loops the selected log entry",
    CurrentValue = false,
    Flag = "PF_LogSingleLoop",
    Callback = function(on)
        State.singleLoop = on
        local e = currentLog()
        if e then State.singleLoopId = e.id end
        if on then
            if not State.singleLoopId then
                State.singleLoop = false
                return notify("loop", "Pick a log entry first", "Warning")
            end
            task.spawn(singleLoopWorker)
            notify("loop", "ON · " .. displayName(State.singleLoopId), "Success")
        end
    end,
})
GLogA:CreateSlider({
    Name = "wait",
    Range = { 0.05, 5 },
    Increment = 0.05,
    Suffix = "s",
    CurrentValue = 0.35,
    Flag = "PF_LogSingleDelay",
    Callback = function(v) State.loopDelaySingle = v end,
})
GLogA:CreateButton({
    Name = "buy all these",
    Callback = function()
        if #State.log == 0 then return notify("log", "Empty", "Warning") end
        local n = 0
        for _, e in ipairs(State.log) do
            if not excluded[tostring(e.id)] then
                if doFire(e.id, e.kind) then n += 1 end
                task.wait(0.08)
            end
        end
        notify("log", "Fired " .. n, "Success")
    end,
})
GLogA:CreateButton({
    Name = "wipe",
    Callback = function()
        table.clear(State.log)
        table.clear(State.logIndex)
        refreshLogDrop()
        notify("log", "Cleared", "Warning")
    end,
})

local TabSup = Window:CreateTab({ Name = "games", Icon = "gamepad-2" })
local SubSup = TabSup:CreateSubTab({ Name = "main" })
local GSup = SubSup:AddLeftGroupbox({ Name = "list", Icon = "gamepad-2" })
local GSupA = SubSup:AddRightGroupbox({ Name = "go", Icon = "log-in" })

local placeOpts = supportedLabels()
rebuildPlaceMap(placeOpts)
if State then State.placeLabel = placeOpts[1] end

UI.placeDrop = GSup:CreateDropdown({
    Name = "pick",
    Desc = "click one",
    Options = placeOpts,
    CurrentOption = placeOpts[1],
    Flag = "PF_PlacePick",
    Callback = function(opt)
        local label = type(opt) == "table" and opt[1] or opt
        if State then State.placeLabel = label end
    end,
})

local function gameNameOf(placeId)
    for _, e in ipairs(SUPPORTED_GAMES) do
        if e.id == placeId then return e.name end
    end
    return tostring(placeId)
end

local function gameUrl(placeId)
    return "https://www.roblox.com/games/" .. tostring(placeId)
end

local function offerJoinLink(placeId, reason)
    local url = gameUrl(placeId)
    copyText(url)
    notify(
        "Teleport blocked",
        (reason or "773 restricted") .. " — link copied. Paste in browser to join " .. gameNameOf(placeId),
        "Warning"
    )
end

pcall(function()
    TeleportService.TeleportInitFailed:Connect(function(player, result, errMsg)
        if player ~= LocalPlayer then return end
        local pid = currentPlaceId()
        offerJoinLink(pid, tostring(errMsg or result or "TeleportInitFailed"))
    end)
end)

local function tryTeleport(placeId)
    local ok = pcall(function()
        TeleportService:TeleportAsync(placeId, { LocalPlayer })
    end)
    if ok then return true end

    ok = pcall(function()
        TeleportService:Teleport(placeId, LocalPlayer)
    end)
    if ok then return true end

    ok = pcall(function()
        local opts = Instance.new("TeleportOptions")
        TeleportService:TeleportAsync(placeId, { LocalPlayer }, opts)
    end)
    if ok then return true end

    return false
end

GSupA:CreateButton({
    Name = "join",
    Style = "Primary",
    Icon = "log-in",
    Callback = function()
        local placeId = currentPlaceId()
        if not placeId then return notify("join", "Pick a game", "Warning") end
        if placeId == game.PlaceId then return notify("join", "Already here", "Warning") end

        notify("join", "Trying teleport → " .. gameNameOf(placeId), "Success")
        copyText(gameUrl(placeId))
        local ok = tryTeleport(placeId)
        if not ok then
            offerJoinLink(placeId, "client teleport failed")
        else
            local from = game.PlaceId
            task.delay(4, function()
                if State.dead then return end
                if game.PlaceId == from then
                    offerJoinLink(placeId, "still in same game (773?)")
                end
            end)
        end
    end,
})
GSupA:CreateButton({
    Name = "copy link (if join dies)",
    Desc = "use this if join fails",
    Icon = "external-link",
    Callback = function()
        local placeId = currentPlaceId()
        if not placeId then return end
        local url = gameUrl(placeId)
        if copyText(url) then
            notify("copied", gameNameOf(placeId) .. "\n" .. url, "Success")
        end
    end,
})
GSupA:CreateButton({
    Name = "copy id",
    Icon = "copy",
    Callback = function()
        local id = currentPlaceId()
        if id and copyText(id) then notify("copied", tostring(id), "Success") end
    end,
})
GSupA:CreateButton({
    Name = "copy link",
    Callback = function()
        local id = currentPlaceId()
        if not id then return end
        local url = "https://www.roblox.com/games/" .. tostring(id)
        if copyText(url) then notify("copied", url, "Success") end
    end,
})

local TabBatch = Window:CreateTab({ Name = "spam", Icon = "layers" })
local SubB = TabBatch:CreateSubTab({ Name = "main" })
local GB = SubB:AddLeftGroupbox({ Name = "spam", Icon = "layers" })
local GL = SubB:AddRightGroupbox({ Name = "loop", Icon = "repeat" })

GB:CreateDropdown({
    Name = "what",
    Options = { "Gamepasses", "Products", "Both" },
    CurrentOption = "Gamepasses",
    Flag = "PF_Target",
    Callback = function(o)
        State.loopTarget = type(o) == "table" and o[1] or o
    end,
})
GB:CreateButton({
    Name = "go",
    Style = "Primary",
    Callback = function() task.spawn(function() fireAll() end) end,
})
GB:CreateToggle({
    Name = "price cap",
    CurrentValue = false,
    Flag = "PF_PriceOn",
    Callback = function(v) State.usePriceFilter = v end,
})
GB:CreateSlider({
    Name = "max r$",
    Range = { 0, 5000 },
    Increment = 5,
    CurrentValue = 0,
    Flag = "PF_MaxR",
    Callback = function(v) State.maxRobux = v end,
})

GL:CreateSlider({
    Name = "wait",
    Range = { 0.05, 5 },
    Increment = 0.05,
    Suffix = "s",
    CurrentValue = 0.35,
    Flag = "PF_Delay",
    Callback = function(v) State.loopDelay = v end,
})
GL:CreateToggle({
    Name = "loop",
    CurrentValue = false,
    Flag = "PF_Loop",
    Callback = function(on)
        State.loop = on
        if on then task.spawn(batchLoopWorker) end
    end,
})

local TabSet = Window:CreateTab({ Name = "cfg", Icon = "settings" })
local GUI = TabSet:AddLeftGroupbox({ Name = "ui", Icon = "monitor" })
GUI:CreateKeybind({
    Name = "hide key",
    CurrentKeybind = "RightShift",
    OnChanged = function(key) Window:SetKeybind(key) end,
})
GUI:CreateToggle({
    Name = "dim",
    CurrentValue = false,
    Flag = "PF_Dim",
    Callback = function(on)
        pcall(function() Window:SetBackdrop(on) end)
        pcall(function() Window:SetBackdropTint(on and 0.35 or 0) end)
    end,
})
GUI:CreateButton({
    Name = "kill",
    Icon = "power",
    Callback = function()
        Library:Confirm({
            Title = "Unload?",
            ConfirmText = "Unload",
            Callback = function()
                State.dead = true
                State.loop = false
                State.singleLoop = false
                pcall(function() Window:Destroy() end)
                rawset(getgenv(), SCRIPT_ID, nil)
            end,
        })
    end,
})

pcall(function() TabSet:CreateConfigManager({ Name = "Configs", Side = "Right" }) end)
pcall(function() TabSet:CreateThemeManager({ Name = "Themes", Side = "Left" }) end)
pcall(function() Window:LoadAutoload() end)

task.defer(function()
    task.wait(0.35)
    scanCatalog()
end)

getgenv()[SCRIPT_ID] = {
    id = SCRIPT_ID,
    kill = function()
        State.dead = true
        State.loop = false
        State.singleLoop = false
        pcall(function() Window:Destroy() end)
        rawset(getgenv(), SCRIPT_ID, nil)
    end,
    catalog = catalog,
    excluded = excluded,
    log = State.log,
    fire = fireId,
    fireAll = fireAll,
    scan = scanCatalog,
}

notify("knife.lua | free products", "yea", "Success")
print("[knife.lua | free products]")
