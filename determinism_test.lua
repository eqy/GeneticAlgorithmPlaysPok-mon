local sequence_len=60000
local direction_window=420

function n_frames(n)
	for i=1,n do
	    emu.frameadvance()
	end
end

function preamble_button(button)
    local frame_interval = 60
    local delay = 15
	n_frames(frame_interval)
    joypad.set({[button] = true})
	n_frames(delay)
    joypad.set({})
end

function preamble()
    -- wait for some stuff to init
    n_frames(420)
    for i=1,7 do
        preamble_button("Start")
    end
    for i=1,60 do
        emu.frameadvance()
    end
    inputTable = {["Select"] = true, ["B"] = true, ["Up"] = true}
    joypad.set(inputTable)
    for i=1,30 do
        emu.frameadvance()
    end
    joypad.set({})
    for i=1,30 do
        emu.frameadvance()
    end
    preamble_button("Down")
    for i=1,2 do
        preamble_button("A")
    end
end

function clear_reset()
	print("rebooting...")
    client.reboot_core()
    preamble()
	print("rebooting...")
    client.reboot_core()
end

function random_button()
    rand = math.random()
	button = "Nop"
	if rand > 0.5 then
        if rand > 0.75 then
            if rand > 0.999 then
                if rand > 0.9999 then
                    button = 'Select'
                else
                    button = 'Start'
                end
			elseif rand > 0.93675 then
                button = 'Right'
			elseif rand > 0.8745 then
                button = 'Left'
            elseif rand > 0.81225 then
                button = 'Down'
            else
                button = 'Up'
            end
        elseif rand > 0.60 then
            button = 'A'
        else
            button = 'B'
		end
	end
    return button
end

function random_sequence()
	sequence = {}
	for i=1,sequence_len do
	    sequence[i] = random_button()
	end
    assert(sequence_len == #sequence)
	return sequence
end

-- only counts one byte because this is an 8-bit system br0
function popcount(val)
    sum = 0
    sum = sum + bit.band(val, 0x1)
    sum = sum + bit.rshift(bit.band(val, 0x2), 1)
    sum = sum + bit.rshift(bit.band(val, 0x4), 2)
    sum = sum + bit.rshift(bit.band(val, 0x8), 3)
    sum = sum + bit.rshift(bit.band(val, 0x10), 4)
    sum = sum + bit.rshift(bit.band(val, 0x20), 5)
    sum = sum + bit.rshift(bit.band(val, 0x40), 6)
    sum = sum + bit.rshift(bit.band(val, 0x80), 7)
    return sum
end


local locations = {38, 0, 40, 12, 1, 41, 13, 51, 2}
local map_scores = {}
local score = 1
for i,addr in ipairs(locations) do
    map_scores[addr] = score
    score = score + 1
end 

function calculate_map_score(map_number)
    if map_scores[map_number] ~= nil then
        return 1000000*map_scores[map_number]
    end 
    return 0
end

-- TODO: finer-grained objectives and heuristics
function calculate_score()
 	-- memory probably not yet init'd by the game yet
	if emu.framecount() < 3000 then
		return 0
	end
    sum = 0
	-- this part is a workaround BizHawk changing the segment mapping
        -- from WRAM being in 0xC000 to 0xDFFF to flat addressing
	local offset = 0xC000
        -- pokemon levels
	-- enemy level 0xD127
    pokemon_levels = {'0xD18C', '0xD1B8', '0xD1E4', '0xD210', '0xD23C', '0xD268', '0xD127'}
    for i,addr in ipairs(pokemon_levels) do
        sum = sum + 1000*mainmemory.readbyte(tonumber(addr)-offset)
    end
    -- seen pokemon (D30A-D31C) 54026-54044
    seen = 0
    for i=54026,54044 do
        seen = seen + popcount(mainmemory.readbyte(i-offset))
    end
    sum = sum + seen * 10000
    -- badges D356/54102
    sum = sum + 10000000*mainmemory.readbyte(54102-offset)
    -- items in storage D53A/54586, D31D (total items)
	item_addrs = {'0xD53A', '0xD31D'}
	for i,addr in ipairs(item_addrs) do
		sum = sum + 1000*mainmemory.readbyte(tonumber(addr)-offset)
	end
	money_addrs = {'0xD347', '0xD348', '0xD349'}
	local scale = 1
	for i,addr in ipairs(money_addrs) do
		sum = sum + scale*mainmemory.readbyte(tonumber(addr)-offset)
		scale = scale * 100
	end
        -- game missable objects (D5A6-D5C5) 54694-54725
    for i=54694,54586 do
        sum = sum + 1000*popcount(mainmemory.readbyte(i-offset))
    end
    -- town map D5F3 / 54771
    -- sum = sum + 1000000*memory.readbyte(54771)
    -- oak's parcel D60D
    -- fly anywhere D70B / 
    -- fly anywhere D70C
    -- fought giovanni D751
    -- fought brock D755
    -- fought misty D75E
    -- fought erika D77C
    -- fought koga D792
    -- fought blaine D79A
    -- fought sabrina D7B3
    -- fought snorlax D7D8
    -- fought snorlax D7E0
    events = {'0xD5F3', '0xD60D', '0xD70B', '0xD70C', '0xD751', '0xD755', '0xD75E', '0xD77C', '0xD792', '0xD79A', '0xD7B3', '0xD7D8', '0xD7E0'}
    for i, addr in ipairs(events) do
        sum = sum + 1000000*popcount(mainmemory.readbyte(tonumber(addr)-offset))
    end
    -- calculate map_number score
    local map_number = mainmemory.readbyte(tonumber('0xD35E')-offset)
    sum = sum + calculate_map_score(map_number)
    return sum
end


function rollout(sequence)
	local last_directions = {}

    function pushpop(val, list)
        for i=direction_window,2,-1 do
            list[i] = list[i-1]
        end
        list[1] = val
        return list
    end


    function in_list(val, list)
        for i=1,direction_window do
            if val == list[i] then
                return true
            end
        end
        return false
    end


	function anti_spin(button)
		if button == 'Down' and in_list('Up', last_directions) then
			return true
		elseif button == 'Up' and in_list('Down', last_directions) then
			return true
		elseif button == 'Left' and in_list('Right', last_directions) then
			return true
		elseif button == 'Right' and in_list('Left', last_directions) then
			return true
		end
		if in_list(button, last_directions) then
			last_directions = pushpop('Nop', last_directions)
		else
			last_directions = pushpop(button, last_directions)
		end
		return false
	end


	for i=1,direction_window do
		last_directions[i] = '?'
	end


	local score = 0
	local max_score = 0
	local max_score_frame = 0 

	for i=1,sequence_len do
		button = sequence[i]
		local inputTable = {}
		if anti_spin(button) then
			do end
		else
		    if button ~= "Nop" then
                inputTable = {[button] = true}
		    end
		    cur_table = joypad.get(1)
		    if emu.framecount() % 420 == 0 then
		    	score = calculate_score()
		    end
		    if score > max_score then
		    	max_score_frame = emu.framecount()
		    end
		    max_score = math.max(score, max_score)
		    gui.text(0, 78, "Cur Score: " .. tostring(score))
		    gui.text(0, 66, "Max Score Frame: " .. tostring(max_score_frame))
		    gui.text(0, 54, "Max Score: " .. tostring(max_score))
		    joypad.set(inputTable)
		    emu.frameadvance()
        end
    end
	return {max_score, max_score_frame}
end


function main()
    sequence = random_sequence()
    clear_reset()
    res = rollout(sequence)
    print("score: " .. tostring(res[1]))
	for i=1,4 do
        clear_reset()
        rerun_res = rollout(sequence)
        print("score: " .. tostring(rerun_res[1]))
        assert(res[1] == rerun_res[1])
        assert(res[2] == rerun_res[2])
	end
end

main()
