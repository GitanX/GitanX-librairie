--y

local FIXED_KEY = "GitanX_844GZAZA015kl"

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- small helpers
local function warnf(...) warn("[GitanX]", ...) end
local function trim(s) return (tostring(s):gsub("^%s*(.-)%s*$", "%1")) end

-- Supported games list
local supportedGames = {
    {name="War Chicago Realistic", id=89166445585239, url="https://raw.githubusercontent.com/GitanX/G1tan2_ikea/main/hdfhs.lua"},
    {name="Emergency Hamburg", id=7711635737, url="https://raw.githubusercontent.com/GitanX/G1tan2_ikea/main/fgdy.lua"},
    {name="Blade Ball", id=16281300371, url="https://raw.githubusercontent.com/arracheur-h/HIT_hub/main/HIT_hub.lua"},
    {name="Street Life Remastered", id=71600459831333, url="https://raw.githubusercontent.com/GitanX/G1tan2_ikea/main/Gitan2_ikea.lua"},
    {name="Arsenal", id=286090429, url="https://raw.githubusercontent.com/GitanX/G1tan2_ikea/main/other.lua"},
    {name="Digital Piano", id=8848607186, url="https://raw.githubusercontent.com/arracheur-h/HIT_hub/main/Digital%20Piano.lua"},
    {name="Natural Disaster", id=189707, url="https://raw.githubusercontent.com/GitanX/G1tan2_ikea/main/hey.lua"},
    {name="Arcade Sans Porter", id=6407649031, url="https://raw.githubusercontent.com/GitanX/G1tan2_ikea/main/sans%20porter.lua"},
    {name="Mega Mansion Tycoon", id=8328351891, url="https://raw.githubusercontent.com/GitanX/G1tan2_ikea/main/mega.lua"},
    {name="Highway Showdown", id=18281776841, url="https://raw.githubusercontent.com/GitanX/G1tan2_ikea/refs/heads/main/high.lua"},
    {name="Legend of Speed", id=3101667897, url="https://raw.githubusercontent.com/GitanX/G1tan2_ikea/refs/heads/main/legend.lua"},
    {name="Labyrinthe d'argent", id=135016791539483, url="https://raw.githubusercontent.com/GitanX/G1tan2_ikea/refs/heads/main/Labyrinthe.lua"},
    {name="Murder Mystery 2", id=142823291, url="https://raw.githubusercontent.com/GitanX/G1tan2_ikea/main/meme2.lua"}
}

-- Persist the fixed key
_G.GitanX_FixedKey = _G.GitanX_FixedKey or FIXED_KEY
local function getFixedKey() return tostring(_G.GitanX_FixedKey or "") end
local function setFixedKey(k) _G.GitanX_FixedKey = tostring(k or "") end
local function clearFixedKey() _G.GitanX_FixedKey = "" end

-- UI/global state
_G.GitanX_TabState = _G.GitanX_TabState or {}
_G.GitanX_Tabs = _G.GitanX_Tabs or {}
_G.GitanX_MainWindow = _G.GitanX_MainWindow or nil
_G.GitanX_HubBuilt = _G.GitanX_HubBuilt or false
_G.GitanX_KeyValidated = false

-- Load Rayfield
local Rayfield
do
    if _G.GitanX_Rayfield then
        Rayfield = _G.GitanX_Rayfield
    else
        local ok, res = pcall(function()
            return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
        end)
        if not ok then
            warnf("Rayfield failed to load:", res)
            return
        end
        Rayfield = res
        _G.GitanX_Rayfield = Rayfield
    end
end

local windowConfig = {
    Name = "GitanX Hub",
    LoadingTitle = "Chargement...",
    LoadingSubtitle = "Universal Hub",
    ConfigurationSaving = { Enabled = true, FolderName = "Universal" },
    Discord = { Enabled = false },
    KeySystem = false
}

local function safeCreateWindow(cfg)
    if _G.GitanX_MainWindow and type(_G.GitanX_MainWindow) == "table" and type(_G.GitanX_MainWindow.CreateTab) == "function" then
        return _G.GitanX_MainWindow
    end
    if type(Rayfield) == "table" and type(Rayfield.CreateWindow) == "function" then
        local ok, win = pcall(function() return Rayfield:CreateWindow(cfg) end)
        if ok and type(win) == "table" then
            _G.GitanX_MainWindow = win
            return win
        end
        warnf("safeCreateWindow fail:", tostring(win))
    else
        warnf("Rayfield.CreateWindow not available")
    end
    return nil
end

local MainWindow = safeCreateWindow(windowConfig)

local function CreateTabSafe(title, icon)
    if _G.GitanX_Tabs[title] and type(_G.GitanX_Tabs[title]) == "table" then
        return _G.GitanX_Tabs[title]
    end

    if MainWindow and type(MainWindow.CreateTab) == "function" then
        local ok, tab = pcall(function() return MainWindow:CreateTab(title, icon) end)
        if ok and type(tab) == "table" then
            _G.GitanX_Tabs[title] = tab
            _G.GitanX_TabState[title] = _G.GitanX_TabState[title] or {}
            return tab
        end
        warnf("CreateTabSafe: MainWindow.CreateTab failed:", tostring(tab))
    end

    if type(Rayfield) == "table" and type(Rayfield.CreateTab) == "function" then
        local ok2, tab2 = pcall(function() return Rayfield:CreateTab(title, icon) end)
        if ok2 and type(tab2) == "table" then
            _G.GitanX_Tabs[title] = tab2
            _G.GitanX_TabState[title] = _G.GitanX_TabState[title] or {}
            return tab2
        end
    end

    local dummy = {}
    function dummy:CreateParagraph(_) end
    function dummy:CreateInput(_) end
    function dummy:CreateButton(_) end
    _G.GitanX_Tabs[title] = dummy
    _G.GitanX_TabState[title] = _G.GitanX_TabState[title] or {}
    return dummy
end

local function notify(title, content, duration)
    if type(Rayfield) == "table" and type(Rayfield.Notify) == "function" then
        pcall(function() Rayfield:Notify({ Title = title, Content = content, Duration = duration or 3 }) end)
    else
        warnf(title, content)
    end
end

-- buildHubTabs
local function buildHubTabs()
    notify("ℹ️ Hub", "buildHubTabs() appelé. keyValidated = "..tostring(_G.GitanX_KeyValidated), 4)

    if not _G.GitanX_KeyValidated then
        notify("❌ Accès refusé", "Construction du hub annulée : clé non validée.", 5)
        return
    end

    if not _G.GitanX_MainWindow then
        MainWindow = safeCreateWindow(windowConfig)
        if not MainWindow then
            notify("Erreur UI", "Impossible de créer la fenêtre du hub (Rayfield).", 6)
            return
        end
    else
        MainWindow = _G.GitanX_MainWindow
    end

    -- HOME TAB
    local homeTab = CreateTabSafe("🏠 Home", 4483362458)
    local homeState = _G.GitanX_TabState["🏠 Home"]
    if not homeState.paragraph_created and type(homeTab.CreateParagraph) == "function" then
        pcall(function()
            homeTab:CreateParagraph({Title = "Current Game", Content = "PlaceId: "..tostring(game.PlaceId)})
            homeTab:CreateParagraph({Title = "Detected Game", Content = (function()
                for _, g in ipairs(supportedGames) do if g.id == game.PlaceId then return g.name end end
                return "This game is not supported."
            end)()})
        end)
        homeState.paragraph_created = true
    end
    if not homeState.button_created and type(homeTab.CreateButton) == "function" then
        pcall(function()
            homeTab:CreateButton({
                Name = "📃 See All Scripts",
                Callback = function() notify("Scripts Menu", "Go to the 📜 Scripts tab to view all scripts!", 5) end
                           })
        end)
        homeState.button_created = true
    end

    -- SCRIPTS TAB
    local scriptTab = CreateTabSafe("📜 Scripts", 4483362458)
    local scriptState = _G.GitanX_TabState["📜 Scripts"]
    scriptTab:CreateParagraph({Title = "Super Important !", Content = "You cant re-open the script in the same game you need to re-join the game for re-open the script"})

    local function safeLoadScript(placeId, url, gameName)
        -- ✅ Modification : suppression du check PlaceId → ouverture partout
        notify("⏳ Chargement", "Téléchargement de "..tostring(gameName).." ...", 3)
        local ok, res = pcall(function() return game:HttpGet(url) end)
        if not ok or not res then
            notify("Loading Error", "Impossible de télécharger: "..tostring(gameName), 5)
            warnf("safeLoadScript HttpGet error for", gameName, tostring(res))
            return
        end

        local body = tostring(res or "")
        if body == "" then
            notify("Loading Error", "Script vide ou introuvable: "..tostring(gameName), 6)
            return
        end

        local okc, funcOrErr = pcall(function() return loadstring(body) end)
        if not okc or type(funcOrErr) ~= "function" then
            notify("Loading Error", "Le script contient une erreur de compilation.", 6)
            warnf("loadstring error for "..tostring(gameName)..":", tostring(funcOrErr))
            return
        end

        local ranOk, runErr = pcall(function() funcOrErr() end)
        if not ranOk then
            notify("Execution Error", "Erreur à l'exécution du script: "..tostring(runErr), 8)
            warnf("runtime error while executing "..tostring(gameName)..":", tostring(runErr))
            return
        end

        notify("Script Loaded", gameName.." chargé avec succès.", 4)
    end

    if not scriptState.buttons_created and type(scriptTab.CreateButton) == "function" then
        pcall(function()
            for _, g in ipairs(supportedGames) do
                scriptTab:CreateButton({
                    Name = g.name,
                    Callback = (function(placeId, url, name)
                        return function() safeLoadScript(placeId, url, name) end
                    end)(g.id, g.url, g.name)
                })
            end
        end)
        scriptState.buttons_created = true
    end

    -- Troll Tab
    local TrollTab = CreateTabSafe("Troll", 4483362458)
    TrollTab:CreateButton({
        Name = "🚀 Troll Fusée",
        Callback = function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/GitanX/G1tan2_ikea/refs/heads/main/menufuser.lua"))()
        end
    })
    TrollTab:CreateButton({
        Name = "🚫 Troll Ban",
        Callback = function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/GitanX/G1tan2_ikea/refs/heads/main/menuban.lua"))()
        end
    })

    -- Credits Tab
    local creditsTab = CreateTabSafe("🎖️ Credits", 6031075938)
    local creditsState = _G.GitanX_TabState["🎖️ Credits"]
    if not creditsState.paragraph_created and type(creditsTab.CreateParagraph) == "function" then
        pcall(function()
            creditsTab:CreateParagraph({Title = "👑 Owner", Content = "G1tan2_ikea"})
            creditsTab:CreateParagraph({Title = "🤝 Co-Owner", Content = "arracheur2_92i"})
            creditsTab:CreateButton({
                Name = "📋 Copier Discord",
                Callback = function()
                    if typeof(setclipboard) == "function" then
                        setclipboard("https://discord.gg/nqVTXUeDHk")
                        notify("Link copied", "Discord copié dans le presse-papiers.", 3)
                    else
                        notify("ℹ️ Non supporté", "setclipboard non disponible.", 3)
                    end
                end
            })
        end)
        creditsState.paragraph_created = true
    end

    _G.GitanX_HubBuilt = true
    notify("✅ Hub", "Construction du hub terminée (idempotent).", 4)
end

-- Si clé déjà validée
if _G.GitanX_KeyValidated then
    pcall(buildHubTabs)
end

-- KEY TAB
local KeyTab = CreateTabSafe("🔐 Key System", 6031075938)
if not _G.GitanX_KeyValidated and type(KeyTab.CreateParagraph) == "function" then
    pcall(function()
        KeyTab:CreateParagraph({
            Title = "Need acces",
            Content = "Utilise la clé fixe locale fournie ou entre une clé manuellement."
        })
    end)
end

local keyInputValue = ""

if not _G.GitanX_KeyValidated and type(KeyTab.CreateInput) == "function" then
    pcall(function()
        KeyTab:CreateInput({
            Name = "Entrer ta clé",
            PlaceholderText = "Ex: GITANX-123456",
            RemoveTextAfterFocusLost = false,
            Callback = function(text)
                keyInputValue = trim(tostring(text or ""))
                warnf("Input changed ->", keyInputValue)
            end
        })
    end)
end

if not _G.GitanX_KeyValidated and type(KeyTab.CreateButton) == "function" then
    pcall(function()
        KeyTab:CreateButton({
            Name = "📋 Get Key",
            Callback = function()
                local fk = trim(getFixedKey())
                if fk == "" then
                    notify("⚠️ Pas de clé fixe", "Aucune clé fixe n'est définie.", 4)
                    return
                end
                keyInputValue = fk
                warnf("Get Key pressed, keyInputValue set to fixed key ->", fk)
                if typeof(setclipboard) == "function" then
                    pcall(function() setclipboard(fk) end)
                    notify("🔗 Clé copiée", "La clé fixe a été copiée dans le presse-papiers.", 3)
                else
                    notify("🔑 Clé pré-remplie", "La clé fixe a été placée dans le champ d'entrée.", 3)
                end
            end
        })
    end)

    pcall(function()
        KeyTab:CreateButton({
            Name = "✅ Vérifier la clé",
            Callback = function()
                local entered = trim(tostring(keyInputValue or ""))
                local fixed = trim(getFixedKey() or "")
                warnf("Verify pressed -> entered:", entered, "fixed:", fixed)

                if entered == "" then
                    notify("❌ Aucun texte", "Entre une clé avant de vérifier.", 3)
                    return
                end

                if fixed == "" then
                    notify("❌ Pas de clé fixe", "Aucune clé fixe définie pour la validation.", 5)
                    return
                end

                if entered == fixed then
                    _G.GitanX_KeyValidated = true
                    notify("✅ Key valid (local)", "Welcome in the hub !", 3)
                    pcall(buildHubTabs)
                else
                    _G.GitanX_KeyValidated = false
                    notify("❌ Key invalid (local)", "La clé locale ne correspond pas.", 6)
                end
            end
        })
    end)

    pcall(function()
        KeyTab:CreateButton({
            Name = "📋 Copy Discord",
            Callback = function()
                if typeof(setclipboard) == "function" then
                    pcall(function() setclipboard("https://discord.gg/nqVTXUeDHk") end)
                    notify("🔗 Link copied", "Discord copié dans le presse-papiers.", 3)
                else
                    notify("ℹ️ Non supporté", "setclipboard non disponible.", 3)
                end
            end
        })
    end)
else
    pcall(function()
        KeyTab:CreateParagraph({ Title = "Clé", Content = "Accès déjà validé pour cette session." })
        KeyTab:CreateButton({
            Name = "🔁 Rebuild Hub",
            Callback = function()
                notify("🔁 Rebuild", "Relance de la construction du hub...", 3)
                pcall(buildHubTabs)
            end
        })
    end)
end
