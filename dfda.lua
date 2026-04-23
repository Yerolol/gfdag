-- LuaManagementSDK.lua
-- Drop this into your Roblox script to handle key validation

local LuaManagement = {}
LuaManagement.__index = LuaManagement

-- Configuration
LuaManagement.Config = {
    API_URL = "http://localhost:8000", -- Change to your hosted URL
    Service = "default", -- Your service identifier
    RecheckInterval = 300, -- Recheck key every 5 minutes
    MaxRetries = 3,
    Timeout = 10
}

-- Storage
LuaManagement.Storage = {
    FileName = "lua_mgmt_key.txt",
    FolderName = "LuaManagement"
}

-- State
LuaManagement.State = {
    IsValid = false,
    CurrentKey = nil,
    KeyData = nil,
    LastCheck = 0
}

-- Utility: File system check
local function hasFileSystem()
    return pcall(function() return type(writefile) == "function" end)
end

-- Save key locally
function LuaManagement:SaveKey(key)
    if not hasFileSystem() then return false end
    local success = pcall(function()
        if not isfolder(self.Storage.FolderName) then
            makefolder(self.Storage.FolderName)
        end
        writefile(self.Storage.FolderName .. "/" .. self.Storage.FileName, key)
    end)
    return success
end

-- Load saved key
function LuaManagement:LoadKey()
    if not hasFileSystem() then return nil end
    local success, content = pcall(function()
        local path = self.Storage.FolderName .. "/" .. self.Storage.FileName
        if isfile(path) then
            return readfile(path)
        end
        return nil
    end)
    return success and content or nil
end

-- Clear saved key
function LuaManagement:ClearKey()
    if not hasFileSystem() then return false end
    return pcall(function()
        local path = self.Storage.FolderName .. "/" .. self.Storage.FileName
        if isfile(path) then
            delfile(path)
        end
    end)
end

-- Get HWID (platform-specific)
function LuaManagement:GetHWID()
    local hwid = nil
    
    -- Try gethwid (common in executors)
    pcall(function()
        if gethwid then
            hwid = gethwid()
        end
    end)
    
    -- Try getgenv().HWID
    if not hwid then
        pcall(function()
            if getgenv().HWID then
                hwid = getgenv().HWID
            end
        end)
    end
    
    -- Try game.RobloxHWID
    if not hwid then
        pcall(function()
            if game.RobloxHWID then
                hwid = tostring(game.RobloxHWID)
            end
        end)
    end
    
    -- Fallback: Generate from UserId
    if not hwid then
        local HttpService = game:GetService("HttpService")
        local Players = game:GetService("Players")
        local player = Players.LocalPlayer
        if player then
            local guid = HttpService:GenerateGUID(false)
            hwid = tostring(player.UserId) .. "-" .. guid:sub(1, 16)
        else
            hwid = "UNKNOWN-" .. HttpService:GenerateGUID(false):sub(1, 8)
        end
    end
    
    return hwid
end

-- Make HTTP request
function LuaManagement:Request(endpoint, data)
    local HttpService = game:GetService("HttpService")
    local success, result = pcall(function()
        local response = HttpService:PostAsync(
            self.Config.API_URL .. endpoint,
            HttpService:JSONEncode(data),
            Enum.HttpContentType.ApplicationJson,
            false,
            {
                ["Content-Type"] = "application/json"
            }
        )
        return HttpService:JSONDecode(response)
    end)
    
    if success then
        return result
    else
        return {valid = false, error = "NETWORK_ERROR", message = "Failed to connect to server"}
    end
end

-- Validate a key with the server
function LuaManagement:ValidateKey(key)
    if not key or key == "" then
        return {valid = false, error = "KEY_EMPTY", message = "No key provided"}
    end
    
    local hwid = self:GetHWID()
    
    local response = self:Request("/api/sdk/validate", {
        key = key,
        hwid = hwid,
        service = self.Config.Service
    })
    
    if response.valid then
        self.State.IsValid = true
        self.State.CurrentKey = key
        self.State.KeyData = response
        self.State.LastCheck = os.time()
        self:SaveKey(key)
    end
    
    return response
end

-- Check if current key is still valid
function LuaManagement:CheckStatus()
    if not self.State.CurrentKey then
        return {valid = false, error = "NO_KEY", message = "No key loaded"}
    end
    
    -- If checked recently, return cached
    if os.time() - self.State.LastCheck < self.Config.RecheckInterval then
        return {valid = self.State.IsValid, cached = true}
    end
    
    local hwid = self:GetHWID()
    local response = self:Request("/api/sdk/check", {
        key = self.State.CurrentKey,
        hwid = hwid,
        service = self.Config.Service
    })
    
    self.State.IsValid = response.valid or false
    self.State.LastCheck = os.time()
    
    if not self.State.IsValid then
        self:ClearKey()
    end
    
    return response
end

-- Initialize and auto-load saved key
function LuaManagement:Initialize(callback)
    local savedKey = self:LoadKey()
    
    if savedKey then
        local response = self:ValidateKey(savedKey)
        if callback then
            callback(response.valid, response)
        end
        return response.valid
    end
    
    if callback then
        callback(false, {valid = false, error = "NO_KEY", message = "No saved key"})
    end
    return false
end

-- Launch with UI prompt (if no valid key)
function LuaManagement:Launch(config)
    if config then
        for k, v in pairs(config) do
            if self.Config[k] ~= nil then
                self.Config[k] = v
            end
        end
    end
    
    -- Check for existing valid key
    local savedKey = self:LoadKey()
    if savedKey then
        local response = self:ValidateKey(savedKey)
        if response.valid then
            return true
        end
    end
    
    -- No valid key - show prompt
    return self:PromptForKey()
end

-- Show key input prompt
function LuaManagement:PromptForKey()
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    
    -- Create simple GUI
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "LuaManagementPrompt"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 350, 0, 200)
    frame.Position = UDim2.new(0.5, -175, 0.5, -100)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    frame.BorderSizePixel = 0
    frame.Parent = screenGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 40)
    title.BackgroundTransparency = 1
    title.Text = "Enter License Key"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 20
    title.Font = Enum.Font.GothamBold
    title.Parent = frame
    
    local textBox = Instance.new("TextBox")
    textBox.Size = UDim2.new(1, -40, 0, 40)
    textBox.Position = UDim2.new(0, 20, 0, 50)
    textBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    textBox.PlaceholderText = "XXXX-XXXX-XXXX-XXXX"
    textBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
    textBox.TextSize = 16
    textBox.Font = Enum.Font.Code
    textBox.Parent = frame
    
    local textCorner = Instance.new("UICorner")
    textCorner.CornerRadius = UDim.new(0, 6)
    textCorner.Parent = textBox
    
    local submitBtn = Instance.new("TextButton")
    submitBtn.Size = UDim2.new(0, 120, 0, 36)
    submitBtn.Position = UDim2.new(0.5, -60, 0, 110)
    submitBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    submitBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
    submitBtn.Text = "Activate"
    submitBtn.TextSize = 16
    submitBtn.Font = Enum.Font.GothamBold
    submitBtn.Parent = frame
    
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = submitBtn
    
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 0, 20)
    statusLabel.Position = UDim2.new(0, 0, 0, 160)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = ""
    statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    statusLabel.TextSize = 14
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.Parent = frame
    
    local result = nil
    local completed = false
    
    submitBtn.MouseButton1Click:Connect(function()
        local key = textBox.Text:gsub("%s+", ""):upper()
        if key == "" then
            statusLabel.Text = "Please enter a key"
            return
        end
        
        statusLabel.Text = "Validating..."
        statusLabel.TextColor3 = Color3.fromRGB(255, 255, 150)
        
        local response = self:ValidateKey(key)
        
        if response.valid then
            statusLabel.Text = "Success! Access granted."
            statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
            result = true
            completed = true
            task.wait(1)
            screenGui:Destroy()
        else
            statusLabel.Text = "Error: " .. (response.message or "Invalid key")
            statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
            result = false
        end
    end)
    
    -- Wait for result
    repeat task.wait() until completed or not screenGui.Parent
    
    if screenGui.Parent then
        screenGui:Destroy()
    end
    
    return result or false
end

-- Monitor key validity in background
function LuaManagement:StartMonitor(callback, interval)
    interval = interval or self.Config.RecheckInterval
    
    task.spawn(function()
        while self.State.IsValid do
            task.wait(interval)
            local response = self:CheckStatus()
            
            if not response.valid then
                self.State.IsValid = false
                if callback then
                    callback(false, response)
                end
                break
            end
        end
    end)
end

-- Get current key info
function LuaManagement:GetInfo()
    return {
        valid = self.State.IsValid,
        key = self.State.CurrentKey and (self.State.CurrentKey:sub(1, 4) .. "-XXXX-XXXX-" .. self.State.CurrentKey:sub(-4)),
        expires = self.State.KeyData and self.State.KeyData.expires_at,
        discord_user = self.State.KeyData and self.State.KeyData.discord_user
    }
end

return LuaManagement
