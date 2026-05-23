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
    [0x8148] = 01,  -- Intro (intro + overture)
    [0x8150] = 02,  -- Main menu
    [0x8160] = 42,  -- Into the Legend
    [0x8108] = 01,  -- Overture (intro + overture)
    [0x8110] = 01,  -- Overture (intro + overture)
}

local bgmShortMap = {
    [0x8018] = 56,  -- Level Up 
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

local townLocationMap = {
	["Romaria"] = { x = 0x34, y = 0x58, size = 2, arena = 1 },
	["Isis1"] = { x = 0x23, y = 0x89, size = 1, arena = 1 },
	["Isis2"] = { x = 0x24, y = 0x8A, size = 1, arena = 1 },
	["Jipang"] = { x = 0x9D, y = 0x93, size = 1, arena = 1 },
	["Jipang Cave"] = { x = 0x9E, y = 0x92, size = 1, arena = 0 },
	["Samanosa"] = { x = 0xD7, y = 0x9A, size = 2, arena = 1 },
	["Domdora"] = { x = 0x2C, y = 0x62, size = 2, arena = 0 },
	["Melkido"] = { x = 0x5C, y = 0x6F, size = 2, arena = 1 },
	["Baramos Castle"] = { x = 0x33, y = 0xAB, size = 2, arena = 0 },
	["Zoma Castle"] = { x = 0x43, y = 0x3A, size = 2, arena = 0 }
}

local dungeonLocationMap = {
	[1] = { x = 0xBE, y = 0xD1},
	[2] = { x = 0x34, y = 0xB4},
	[3] = { x = 0x66, y = 0xD8}, -- Solo Dungeon
	[4] = { x = 0x78, y = 0x92},
	[5] = { x = 0x2F, y = 0x15},
	[6] = { x = 0x30, y = 0x42}
}


-- 2. 마을 이름을 입력받아 현재 위치 여부를 반환하는 함수
local function isInTown(townName)

    -- 등록되지 않은 마을 이름이 들어오면 false 반환
    local data = townLocationMap[townName]
    if not data then 
        return nil 
    end

    -- 현재 플레이어의 X, Y 좌표 읽기
    local px = emu.read(0x02A, emu.memType.nesDebug, false)
    local py = emu.read(0x02B, emu.memType.nesDebug, false)

    -- 좌표 및 범위(size) 판정
    if py == data.y and px >= data.x and px < (data.x + data.size) then
        return data.arena
    end

    return false
end

local function isInDungeon()

    -- 현재 플레이어의 X, Y 좌표 읽기
    local px = emu.read(0x02A, emu.memType.nesDebug, false)
    local py = emu.read(0x02B, emu.memType.nesDebug, false)

	-- 등록되지 않은 마을 이름이 들어오면 false 반환
	for i, dungeon in pairs(dungeonLocationMap) do
		if dungeon.x == px and dungeon.y == py then
			return i
		end
    end

    return false
end



-- =================================================================
-- Global Veriables
-- =================================================================

local currentTrack = emu.read(0x7C9, emu.memType.nesDebug, false)
local isUnderworld = 0 -- for Underworld Map
local isField = 1 -- 전투 / 필드 구분


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



local isDebug = false
local prevSelect = false
local selectHoldTimer = 0 
local HOLD_THRESHOLD = 40 -- 약 0.6초 (프레임 기준)

local function checkInput()
    local input = emu.getInput(0)
    local currentSelect = input.select

    if currentSelect then
        -- 버튼을 누르고 있는 동안 타이머 증가
        selectHoldTimer = selectHoldTimer + 1
    elseif not currentSelect and prevSelect then
        -- 버튼을 떼는 순간 동작 판정
        if selectHoldTimer < HOLD_THRESHOLD then
            -- [짧게 누름] 기존 미니맵 토글 로직
            local mapFlag = emu.read(0x7C5, emu.memType.nesDebug, false)
            
            if mapFlag > 0 then
                -- 켜져 있으면 끄기
                emu.write(0x7C5, 0, emu.memType.nesDebug)
            else
                -- 꺼져 있으면 현재 위치(지상/지하) 확인 후 켜기
                if isUnderworld == 1 then
                    emu.write(0x7C5, 2, emu.memType.nesDebug) -- 지하 지도
                else
                    emu.write(0x7C5, 1, emu.memType.nesDebug) -- 지상 지도
                end
            end
        else
            -- [길게 누름] 다른 기능 수행
            isDebug = not isDebug
        end
        
        -- 타이머 초기화
        selectHoldTimer = 0
    end

    prevSelect = currentSelect
end

-- inputPolled 이벤트에 콜백 등록 (입력이 갱신될 때마다 실행)
emu.addEventCallback(checkInput, emu.eventType.inputPolled)

local blinkTimer = 0

-- 2. 실제 좌표를 읽어와 미니맵에 마커 그리기
local function drawPlayerPosition()
    local mapFlag = emu.read(0x7C5, emu.memType.nesDebug, false)

    if mapFlag > 0 then
        -- [좌표 읽기] 현재 찾으신 타일 기반 X, Y 좌표 (0 ~ 255 값)
        local playerX = emu.read(0x02A, emu.memType.nesDebug, false)
        local playerY = emu.read(0x02B, emu.memType.nesDebug, false)
        
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
		
         -- 💡 점멸 타이머 증가
        blinkTimer = blinkTimer + 1
        
        -- 💡 타이머 값에 따라 색상 결정 (60프레임 = 1초 기준)
        local markerColor = 0xFFFFFF -- 기본값: 흰색
        
        -- blinkTimer를 60으로 나눈 나머지가 30보다 작으면(0.5초) 빨간색, 
        -- 30 이상이면(0.5초) 흰색으로 변경합니다.
        if (blinkTimer % 120) >= 30 then
            markerColor = 0xFF0000 -- 변경값: 빨간색
        end
        
        -- HD 팩이나 다른 UI 레이어보다 위에 그려지도록 스크립트 HUD 서피스 선택
        emu.selectDrawSurface(emu.drawSurface.scriptHud)
        
        -- 계산된 위치에 4x4 픽셀의 붉은 불투명 마커 출력
        emu.drawRectangle(dotX, dotY, 4, 4, markerColor, true, 1, 0)
        
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
    local menuFlag = emu.read(0x035, emu.memType.nesDebug, false)
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
 	   local menuIndexX = emu.read(0x074, emu.memType.nesDebug, false)
 	   local menuIndexY = emu.read(0x075, emu.memType.nesDebug, false)

		-------------------------------------------------------------
        -- [2번째 패드  A] 서치 매크로 (A -> 아래 -> 아래 -> A)
        -------------------------------------------------------------
        if currentMacro == "search" then
            if menuFlag ~= 0x14 and macroTimeline == 1 then
                fakeInput.a = true -- 메뉴 열기
            elseif menuIndexY == 0x0 or menuIndexY == 0x1 then
                fakeInput.down = true -- 아래로 한 칸
            elseif menuIndexY == 0x2 then
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
            elseif menuIndexX == 0x0 then
                fakeInput.right = true -- 오른쪽으로 한 칸 (주문 위치로 이동)
            elseif menuIndexX == 0x1 then
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
    -- 정상 상태일 때 불필요한 연산을 막고 즉시 종료 (nil 에러 방지)
    if value == 0x8080 then
        return ""
    end

    -- 상위 바이트와 하위 바이트 분리
    local highByte = math.floor(value / 256)
    local lowByte = value % 256

    -- 1. 수면 턴수 및 순수 상태이상 플래그 분리 연산
    -- % 4를 사용하면 0x04(배리어)와 0x08(리플렉트)이 수면 턴수에 간섭하지 않고 pureLow로 빠집니다.
    local sleepTurn = lowByte % 4      
    local pureLow = lowByte - sleepTurn 

    local states = {}

    -- 2. 상위 바이트 조건 검사 (사망, 독, 마비, 혼란, 반사 등)
    if highByte == 0x00 then table.insert(states, "Dead")
    elseif highByte == 0xA0 then table.insert(states, "Poisoned")
    elseif highByte == 0xC0 then table.insert(states, "Paralyzed")
    elseif highByte == 0x90 then table.insert(states, "Confuse")
    elseif highByte == 0x8F then table.insert(states, "Reflection")
    end

    -- 3. 하위 바이트 조건 검사 (침묵, 실명, 버프 등)
    -- 💡 수정: == 와 elseif 대신, & 연산자와 개별 if문을 사용하여 중복 상태를 모두 잡아냅니다.

    -- 침묵 (Mute) : 0x20 비트 확인 (기본 0x80 + 0x20 = 0xA0)
    if (pureLow & 0x20) ~= 0 then 
        table.insert(states, "Mute")
    end

    -- 환영/눈멂 (Phantom) : 0x10 비트 확인 (기본 0x80 + 0x10 = 0x90)
    if (pureLow & 0x10) ~= 0 then 
        table.insert(states, "Phantom")
    end

    -- 앰플리파이 (Amplified) : 0x08 비트 확인
    if (pureLow & 0x08) ~= 0 then 
        table.insert(states, "Amplified")
    end

    -- 마법 배리어 (Barrier) : 0x04 비트 확인
    if (pureLow & 0x04) ~= 0 then 
        table.insert(states, "Barrier")
    end

    -- 4. 수면 턴 카운터 조사
    if sleepTurn > 0 then
        table.insert(states, string.format("Sleep(%dT)", sleepTurn))
    end

    -- 최종 출력 가공
    if #states == 0 then
        return ""
    else
        return table.concat(states, "\n")
    end
end


-- 오직 전투 시 화면 최종 단계에 상태이상을 그려주는 함수
local function drawPartyStatus()
	local bgFlag = emu.read(0x7C6, emu.memType.nesDebug, false)
    local baseAddress = 0x73C
    
    if bgFlag > 0 then
    	for i = 1, 4 do
            local currentAddr = baseAddress + ((i - 1) * 2)
            local statusWord = emu.readWord(currentAddr, emu.memType.nesDebug)
            local statusText = getStatusText(statusWord)
            
            local xPos = 80 + ((i - 1) * 80)
            local yPos = 5
            
            local textColor = 0xFFFFFF
            if statusWord ~= 0x8080 then
                local activeStatus = statusWord - 0x8080 
                
                -- 버프로 간주할 비트들의 합 (예: 리플렉트 0x08 + 앰플리파이 0x0F00 = 0x0F08)
                local buffMask = 0x0F0C 
                
                -- 1. 버프가 하나라도 켜져 있는가? (AND 연산 결과가 0이 아니면 참)
                local hasBuff = (activeStatus & buffMask) ~= 0
                
                -- 2. 디버프가 하나라도 켜져 있는가? (전체 상태에서 버프 마스크를 제외한 나머지 비트가 켜져 있으면 참)
                -- 비트 NOT 연산(~)을 사용하여 버프 외의 값이 있는지 확인합니다.
                local hasDebuff = (activeStatus & ~buffMask) ~= 0

                -- 3. 색상 판별 로직
                if hasBuff and hasDebuff then
                    textColor = 0xFFFF55 -- 🟡 버프 & 디버프 혼합 (Yellow)
                elseif hasBuff then
                    textColor = 0x55FF55 -- 🟢 순수 버프만 있음 (Green)
                elseif hasDebuff then
                    textColor = 0xFF5555 -- 🔴 순수 디버프만 있음 (Red)
                end
            end
            
			emu.drawString(xPos, yPos, string.format("%s", statusText), textColor, 78)
        end
    end
end


local function drawFilter(color)
    -- 2. 필터 적용 레이어 선택
    emu.selectDrawSurface(emu.drawSurface.consoleScreen)

	-- ARGB 색상 코드: 0x600000B0
    -- A(투명도): 60, R(빨강): 00, G(초록): 00, B(파랑): B0 (짙은 푸른색)
    -- 화면 꽉 차게(0, 0 부터 256x240 크기) 색을 채웁니다.
    emu.drawRectangle(0, 0, 512, 480, color, true, 1, 0)

end


local battleTimer = 0
local savedTile = emu.read(0x7C7, emu.memType.nesDebug, false)        -- 평소 필드 타일 ID를 기억해둘 백업 변수

-- 전투 상태를 감시하고 HD 팩 연동 플래그를 작성하는 함수
local function checkBattleStatus()
	
    -- 1. $0051 주소에서 현재 게임의 페이즈/메인 상태 값을 읽어옵니다.
    local myTile = emu.read(0x92, emu.memType.nesDebug, false) -- 내 타일
	local gameState3 = emu.read(0x581, emu.memType.nesDebug, false) -- 전투 진입시 0xFF
	local bufferField = emu.read(0x2C0, emu.memType.nesDebug, false) -- 비전투시 F8이 플래싱
	local currentTime = emu.read(0x6DF, emu.memType.nesDebug, false) -- 아침부터 걸은 거리
    
    if isInDungeon() ~= 3 then -- 혼자 들어가는 던전 제외
		drawPartyStatus() -- 파티 상태이상 일람
	end
		
    if bufferField == 0xF8 then -- 버퍼에 타일이 들어가면 필드
    	isField = 1

	end
    
    if gameState3 == 0xFF then -- 전투 진입
    	isField = 0
    	battleTimer = 0
    
	end
	
	-- 2. 조건 판별 및 커서/배경용 플래그 주소($07C6)에 쓰기
    if isField == 1 then -- 오버월드시 배경 및 필터 비활성화
        emu.write(0x7C6, 0, emu.memType.nesDebug) -- Batte Backdrop
	    emu.write(0x7C9, 0, emu.memType.nesDebug) -- Night Shadowmask
	    emu.write(0x7C7, myTile, emu.memType.nesDebug) -- 내 타일 백업 (미사용)
        
	elseif battleTimer >= 10 then
		if currentTime >= 97 then -- Night 
		    emu.write(0x7C9, 1, emu.memType.nesDebug)
	--		drawFilter(0x600000B0) -- Using hires.txt and backdrop_shadow5.png
		end

        -- [지형 분석 및 배경 플래그 작성과 BGM 싱크 제어]
        if isInTown("Romaria") or isInTown("Isis1") or isInTown("Isis2") or isInTown("Samanosa") or isInTown("Melkido") then
			emu.write(0x7C6, 0xF, emu.memType.nesDebug) -- Monster Fighting Arena
			
		elseif isInDungeon() == 3 then
            emu.write(0x7C6, 0x15, emu.memType.nesDebug) -- Dungeon Solo

		elseif isInDungeon() then
            emu.write(0x7C6, 0xE, emu.memType.nesDebug) -- Dungeon

		elseif isInTown("Jipang") then
            emu.write(0x7C6, 0x10, emu.memType.nesDebug) -- Jipang
        
        elseif isInTown("Jipang Cave") then
            emu.write(0x7C6, 0x11, emu.memType.nesDebug) -- Jipang Cave
        
        elseif isInTown("Baramos Castle") then
            emu.write(0x7C6, 0x14, emu.memType.nesDebug) -- Baramos Castle (Use Dungeon Backdrop)
        
        elseif isInTown("Zoma Castle") then
            emu.write(0x7C6, 0x12, emu.memType.nesDebug) -- Zoma Castle
        
        elseif currentTrack == 22 then -- Sailling
            emu.write(0x7C6, 4, emu.memType.nesDebug)
            
        elseif currentTrack == 12 then -- Dungeon
            emu.write(0x7C6, 8, emu.memType.nesDebug) -- Dungeon

		elseif currentTrack == 15 then -- Tower
            emu.write(0x7C6, 9, emu.memType.nesDebug)

        elseif currentTrack == 21 then -- Pyramid
            emu.write(0x7C6, 0xA, emu.memType.nesDebug)

        elseif currentTrack == 25 then -- Phantom Ship
            emu.write(0x7C6, 0xB, emu.memType.nesDebug)
            
		elseif myTile == 2 or myTile == 3 then -- 평지
            emu.write(0x7C6, 1, emu.memType.nesDebug)

		elseif myTile == 5 then -- 산
            emu.write(0x7C6, 5, emu.memType.nesDebug)

		elseif myTile == 7 then -- Poison Field
            emu.write(0x7C6, 6, emu.memType.nesDebug)

        elseif myTile == 4 or myTile == 5 then -- 숲
            emu.write(0x7C6, 2, emu.memType.nesDebug)
            
        elseif myTile == 0x13 then -- 블럭 바닥
--            emu.write(0x7C6, 2, emu.memType.nesDebug)
            
        elseif myTile == 0x0D then -- Broken 블럭 바닥
--            emu.write(0x7C6, 2, emu.memType.nesDebug)
            
        elseif myTile == 0x2C then -- Broken 돌 바닥
--            emu.write(0x7C6, 2, emu.memType.nesDebug)

		elseif myTile == 0x8F then -- 흙 바닥
--            emu.write(0x7C6, 2, emu.memType.nesDebug)
            
        elseif myTile == 1 then -- 사막 / 눈밭 타일번호 같음 Y좌표 및 언더월드 여부 보고 판단
			emu.write(0x7C6, 3, emu.memType.nesDebug) -- Desert

		elseif myTile == 0x1E then
            emu.write(0x7C6, 7, emu.memType.nesDebug) -- Snow

        else -- 아니면 cloud 배경
            emu.write(0x7C6, 0xC, emu.memType.nesDebug)
		end

	else
		battleTimer = battleTimer + 1
	end
end


-- 매 프레임마다 전투 메모리를  감시하도록 설정
emu.addEventCallback(checkBattleStatus, emu.eventType.startFrame)

local function playTrack(trackNum, loop)
    -- 이미 해당 트랙이 재생 중이면 명령을 무시하여 뚝뚝 끊기는 현상 방지
    if currentBgm == trackNum then return end 

	if trackNum == 255 then  
    	emu.write(0x4101, 2, emu.memType.nesMemory)  -- Stop BGM

	elseif trackNum ~= 10 then -- 전투트랙이 아닌 경우 트랙종류로 장소 파악
		currentTrack = trackNum
		
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

local function checkUnderworld()
    if currentTrack == 34 then
    	isUnderworld = 1
     	emu.write(0x7C8, 1, emu.memType.nesMemory)  -- Underworld
   	
    elseif currentTrack == 9 or trackNum == 31 then
    	isUnderworld = 0
     	emu.write(0x7C8, 0, emu.memType.nesMemory)  -- Underworld
    	
    end
end

emu.addEventCallback(checkUnderworld, emu.eventType.endFrame)

-- 1. HD BGM 재생 콜백 함수
local function onBgmPointerRead(address, value)
    -- 주소[1]가 bgmTrackMap에 등록되어 있는지 확인 Global veriable!!
    local trackNum = bgmTrackMap[address] 

	if trackNum ~= nil and currentTrackAddress ~= address then
        emu.log("🎵 BGM 감지: 오리지널 주소 0x" .. string.format("%X", address) .. " -> HD 트랙 " .. trackNum .. "번 재생!")
		bgmName = string.format("Track# %X", trackNum)

		playTrack(trackNum, true)
        
        currentTrackAddress = address
        emu.write(0x7C9, trackNum, emu.memType.nesMemory) -- 트랙 어드레스 저장
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
    local addresses = { 0x50, 0x7C6, 0x7c7, 0x7c8, 0x2A, 0x2B } 
    
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
	if isDebug == true then
	    emu.drawString(5, 470, displayText, 0xFFFFFF)
	    emu.drawString(500,470, currentTrack, 0xFFFFFF)
	end
end

-- 중복 등록 방지 후 화면 렌더링 시점(endFrame)에 콜백 등록
emu.addEventCallback(drawCurrentWatchingAddress, emu.eventType.endFrame)

