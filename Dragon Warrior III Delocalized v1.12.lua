-- 💡 우리가 찾아냈던 BGM 포인터 주소(0x78038 등)와 hires.txt의 트랙 번호를 연결합니다.
local bgmTrackMap = {
    [0x8010] = 01,  -- Intro (intro + overture)
    [0x8028] = 07,  -- Castle
    [0x8030] = 09,  -- Adventure
    [0x8038] = 34,  -- Unknown World
    [0x8040] = 23,  -- Jipang
    [0x8048] = 12,  -- Dungeon
    [0x8050] = 15,  -- Tower
    [0x8058] = 21,  -- Pyramid
    [0x8060] = 16,  -- Shrine
    [0x8068] = 22,  -- Sailing
    [0x8070] = 26,  -- Song of Sadness
    [0x8078] = 13,  -- Village Theme
    [0x8080] = 31,  -- Heavly Flight (Lamia)
    [0x8088] = 05,  -- Town Theme
    [0x8090] = 10,  -- Battle Theme
    [0x8098] = 25,  -- Phantom Ship
    [0x80A0] = 40,  -- Hero's Challenge
    [0x80A8] = 11,  -- Requem
    [0x80D0] = 41,  -- The Light Returns
    [0x80D8] = 42,  -- Into the Legend
    [0x80E0] = 39,  -- Rainbow Bridge
    [0x80E8] = 27,  -- Memory of Love 1
    [0x8108] = 01,  -- Overture (intro + overture)
    [0x8110] = 01,  -- Overture (intro + overture)
    [0x8148] = 01,  -- Intro (intro + overture)
    [0x8150] = 02,  -- Main menu
    [0x8160] = 42,  -- Into the Legend
}

local bgmShortMap = {
    [0x80B0] = 45,  -- Wayfarer's Inn*
    [0x80B8] = 47,  -- Wayfarer's Inn*
    [0x80C0] = 43,  -- Victory*
    [0x80C8] = 49,  -- Cursed*
    [0x80F0] = 38,  -- Fairy Flute*
    [0x8100] = 53,  -- Echoing Flute *
    [0x8140] = 55,  -- Siver Harp*
    [0x80F8] = 54,  -- Echoing Flute (Echo)*
    [0x8158] = nil,  -- ??
}

local currentBgm = nil
local dungeon = nil -- find location thru BGM
local isUnderworld = 0 -- for Underworld Map

-- =================================================================
-- 🔇 bgmTrackMap 기반 자동 BGM 무음화 (안전하고 간결한 방식)
-- =================================================================
local function patchRomForSilenceBgm()
    local prgRomType = emu.memType.nesPrgRom
    -- [cite: 3, 15, 134]를 바탕으로 한 무음 패턴
    -- 1채널: $8168(FF 즉시 종료), 2~4채널: $8169(무음 대기)
    local silencePattern = { 0x68, 0x81, 0x69, 0x81, 0x69, 0x81, 0x69, 0x81 }

    -- bgmTrackMap에 등록된 모든 주소를 순회합니다. [cite: 147]
    for addr, _ in pairs(bgmTrackMap) do
        -- CPU 주소(예: 0x8010)를 물리 ROM 주소(0x78010)로 변환합니다. [cite: 148, 150]
        -- 드퀘 3의 BGM 포인터 구역은 0x78000 대역에 집중되어 있습니다.
        local physicalAddr = 0x70000 + addr

        -- 해당 곡의 8바이트(4채널 분량) 포인터를 무음 패턴으로 덮어씌웁니다. [cite: 1, 152]
        for j = 0, 7 do
            emu.write(physicalAddr + j, silencePattern[j + 1], prgRomType)
        end
    end

    emu.log("✅ bgmTrackMap 기반 BGM 무음화 완료 (등록된 모든 곡 처리)")
end

-- 스크립트 로드 시 실행
patchRomForSilenceBgm()




local prevSelect = false

-- 1. 셀렉트 버튼 입력 감지 및 토글 로직
local function checkInput()
    local input = emu.getInput(0)
    local currentSelect = input.select

    if currentSelect and not prevSelect then
        -- 수정된 부분: cpuDebug 대신 nesDebug를 사용하여 메모리를 읽습니다.
        local mapFlag = emu.read(0x07C5, emu.memType.nesDebug, false)
        
        if mapFlag > 0 then
            -- 값이 1(켜짐)이면 0으로 변경 (미니맵 끄기)
            emu.write(0x07C5, 0, emu.memType.nesDebug)
        else
            -- 값이 0(꺼짐)이거나 못 읽어왔으면 1로 변경 (미니맵 켜기)
            isUnderworld = emu.read(0x07C8, emu.memType.nesDebug, false)
            if isUnderworld == 1 then -- Under world music track
	            emu.write(0x07C5, 2, emu.memType.nesDebug)
			else
	            emu.write(0x07C5, 1, emu.memType.nesDebug)
			end
        end
    end
    
    prevSelect = currentSelect
end

-- inputPolled 이벤트에 콜백 등록 (입력이 갱신될 때마다 실행)
emu.addEventCallback(checkInput, emu.eventType.inputPolled)


-- 2. 실제 좌표를 읽어와 미니맵에 마커 그리기
local function drawPlayerPosition()
    local mapFlag = emu.read(0x07C5, emu.memType.nesDebug, false)

    if mapFlag > 0 then
        -- [좌표 읽기] 현재 찾으신 타일 기반 X, Y 좌표 (0 ~ 255 값)
        local playerX = emu.read(0x002A, emu.memType.nesDebug, false)
        local playerY = emu.read(0x002B, emu.memType.nesDebug, false)
        
        -- =======================================================
        -- [캘리브레이션 설정] 
        -- 만들고 계신 미니맵 이미지 실제 크기와 위치에 맞게 세팅하세요!
        -- =======================================================
        local mapOffsetX = 0 -- 지도 이미지가 화면 좌측에서 떨어진 거리(X 픽셀)
        local mapOffsetY = 0  -- 지도 이미지가 화면 상단에서 떨어진 거리(Y 픽셀)
        local mapWidth = 480    -- 미니맵 이미지의 실제 가로 폭(픽셀 크기)
        local mapHeight = 480   -- 미니맵 이미지의 실제 세로 높이(픽셀 크기)

        -- [비율 계산 핵심 수정] 
        -- 1. 최대 타일 값인 255로 나눕니다.
        -- 2. math.floor를 사용해 소수점을 제거하고 정확한 화면 픽셀 좌표(정수)로 만듭니다.
        local dotX
        local dotY
        
        if mapFlag == 1 then -- Over World
			mapOffsetX = 16
			dotX = mapOffsetX + math.floor(playerX * mapWidth / 256)
	        dotY = mapOffsetY + math.floor(playerY * mapHeight / 256)
	    else
			mapOffsetX = -39
			mapOffsetY = -4
	        dotX = mapOffsetX + math.floor(playerX * mapWidth / 129)
	        dotY = mapOffsetY + math.floor(playerY * mapHeight / 132)
		end
		
        -- HD 팩이나 다른 UI 레이어보다 위에 그려지도록 스크립트 HUD 서피스 선택
        emu.selectDrawSurface(emu.drawSurface.scriptHud)
        
        -- 계산된 위치에 4x4 픽셀의 붉은 불투명 마커 출력
        emu.drawRectangle(dotX, dotY, 4, 4, 0xFF0000, true, 1, 0)
        
        -- 레이어 원상 복구
        emu.selectDrawSurface(emu.drawSurface.consoleScreen)
    end
end

-- endFrame 이벤트에 콜백 등록 (화면 렌더링 시점에 마커를 그림)
emu.addEventCallback(drawPlayerPosition, emu.eventType.endFrame)

-- 매크로 상태 제어 변수
local currentMacro = nil -- 현재 실행 중인 매크로 ("search", "item", "magic")
local macroTimeline = 0

function handleStartOfFrame()
    -- 1. Port 2 입력 신호 감지
    local p2Input = emu.getInput(1)
 
 -- 1. 게임 내부 상태 메모리 읽기
    -- $003D: 메뉴 창이 활성화되었는지 감시 (00이면 필드, 01 이상이면 메뉴 오픈 완료)
    local menuFlag = emu.read(0x0035, emu.memType.nesDebug, false)
    -- $0041: 메뉴 안에서 현재 손가락 커서가 가리키는 인덱스 위치 (0, 1, 2, 3...)
    
    
    -- 매크로가 실행 중이 아닐 때만 버튼 입력 감지
    if currentMacro == nil and p2Input then
        if p2Input.b then          -- 실물 패드 L 누름
            currentMacro = "search"
        elseif p2Input.a then      -- 실물 패드 R 누름
            currentMacro = "magic"
        end
        macroTimeline = 0
    end

    -- 2. 매크로 작동 제어 구간
    if currentMacro ~= nil then
    	macroTimeline = macroTimeline + 1
        local fakeInput = {} -- 플레이어 원본 입력 차단용 빈 테이블
 	   local menuIndexX = emu.read(0x0074, emu.memType.nesDebug, false)
 	   local menuIndexY = emu.read(0x0075, emu.memType.nesDebug, false)

		-------------------------------------------------------------
        -- [2번째 패드  A] 서치 매크로 (A -> 아래 -> 아래 -> A)
        -------------------------------------------------------------
        if currentMacro == "search" then
            if menuFlag ~= 0x14 and macroTimeline == 1 then
                fakeInput.a = true -- 메뉴 열기
            elseif menuIndexY == 0x00 or menuIndexY == 0x01 then
                fakeInput.down = true -- 아래로 한 칸
            elseif menuIndexY == 0x02 then
                fakeInput.a = true -- 서치 선택
            end
            
            if macroTimeline > 50 then 
                currentMacro = nil 
                emu.setInput({}, 0) 
	        end
            
        -------------------------------------------------------------
        -- [2번째 패드 B] 마법 매크로 (A -> 오른쪽 -> A)
        -------------------------------------------------------------
        elseif currentMacro == "magic" then
            if menuFlag ~= 0x14 and macroTimeline == 1 then
                fakeInput.a = true -- 메뉴 열기
            elseif menuIndexX == 0x00 then
                fakeInput.right = true -- 오른쪽으로 한 칸 (주문 위치로 이동)
            elseif menuIndexX == 0x01 then
                fakeInput.a = true -- 주문 창 열기
            end
            
            if macroTimeline > 50 then 
                currentMacro = nil 
                emu.setInput({}, 0) 
            end
        end
        
        -- 가상 입력 주입
        if currentMacro ~= nil then
            emu.setInput(fakeInput, 0)
        end
    end
end

-- startOfFrame 주기에 콜백 등록
emu.addEventCallback(handleStartOfFrame, emu.eventType.startOfFrame)


-- 2바이트 Word 값을 분석해 상태 이름을 반환하는 함수 (기존 구조 완전 유지)
local function getStatusText(value)
    -- 상위 바이트와 하위 바이트 분리
    local highByte = math.floor(value / 256)
    local lowByte = value % 256

-- 1. [정정] 수면 턴수 및 순수 상태이상 플래그 분리 연산
    local sleepTurn = 0
    local pureLow = lowByte
    
    if lowByte % 16 == 8 then
        sleepTurn = 0
        pureLow = lowByte
    else
        sleepTurn = lowByte % 16      
        pureLow = lowByte - sleepTurn 
    end

    local states = {}

    -- 2. [정정] 하위 바이트 조건 검사 (문법 및 줄바꿈 완전 교정)
    if pureLow == 0xA0 or pureLow == 0xA8 then 
        table.insert(states, "Mute")
    elseif pureLow == 0x90 or pureLow == 0x98 then 
        table.insert(states, "Blind")
    end
    
    if lowByte % 16 == 8 or pureLow == 0x88 then
        table.insert(states, "Amplified")
    end
    
	local states = {} -- ◀ 반드시 이 테이블 선언이 먼저 와야 합니다.

	-- 1. 상위 바이트 조건 검사 (사망, 독, 마비, 혼란, 반사 등)
    if highByte == 0x00 then table.insert(states, "Dead") -- ◀ 이 한 줄만 추가
    elseif highByte == 0xA0 then table.insert(states, "Poisoned")
    elseif highByte == 0xC0 then table.insert(states, "Paralyzed")
    elseif highByte == 0x90 then table.insert(states, "Confuse")
    elseif highByte == 0x8F then table.insert(states, "Reflection")
    end

    -- 2. 하위 바이트 조건 검사 (침묵, 실명, 버프 등)
    if pureLow == 0xA0 then table.insert(states, "Mute")
    elseif pureLow == 0x90 then table.insert(states, "Phantom")
    elseif pureLow == 0x88 then table.insert(states, "Amplified")
    end

    -- 3. 수면 턴 카운터 조사
    if sleepTurn > 0 then
        table.insert(states, string.format("Sleep(%dT)", sleepTurn))
    end

    -- 최종 출력 가공
    if #states == 0 then
        return ""
    else
        return table.concat(states, ",")
    end
end

-- 오직 전투 시 화면 최종 단계에 상태이상을 그려주는 함수
local function drawPartyStatus()
	local bgFlag = emu.read(0x07C6, emu.memType.nesDebug, false)
    local baseAddress = 0x073C
    
    if bgFlag > 0 then
    	for i = 1, 4 do
            local currentAddr = baseAddress + ((i - 1) * 2)
            local statusWord = emu.readWord(currentAddr, emu.memType.nesDebug)
            local statusText = getStatusText(statusWord)
            
            local xPos = 80 + ((i - 1) * 80)
            local yPos = 20
            
            local textColor = 0xFFFFFF
            if statusWord ~= 0x8080 then
                if statusWord == 0x8088 or statusWord == 0x8F80 then
                    textColor = 0x55FF55 -- 버프 (Green)
                else
                    textColor = 0xFF5555 -- 디버프 (Red)
                end
            end
            
			emu.drawString(xPos, yPos, string.format("%s", statusText), textColor)
        end
    end
end

local battleTimer = 0
local savedTile = emu.read(0x07C7, emu.memType.nesDebug, false)        -- 평소 필드 타일 ID를 기억해둘 백업 변수

-- 전투 상태를 감시하고 HD 팩 연동 플래그를 작성하는 함수
local function checkBattleStatus()
	
    -- 1. $0051 주소에서 현재 게임의 페이즈/메인 상태 값을 읽어옵니다.
    local gameState = emu.read(0x050, emu.memType.nesDebug, false)
    local gameState2 = emu.read(0x04F, emu.memType.nesDebug, false)
    local gameState3 = emu.read(0x04E, emu.memType.nesDebug, false)

	drawPartyStatus() -- 파티 상태이상 일람
	
	-- 2. 조건 판별 및 커서/배경용 플래그 주소($07C6)에 쓰기
    if gameState == 0xD9 or gameState == 0xB1 then
        -- 오버월드(필드) 복귀 (0xD9/0xB1) 이면 $07C6을 0으로 돌림 (배경 비활성화)
        emu.write(0x07C6, 0, emu.memType.nesDebug)
        
        if gameState3 == 0x00 then
	        savedTile = emu.read(0x04F, emu.memType.nesDebug, false)
	        emu.write(0x07C7, savedTile, emu.memType.nesDebug)
		end
        
	elseif gameState == 0x1D and gameState2 == 0x1F and battleTimer >= 100 then
--	emu.log(string.format("%x %x %x", gameState, gameState2, dungeon))
		local playerX = emu.read(0x02A, emu.memType.nesDebug, false)
		local playerY = emu.read(0x02B, emu.memType.nesDebug, false)

        -- [지형 분석 및 배경 플래그 작성과 BGM 싱크 제어]
        if dungeon == 22 then -- Sailling
            emu.write(0x07C6, 4, emu.memType.nesDebug)
            emu.log("Sea")
            
        elseif dungeon == 12 then -- Dungeon
        	if playerY == 0xAB and (playerX == 0x33 or playeX == 0x34) then
	            emu.write(0x07C6, 0x0E, emu.memType.nesDebug)
	            emu.log("Baramos Castle")
            else
                emu.write(0x07C6, 8, emu.memType.nesDebug)
	            emu.log("Dungeon")
	        end
        elseif dungeon == 15 then -- Tower
            emu.write(0x07C6, 9, emu.memType.nesDebug)
            emu.log("Tower")

        elseif dungeon == 21 then -- Pyramid
            emu.write(0x07C6, 0x0A, emu.memType.nesDebug)
            emu.log("Pyramid")

        elseif dungeon == 25 then -- Phantom Ship
            emu.write(0x07C6, 0x0B, emu.memType.nesDebug)
            emu.log("Phantom Ship")
            
		elseif savedTile == 2 or savedTile == 3 then -- 평지
            emu.write(0x07C6, 1, emu.memType.nesDebug)
            emu.log("Land")

		elseif savedTile == 5 then -- 산
            emu.write(0x07C6, 5, emu.memType.nesDebug)
            emu.log("Mountain")

		elseif savedTile == 7 then -- Poison Field
            emu.write(0x07C6, 6, emu.memType.nesDebug)
            emu.log("Poison Field")

        elseif savedTile == 4 or savedTile == 5 then -- 숲
            emu.write(0x07C6, 2, emu.memType.nesDebug)
            emu.log("Forest")
            
        elseif savedTile == 1 then -- 사막 / 눈밭 타일번호 같음 Y좌표 보고 판단
			if playerY <= 0x63 or playerY >= 0xE0 and isUnderworld ~= 1 then
	            emu.write(0x07C6, 7, emu.memType.nesDebug)
	            emu.log("Snow")
			else
				emu.write(0x07C6, 3, emu.memType.nesDebug)
	            emu.log("Desert")
			end

        else -- 아니면 cloud 배경
            emu.write(0x07C6, 0x0C, emu.memType.nesDebug)
            emu.log("Don't know")
		end
	else
		battleTimer = battleTimer + 1
	end
end


-- 매 프레임마다 전투 메모리를 칼같이 감시하도록 설정
emu.addEventCallback(checkBattleStatus, emu.eventType.startFrame)


local function playTrack(trackNum, loop)
    -- 이미 해당 트랙이 재생 중이면 명령을 무시하여 뚝뚝 끊기는 현상 방지
    if currentBgm == trackNum then return end 
    if trackNum == 255 then  
    	emu.write(0x4101, 2, emu.memType.nesMemory)  -- Stop BGM

	elseif trackNum ~= 10 then -- 전투트랙이 아닌 경우 트랙종류로 장소 파악
		dungeon = trackNum
	
	end
    
    if trackNum == 34 then
    	isUnderworld = 1
     	emu.write(0x07C8, 1, emu.memType.nesMemory)  -- Underworld
   	
    elseif trackNum == 9 or trackNum == 31 then
    	isUnderworld = 0
     	emu.write(0x07C8, 0, emu.memType.nesMemory)  -- Underworld
    	
    end

    local loopFlag = 0
    if loop == true then loopFlag = 1 end

    emu.write(0x4100, loopFlag, emu.memType.nesMemory)    -- 0: 한 번 재생, 1: 무한 반복 루프
    emu.write(0x4101, 0, emu.memType.nesMemory)           -- 재생 정지 해제
    emu.write(0x4102, 70, emu.memType.nesMemory)         -- BGM 볼륨 최대(255)
    emu.write(0x4104, 0, emu.memType.nesMemory)           -- 0번 앨범 선택
    emu.write(0x4105, trackNum, emu.memType.nesMemory)    -- 지정한 트랙 번호 재생 시작!
    
    currentBgm = trackNum -- 현재 재생 중인 트랙 번호 백업
end


local trackNum = nil

-- 1. HD BGM 재생 콜백 함수
local function onBgmPointerRead(address, value)
    -- 주소[1]가 bgmTrackMap에 등록되어 있는지 확인 Global veriable!!
    trackNum = bgmTrackMap[address] 

	if trackNum ~= nil and currentTrackAddress ~= address then
        emu.log("🎵 BGM 감지: 오리지널 주소 0x" .. string.format("%X", address) .. " -> HD 트랙 " .. trackNum .. "번 재생!")
		bgmName = string.format("Track# %X", trackNum)

		playTrack(trackNum, true)
        
        currentTrackAddress = address
    end
        
    -- 짧은 노래는 원본 사용 (해결 못함)
    trackNum = bgmShortMap[address]
    
    if trackNum ~= nil and currentTrackAddress ~= address then
--		bgmName = string.format("Track# %X", trackNum)

		playTrack(255, false) -- bgm Mute
        
        currentTrackAddress = address
    end
end

-- BGM 포인터 구역 읽기 감시 이벤트 등록
emu.addMemoryCallback(onBgmPointerRead, emu.callbackType.read, 0x78010, 0x7815F, emu.cpuType.nes, emu.memType.nesPrgRom)


local function drawCurrentWatchingAddress()
    -- 1. 모니터링하고 싶은 주소들을 배열에 원하는 만큼 집어넣습니다.
    local addresses = { 0x47D, 0x50, 0x4F, 0x4e, 0x2A, 0x2B } 
    
    local results = {}
    
    -- 2. 배열에 지정된 주소들을 돌면서 값을 읽어와 가공합니다.
    for i, addr in ipairs(addresses) do
        local value = emu.read(addr, emu.memType.nesDebug, false)
        -- 출력 형태 예시: "3EB:17"
        local pairText = string.format("0x%03X:0x%02X", addr, value)
        table.insert(results, pairText)
    end
    
    -- 3. 읽어온 값들을 한 줄로 합칩니다. (구분자: " | ")
    local displayText = table.concat(results, " | ")
    -- 5. 화면에 출력
    emu.drawString(5, 470, displayText, 0xFFFFFF)
    emu.drawString(500,470, "한글", 0xFFFFFF)
end

-- 중복 등록 방지 후 화면 렌더링 시점(endFrame)에 콜백 등록
--emu.addEventCallback(drawCurrentWatchingAddress, emu.eventType.endFrame)

