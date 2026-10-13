local AIRFLOW_URL = "https://raw.githubusercontent.com/kni-fe/free-products/main/AirFlowLibrary.luau"
local KNIFE_URL = "https://raw.githubusercontent.com/kni-fe/free-products/main/knife.lua_free%20products.lua"

local success, Library = pcall(function()
    local source = game:HttpGet(AIRFLOW_URL)
    return loadstring(source)()
end)

if not success or type(Library) ~= "table" or type(Library.CreateWindow) ~= "function" then
    error("[Wrapper] Failed to load AirFlow library: " .. tostring(Library))
end

getgenv().AirFlow = Library
getgenv().Library = Library

local timeout = 0
while type(getgenv().AirFlow) ~= "table" or type(getgenv().AirFlow.CreateWindow) ~= "function" do
    timeout = timeout + 1
    if timeout > 50 then -- 5 seconds
        error("[Wrapper] Timed out waiting for AirFlow to initialize")
    end
    task.wait(0.1)
end

local knifeSource = game:HttpGet(KNIFE_URL)
local knifeFn = loadstring(knifeSource)
if not knifeFn then
    error("[Wrapper] Failed to compile knife script")
end

knifeFn()