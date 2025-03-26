-- Add LibDBIcon-1.0 dependency to the TOC file:
-- ## OptionalDeps: LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0

-- PandariaTetris: A Tetris-style game for World of Warcraft: Mists of Pandaria
-- Author: Claude
-- Version: 1.0

local addonName, PandariaTetris = ...
PandariaTetris = LibStub("AceAddon-3.0"):NewAddon(PandariaTetris, addonName, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

-- Configuration
local BOARD_WIDTH = 10
local BOARD_HEIGHT = 20
local CELL_SIZE = 24
local EDGE_SIZE = 2
local GAME_SPEED_BASE = 0.8  -- Base speed (seconds per drop)
local GAME_SPEED_DECREMENT = 0.05  -- Speed up after each level
local MIN_GAME_SPEED = 0.1  -- Fastest possible speed
local POINTS_PER_LINE = 100
local POINTS_PER_TETRIS = 400  -- 4 lines at once
local LEVEL_UP_LINES = 10

-- Game assets: block colors will use Pandaria-themed colors
local BLOCK_COLORS = {
    [1] = {r = 0.6, g = 0.8, b = 0.2}, -- Jade Forest green
    [2] = {r = 0.9, g = 0.7, b = 0.2}, -- Golden Pagoda
    [3] = {r = 0.5, g = 0.8, b = 0.9}, -- Valley of Eternal Blossoms blue
    [4] = {r = 0.8, g = 0.3, b = 0.2}, -- Mogu red
    [5] = {r = 0.7, g = 0.4, b = 0.8}, -- Shadopan purple
    [6] = {r = 0.3, g = 0.6, b = 0.3}, -- Serpent Scale green
    [7] = {r = 0.9, g = 0.5, b = 0.1}, -- Pandaren orange
}

-- Tetromino shapes
local SHAPES = {
    -- I shape
    {
        {0, 0, 0, 0},
        {1, 1, 1, 1},
        {0, 0, 0, 0},
        {0, 0, 0, 0}
    },
    -- J shape
    {
        {1, 0, 0},
        {1, 1, 1},
        {0, 0, 0}
    },
    -- L shape
    {
        {0, 0, 1},
        {1, 1, 1},
        {0, 0, 0}
    },
    -- O shape
    {
        {1, 1},
        {1, 1}
    },
    -- S shape
    {
        {0, 1, 1},
        {1, 1, 0},
        {0, 0, 0}
    },
    -- T shape
    {
        {0, 1, 0},
        {1, 1, 1},
        {0, 0, 0}
    },
    -- Z shape
    {
        {1, 1, 0},
        {0, 1, 1},
        {0, 0, 0}
    }
}

-- Game state variables
local gameBoard = {}
local currentTetromino = {}
local nextTetromino = {}
local tetrominoPosition = {x = 0, y = 0}
local gameSpeed = GAME_SPEED_BASE
local gameScore = 0
local gameLevel = 1
local linesCleared = 0
local gameTimer = nil
local gameActive = false
local gamePaused = false
local highScores = {}

-- UI elements
local gameFrame = nil
local gameBoard_UI = nil
local scoreText = nil
local levelText = nil
local linesText = nil
local nextTetrominoFrame = nil
local controlsFrame = nil

-- Minimap button variables
local minimapIcon = LibStub("LibDataBroker-1.1"):NewDataObject("PandariaTetris", {
    type = "launcher",
    text = "Pandaria Tetris",
    icon = "Interface\\Icons\\achievement_guild_classypanda",
    OnClick = function(self, button)
        if button == "LeftButton" then
            if gameFrame and gameFrame:IsShown() then
                PandariaTetris:HideGame()
            else
                PandariaTetris:ShowGame()
            end
        elseif button == "RightButton" then
            PandariaTetris:PrintHelp()
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("Pandaria Tetris")
        tooltip:AddLine("Left-click to show/hide the game", 1, 1, 1)
        tooltip:AddLine("Right-click for help", 1, 1, 1)
    end
})

function PandariaTetris:OnInitialize()
    -- Register slash commands
    self:RegisterChatCommand("pt", "HandleSlashCommand")
    self:RegisterChatCommand("pandariaTetris", "HandleSlashCommand")
    
    -- Load saved high scores if they exist
    if PandariaTetrisHighScores then
        highScores = PandariaTetrisHighScores
    end
    
    -- Initialize minimap button
    self:InitializeMinimapButton()
    
    -- Create the game UI
    self:CreateGameUI()
end

function PandariaTetris:InitializeMinimapButton()
    -- Initialize LibDBIcon
    self.db = self.db or { minimapButton = { hide = false } }
    self.iconDB = LibStub("LibDBIcon-1.0")
    self.iconDB:Register("PandariaTetris", minimapIcon, self.db.minimapButton)
end

function PandariaTetris:HandleSlashCommand(input)
    input = input:trim()
    if input == "show" or input == "" then
        self:ShowGame()
    elseif input == "hide" then
        self:HideGame()
    elseif input == "reset" then
        self:ResetHighScores()
    elseif input == "minimap" then
        self.db.minimapButton.hide = not self.db.minimapButton.hide
        if self.db.minimapButton.hide then
            self.iconDB:Hide("PandariaTetris")
            self:Print("Minimap button hidden")
        else
            self.iconDB:Show("PandariaTetris")
            self:Print("Minimap button shown")
        end
    elseif input == "help" then
        self:PrintHelp()
    end
end

function PandariaTetris:PrintHelp()
    self:Print("|cFF00FF00PandariaTetris Commands:|r")
    self:Print("/pt show - Show the game")
    self:Print("/pt hide - Hide the game")
    self:Print("/pt reset - Reset high scores")
    self:Print("/pt minimap - Toggle minimap button")
    self:Print("/pt help - Show this help message")
    self:Print("|cFF00FF00Game Controls:|r")
    self:Print("Left/Right Arrow - Move tetromino")
    self:Print("Up Arrow - Rotate tetromino")
    self:Print("Down Arrow - Soft drop")
    self:Print("Space - Hard drop")
    self:Print("P - Pause/Resume")
    self:Print("Esc - Close game")
end

function PandariaTetris:CreateGameUI()
    -- Main game frame
    gameFrame = CreateFrame("Frame", "PandariaTetrisFrame", UIParent)
    gameFrame:SetSize(BOARD_WIDTH * CELL_SIZE + 250, BOARD_HEIGHT * CELL_SIZE + 60)
    gameFrame:SetPoint("CENTER", UIParent, "CENTER")
    gameFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = {left = 11, right = 12, top = 12, bottom = 11}
    })
    gameFrame:SetMovable(true)
    gameFrame:EnableMouse(true)
    gameFrame:RegisterForDrag("LeftButton")
    gameFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    gameFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    gameFrame:Hide()
    
    -- Title
    local titleText = gameFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", gameFrame, "TOP", 0, -20)
    titleText:SetText("Pandaria Tetris")
    
    -- Game board
    gameBoard_UI = CreateFrame("Frame", "PandariaTetrisBoard", gameFrame)
    gameBoard_UI:SetSize(BOARD_WIDTH * CELL_SIZE, BOARD_HEIGHT * CELL_SIZE)
    gameBoard_UI:SetPoint("TOPLEFT", gameFrame, "TOPLEFT", 20, -40)
    gameBoard_UI:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    gameBoard_UI:SetBackdropColor(0, 0, 0, 1)
    
    -- Create grid cells for the game board
    for y = 1, BOARD_HEIGHT do
        for x = 1, BOARD_WIDTH do
            local cell = CreateFrame("Frame", "PandariaTetrisCell_"..x.."_"..y, gameBoard_UI)
            cell:SetSize(CELL_SIZE - EDGE_SIZE * 2, CELL_SIZE - EDGE_SIZE * 2)
            cell:SetPoint("TOPLEFT", gameBoard_UI, "TOPLEFT", (x-1) * CELL_SIZE + EDGE_SIZE, -(y-1) * CELL_SIZE - EDGE_SIZE)
            cell:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
                tile = false,
                edgeSize = 1,
            })
            cell:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
            cell:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.3)
            cell.occupied = false
            cell.colorIndex = 0
        end
    end
    
    -- Sidebar for game info
    local sidebar = CreateFrame("Frame", "PandariaTetrisSidebar", gameFrame)
    sidebar:SetSize(180, BOARD_HEIGHT * CELL_SIZE)
    sidebar:SetPoint("TOPLEFT", gameBoard_UI, "TOPRIGHT", 20, 0)
    
    -- Score display
    local scoreLabel = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scoreLabel:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -20)
    scoreLabel:SetText("Score:")
    
    scoreText = sidebar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scoreText:SetPoint("TOPLEFT", scoreLabel, "BOTTOMLEFT", 0, -5)
    scoreText:SetText("0")
    
    -- Level display
    local levelLabel = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    levelLabel:SetPoint("TOPLEFT", scoreText, "BOTTOMLEFT", 0, -15)
    levelLabel:SetText("Level:")
    
    levelText = sidebar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    levelText:SetPoint("TOPLEFT", levelLabel, "BOTTOMLEFT", 0, -5)
    levelText:SetText("1")
    
    -- Lines display
    local linesLabel = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    linesLabel:SetPoint("TOPLEFT", levelText, "BOTTOMLEFT", 0, -15)
    linesLabel:SetText("Lines:")
    
    linesText = sidebar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    linesText:SetPoint("TOPLEFT", linesLabel, "BOTTOMLEFT", 0, -5)
    linesText:SetText("0")
    
    -- Next tetromino preview
    local nextLabel = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nextLabel:SetPoint("TOPLEFT", linesText, "BOTTOMLEFT", 0, -20)
    nextLabel:SetText("Next:")
    
    nextTetrominoFrame = CreateFrame("Frame", "PandariaTetrisNextTetromino", sidebar)
    nextTetrominoFrame:SetSize(4 * CELL_SIZE, 4 * CELL_SIZE)
    nextTetrominoFrame:SetPoint("TOPLEFT", nextLabel, "BOTTOMLEFT", 10, -5)
    nextTetrominoFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    nextTetrominoFrame:SetBackdropColor(0, 0, 0, 0.7)
    
    -- Create cells for the next tetromino preview
    for y = 1, 4 do
        for x = 1, 4 do
            local cell = CreateFrame("Frame", "PandariaTetrisNextCell_"..x.."_"..y, nextTetrominoFrame)
            cell:SetSize(CELL_SIZE - EDGE_SIZE * 2, CELL_SIZE - EDGE_SIZE * 2)
            cell:SetPoint("TOPLEFT", nextTetrominoFrame, "TOPLEFT", (x-1) * CELL_SIZE + EDGE_SIZE, -(y-1) * CELL_SIZE - EDGE_SIZE)
            cell:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
                tile = false,
                edgeSize = 1,
            })
            cell:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
            cell:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.3)
        end
    end
    
    -- Game controls
    local startButton = CreateFrame("Button", "PandariaTetrisStartButton", sidebar, "UIPanelButtonTemplate")
    startButton:SetSize(100, 25)
    startButton:SetPoint("TOPLEFT", nextTetrominoFrame, "BOTTOMLEFT", 0, -5)
    startButton:SetText("Start Game")
    startButton:SetScript("OnClick", function() self:StartGame() end)
    
    local closeButton = CreateFrame("Button", "PandariaTetrisCloseButton", sidebar, "UIPanelButtonTemplate")
    closeButton:SetSize(100, 25)
    closeButton:SetPoint("TOPLEFT", startButton, "BOTTOMLEFT", 0, 5)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function() self:HideGame() end)
    
    -- Panda button in the bottom right
    local pandaButton = CreateFrame("Button", "PandariaTetrisPandaButton", gameFrame)
    pandaButton:SetSize(64, 64)
    pandaButton:SetPoint("BOTTOMRIGHT", gameFrame, "BOTTOMRIGHT", -15, 25)
    
    local pandaTexture = pandaButton:CreateTexture(nil, "ARTWORK")
    pandaTexture:SetAllPoints()
    pandaTexture:SetTexture("Interface\\Icons\\achievement_guild_classypanda")
    
    -- Add highlight texture
    local highlightTexture = pandaButton:CreateTexture(nil, "HIGHLIGHT")
    highlightTexture:SetAllPoints()
    highlightTexture:SetTexture("Interface\\Icons\\achievement_guild_classypanda")
    highlightTexture:SetBlendMode("ADD")
    
    -- Add click functionality
    pandaButton:SetScript("OnClick", function() 
        PlaySoundFile("Sound\\Character\\Pandaren\\PandarenVocalMale\\PandarenVocalMaleCheer01.ogg", "Master")
        self:Print("For Pandaria! May your blocks fall with wisdom!")
    end)
    
    -- Add tooltip
    pandaButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Pandaren Luck")
        GameTooltip:AddLine("Click for Pandaren wisdom", 1, 1, 1)
        GameTooltip:Show()
    end)
    pandaButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Key binding frame for game controls
    controlsFrame = CreateFrame("Frame", "PandariaTetrisControlsFrame", gameFrame)
    controlsFrame:SetAllPoints()
    controlsFrame:SetScript("OnKeyDown", function(self, key) PandariaTetris:HandleKeyPress(key) end)
    controlsFrame:Hide()
    
    -- Register events
    gameFrame:SetScript("OnShow", function() 
        self:Print("|cFFFFD700PandariaTetris|r loaded! Press 'Start Game' to begin.")
    end)
    
    -- Make the frame closeable with ESC
    tinsert(UISpecialFrames, "PandariaTetrisFrame")
end

function PandariaTetris:ShowGame()
    gameFrame:Show()
    self:UpdateHighScoreDisplay()
end

function PandariaTetris:HideGame()
    self:EndGame()
    gameFrame:Hide()
end

function PandariaTetris:StartGame()
    -- Reset the game state
    gameBoard = {}
    for y = 1, BOARD_HEIGHT do
        gameBoard[y] = {}
        for x = 1, BOARD_WIDTH do
            gameBoard[y][x] = 0
        end
    end
    
    gameScore = 0
    gameLevel = 1
    linesCleared = 0
    gameSpeed = GAME_SPEED_BASE
    gameActive = true
    gamePaused = false
    
    -- Update UI
    scoreText:SetText(gameScore)
    levelText:SetText(gameLevel)
    linesText:SetText(linesCleared)
    
    -- Clear the game board UI
    self:ClearBoard()
    
    -- Enable keyboard controls
    controlsFrame:EnableKeyboard(true)
    controlsFrame:Show()
    
    -- Spawn the first tetromino
    nextTetromino = self:GenerateRandomTetromino()
    self:SpawnNextTetromino()
    
    -- Start the game loop
    gameTimer = self:ScheduleRepeatingTimer("GameLoop", gameSpeed)
    
    -- Update the high scores display to ensure it's properly positioned
    self:UpdateHighScoreDisplay()
    
    -- Add Pandaren-style game start sound
    PlaySoundFile("Sound\\Character\\Pandaren\\PandarenVocalFemale\\PandarenVocalFemaleCheer01.ogg", "Master")
end

function PandariaTetris:EndGame()
    if not gameActive then return end
    
    -- Stop the game timer
    if gameTimer then
        self:CancelTimer(gameTimer)
        gameTimer = nil
    end
    
    -- Disable keyboard controls
    controlsFrame:EnableKeyboard(false)
    controlsFrame:Hide()
    
    -- Check for high scores
    if gameScore > 0 then
        self:CheckHighScore(gameScore)
    end
    
    -- Reset game state
    gameActive = false
    
    -- Display game over message
    local gameOverMsg = "Game Over! Score: " .. gameScore
    self:Print("|cFFFF0000" .. gameOverMsg .. "|r")
    
    -- Add Pandaren-style game over sound
    PlaySoundFile("Sound\\Character\\Pandaren\\PandarenVocalMale\\PandarenVocalMaleSigh01.ogg", "Master")
end

function PandariaTetris:PauseGame()
    if not gameActive then return end
    
    if gamePaused then
        -- Resume the game
        gameTimer = self:ScheduleRepeatingTimer("GameLoop", gameSpeed)
        gamePaused = false
        self:Print("Game resumed")
    else
        -- Pause the game
        if gameTimer then
            self:CancelTimer(gameTimer)
            gameTimer = nil
        end
        gamePaused = true
        self:Print("Game paused")
    end
end

function PandariaTetris:GenerateRandomTetromino()
    local colorIndex = math.random(1, #BLOCK_COLORS)
    local shapeIndex = math.random(1, #SHAPES)
    
    return {
        shape = SHAPES[shapeIndex],
        colorIndex = colorIndex
    }
end

function PandariaTetris:SpawnNextTetromino()
    currentTetromino = nextTetromino
    nextTetromino = self:GenerateRandomTetromino()
    
    -- Calculate the starting position (centered at top)
    local shapeWidth = #currentTetromino.shape[1]
    tetrominoPosition = {
        x = math.floor((BOARD_WIDTH - shapeWidth) / 2) + 1,
        y = 1
    }
    
    -- Update the next tetromino preview
    self:UpdateNextTetrominoPreview()
    
    -- Check for collision on spawn (game over condition)
    if self:CheckCollision(tetrominoPosition.x, tetrominoPosition.y, currentTetromino.shape) then
        self:EndGame()
        return false
    end
    
    -- Draw the tetromino on the board
    self:DrawTetromino()
    
    return true
end

function PandariaTetris:UpdateNextTetrominoPreview()
    -- Clear the preview
    for y = 1, 4 do
        for x = 1, 4 do
            local cell = _G["PandariaTetrisNextCell_"..x.."_"..y]
            cell:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
            cell:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.3)
        end
    end
    
    -- Draw the next tetromino in the preview
    local shape = nextTetromino.shape
    local colorIndex = nextTetromino.colorIndex
    local color = BLOCK_COLORS[colorIndex]
    
    -- Calculate centering offsets
    local shapeHeight = #shape
    local shapeWidth = #shape[1]
    local offsetX = math.floor((4 - shapeWidth) / 2) + 1
    local offsetY = math.floor((4 - shapeHeight) / 2) + 1
    
    for y = 1, shapeHeight do
        for x = 1, shapeWidth do
            if shape[y][x] == 1 then
                local cell = _G["PandariaTetrisNextCell_"..(x+offsetX-1).."_"..(y+offsetY-1)]
                cell:SetBackdropColor(color.r, color.g, color.b, 1)
                cell:SetBackdropBorderColor(color.r * 0.7, color.g * 0.7, color.b * 0.7, 1)
            end
        end
    end
end

function PandariaTetris:DrawTetromino()
    local shape = currentTetromino.shape
    local colorIndex = currentTetromino.colorIndex
    local posX = tetrominoPosition.x
    local posY = tetrominoPosition.y
    
    for y = 1, #shape do
        for x = 1, #shape[1] do
            if shape[y][x] == 1 then
                local boardX = posX + x - 1
                local boardY = posY + y - 1
                
                -- Only draw if within bounds
                if boardX >= 1 and boardX <= BOARD_WIDTH and boardY >= 1 and boardY <= BOARD_HEIGHT then
                    local cell = _G["PandariaTetrisCell_"..boardX.."_"..boardY]
                    local color = BLOCK_COLORS[colorIndex]
                    cell:SetBackdropColor(color.r, color.g, color.b, 1)
                    cell:SetBackdropBorderColor(color.r * 0.7, color.g * 0.7, color.b * 0.7, 1)
                    cell.occupied = true
                    cell.colorIndex = colorIndex
                end
            end
        end
    end
end

function PandariaTetris:ClearTetromino()
    local shape = currentTetromino.shape
    local posX = tetrominoPosition.x
    local posY = tetrominoPosition.y
    
    for y = 1, #shape do
        for x = 1, #shape[1] do
            if shape[y][x] == 1 then
                local boardX = posX + x - 1
                local boardY = posY + y - 1
                
                -- Only clear if within bounds
                if boardX >= 1 and boardX <= BOARD_WIDTH and boardY >= 1 and boardY <= BOARD_HEIGHT then
                    local cell = _G["PandariaTetrisCell_"..boardX.."_"..boardY]
                    cell:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
                    cell:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.3)
                    cell.occupied = false
                    cell.colorIndex = 0
                end
            end
        end
    end
end

function PandariaTetris:LockTetromino()
    local shape = currentTetromino.shape
    local colorIndex = currentTetromino.colorIndex
    local posX = tetrominoPosition.x
    local posY = tetrominoPosition.y
    
    for y = 1, #shape do
        for x = 1, #shape[1] do
            if shape[y][x] == 1 then
                local boardX = posX + x - 1
                local boardY = posY + y - 1
                
                if boardX >= 1 and boardX <= BOARD_WIDTH and boardY >= 1 and boardY <= BOARD_HEIGHT then
                    gameBoard[boardY][boardX] = colorIndex
                end
            end
        end
    end
    
    -- Play lock sound
    PlaySoundFile("Sound\\Interface\\iTellTarget.ogg", "Master")
    
    -- Check for completed lines
    self:CheckLines()
    
    -- Spawn next tetromino
    return self:SpawnNextTetromino()
end

function PandariaTetris:CheckCollision(posX, posY, shape)
    for y = 1, #shape do
        for x = 1, #shape[1] do
            if shape[y][x] == 1 then
                local boardX = posX + x - 1
                local boardY = posY + y - 1
                
                -- Check boundaries
                if boardX < 1 or boardX > BOARD_WIDTH or boardY > BOARD_HEIGHT then
                    return true
                end
                
                -- Check collision with locked pieces (only if within vertical bounds)
                if boardY >= 1 and gameBoard[boardY][boardX] > 0 then
                    return true
                end
            end
        end
    end
    
    return false
end

function PandariaTetris:RotateTetromino()
    if not gameActive or gamePaused then return end
    
    local shape = currentTetromino.shape
    local rows = #shape
    local cols = #shape[1]
    
    -- Create a new rotated shape matrix
    local newShape = {}
    for i = 1, cols do
        newShape[i] = {}
        for j = 1, rows do
            newShape[i][j] = shape[rows - j + 1][i]
        end
    end
    
    -- Check if rotation is valid
    if not self:CheckCollision(tetrominoPosition.x, tetrominoPosition.y, newShape) then
        -- Clear the current tetromino
        self:ClearTetromino()
        
        -- Apply rotation
        currentTetromino.shape = newShape
        
        -- Draw the rotated tetromino
        self:DrawTetromino()
        
        -- Play rotation sound
        PlaySoundFile("Sound\\Interface\\UI_Garrison_Nav_Clickable.ogg", "Master")
    end
end

function PandariaTetris:MoveTetromino(dirX, dirY)
    if not gameActive or gamePaused then return false end
    
    local newX = tetrominoPosition.x + dirX
    local newY = tetrominoPosition.y + dirY
    
    -- Check if move is valid
    if not self:CheckCollision(newX, newY, currentTetromino.shape) then
        -- Clear the current tetromino
        self:ClearTetromino()
        
        -- Update position
        tetrominoPosition.x = newX
        tetrominoPosition.y = newY
        
        -- Draw the tetromino at new position
        self:DrawTetromino()
        
        return true
    end
    
    -- If moving down and collision occurs, lock the tetromino
    if dirY > 0 and dirX == 0 then
        return self:LockTetromino()
    end
    
    return false
end

function PandariaTetris:HardDrop()
    if not gameActive or gamePaused then return end
    
    local dropDistance = 0
    
    -- Find the maximum drop distance
    while not self:CheckCollision(tetrominoPosition.x, tetrominoPosition.y + dropDistance + 1, currentTetromino.shape) do
        dropDistance = dropDistance + 1
    end
    
    if dropDistance > 0 then
        -- Clear the current tetromino
        self:ClearTetromino()
        
        -- Update position
        tetrominoPosition.y = tetrominoPosition.y + dropDistance
        
        -- Draw the tetromino at new position
        self:DrawTetromino()
        
        -- Add points for hard drop
        gameScore = gameScore + (dropDistance * 2)
        scoreText:SetText(gameScore)
        
        -- Play hard drop sound
        PlaySoundFile("Sound\\Interface\\RaidWarning.ogg", "Master")
    end
    
    -- Lock the tetromino
    return self:LockTetromino()
end

function PandariaTetris:CheckLines()
    local linesCompleted = 0
    local y = BOARD_HEIGHT
    
    while y >= 1 do
        local lineComplete = true
        
        -- Check if line is complete
        for x = 1, BOARD_WIDTH do
            if gameBoard[y][x] == 0 then
                lineComplete = false
                break
            end
        end
        
        if lineComplete then
            -- Remove the line
            for yy = y, 2, -1 do
                for x = 1, BOARD_WIDTH do
                    gameBoard[yy][x] = gameBoard[yy-1][x]
                end
            end
            
            -- Clear the top line
            for x = 1, BOARD_WIDTH do
                gameBoard[1][x] = 0
            end
            
            linesCompleted = linesCompleted + 1
            
            -- Don't increment y here as we need to check the same line again
            -- after shifting everything down
        else
            y = y - 1
        end
    end
    
    -- Update the board UI to reflect changes
    self:UpdateBoardUI()
    
    -- Update score and level if lines were completed
    if linesCompleted > 0 then
        -- Calculate score based on number of lines
        local scoreIncrease = linesCompleted == 4 and POINTS_PER_TETRIS or linesCompleted * POINTS_PER_LINE
        
        -- Add level multiplier
        scoreIncrease = scoreIncrease * gameLevel
        
        -- Update total score
        gameScore = gameScore + scoreIncrease
        
        -- Update lines cleared
        linesCleared = linesCleared + linesCompleted
        
        -- Check for level up
        local newLevel = math.floor(linesCleared / LEVEL_UP_LINES) + 1
        if newLevel > gameLevel then
            gameLevel = newLevel
            
            -- Increase game speed
            gameSpeed = math.max(MIN_GAME_SPEED, GAME_SPEED_BASE - ((gameLevel - 1) * GAME_SPEED_DECREMENT))
            
            -- Update the game timer
            if gameTimer then
                self:CancelTimer(gameTimer)
            end
            gameTimer = self:ScheduleRepeatingTimer("GameLoop", gameSpeed)
            
            -- Level up sound
            PlaySoundFile("Sound\\Interface\\LevelUp.ogg", "Master")
            self:Print("Level Up! Now level " .. gameLevel)
        end
        
        -- Update UI
        scoreText:SetText(gameScore)
        levelText:SetText(gameLevel)
        linesText:SetText(linesCleared)
        
        -- Play line clear sound
        if linesCompleted == 4 then
            -- Special sound for Tetris (4 lines)
            PlaySoundFile("Sound\\Interface\\AuctionWindowClose.ogg", "Master")
        else
            PlaySoundFile("Sound\\Interface\\iQuestComplete.ogg", "Master")
        end
    end
end

function PandariaTetris:UpdateBoardUI()
    for y = 1, BOARD_HEIGHT do
        for x = 1, BOARD_WIDTH do
            local cell = _G["PandariaTetrisCell_"..x.."_"..y]
            local colorIndex = gameBoard[y][x]
            
            if colorIndex > 0 then
                local color = BLOCK_COLORS[colorIndex]
                cell:SetBackdropColor(color.r, color.g, color.b, 1)
                cell:SetBackdropBorderColor(color.r * 0.7, color.g * 0.7, color.b * 0.7, 1)
                cell.occupied = true
                cell.colorIndex = colorIndex
            else
                cell:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
                cell:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.3)
                cell.occupied = false
                cell.colorIndex = 0
            end
        end
    end
end

function PandariaTetris:ClearBoard()
    for y = 1, BOARD_HEIGHT do
        for x = 1, BOARD_WIDTH do
            local cell = _G["PandariaTetrisCell_"..x.."_"..y]
            cell:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
            cell:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.3)
            cell.occupied = false
            cell.colorIndex = 0
        end
    end
end

function PandariaTetris:GameLoop()
    if not gameActive or gamePaused then return end
    
    -- Move the tetromino down
    if not self:MoveTetromino(0, 1) then
        -- If the movement failed and the tetromino was locked,
        -- the MoveTetromino function will have already spawned a new tetromino
        -- If that failed too (indicating game over), we should end the game
        if not gameActive then
            self:EndGame()
        end
    end
end

function PandariaTetris:HandleKeyPress(key)
    if not gameActive then return end
    
    if key == "LEFT" then
        self:MoveTetromino(-1, 0)
    elseif key == "RIGHT" then
        self:MoveTetromino(1, 0)
    elseif key == "DOWN" then
        self:MoveTetromino(0, 1)
    elseif key == "UP" then
        self:RotateTetromino()
    elseif key == "SPACE" then
        self:HardDrop()
    elseif key == "P" then
        self:PauseGame()
    elseif key == "ESCAPE" then
        self:HideGame()
    end
end

function PandariaTetris:CheckHighScore(score)
    -- Insert score into high scores table
    table.insert(highScores, {score = score, level = gameLevel, lines = linesCleared, date = date("%m/%d/%y")})
    
    -- Sort high scores (highest first)
    table.sort(highScores, function(a, b) return a.score > b.score end)
    
    -- Trim to top 10
    while #highScores > 10 do
        table.remove(highScores)
    end
    
    -- Save high scores
    PandariaTetrisHighScores = highScores
    
    -- Update display
    self:UpdateHighScoreDisplay()
end

function PandariaTetris:UpdateHighScoreDisplay()
    -- Clear previous high score display if it exists
    if gameFrame.highScoreFrame then
        gameFrame.highScoreFrame:Hide()
        gameFrame.highScoreFrame = nil
    end
    
    -- Create high score frame
    local highScoreFrame = CreateFrame("Frame", "PandariaTetrisHighScoreFrame", gameFrame)
    highScoreFrame:SetSize(200, 150)
    highScoreFrame:SetPoint("BOTTOMLEFT", gameBoard_UI, "BOTTOMRIGHT", 20, 0)
    highScoreFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    gameFrame.highScoreFrame = highScoreFrame
    
    -- High scores title
    local titleText = highScoreFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", highScoreFrame, "TOP", 0, -10)
    titleText:SetText("High Scores")
    
    -- Display high scores
    for i = 1, math.min(5, #highScores) do
        local scoreEntry = highScores[i]
        local scoreText = highScoreFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        scoreText:SetPoint("TOPLEFT", highScoreFrame, "TOPLEFT", 10, -20 - (i * 20))
        scoreText:SetText(i .. ". " .. scoreEntry.score .. " (Lvl " .. scoreEntry.level .. ")")
    end
end

function PandariaTetris:ResetHighScores()
    highScores = {}
    PandariaTetrisHighScores = highScores
    self:UpdateHighScoreDisplay()
    self:Print("High scores have been reset")
end

-- Register the addon with Ace
local AceAddon = LibStub("AceAddon-3.0")
if not AceAddon then
    print("PandariaTetris requires Ace3, LibDBIcon, and LibDataBroker to function")
    return
end