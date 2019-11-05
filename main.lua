-- one file because why not


local direction_window = 240
local generations = 50
local k = 4
local population_size = 32
local sequence_len = 120000

-- per-individual crossover prob (vs. mutation)
local crossover_prob = 0.3
-- per-frame mutation probablity
local mutation_prob = 0.01
-- per-mutation deletion probablity
local delete_prob = 0.5
-- crossover window size in number of frames
local crossover_window = 100

--client.speedmode(200)
client.SetSoundOn(false)

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


local locations = {38, 37, 0, 40, 12, 1, 41, 13, 51, 2}
local map_scores = {}
local location_score = 1
for i,addr in ipairs(locations) do
    map_scores[addr] = location_score
    location_score = location_score + 1
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


function sequence_copy(sequence)
	new_sequence = {}
	for i=1,sequence_len do
		new_sequence[i] = sequence[i]
	end
	return new_sequence
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


function mutate(sequence)
    for i=1,sequence_len do
        local rand = math.random()
        if rand < mutation_prob then
            button = random_button()
            rand = math.random()
            if rand < delete_prob then
                table.remove(sequence, i)
                table.insert(sequence, button)
            else
                sequence[i] = button
            end
        end    
    end
    assert(#sequence == sequence_len)
    return sequence
end

function crossover(sequence_a, sequence_b)
    local new_sequence = {}
    local i = 1
    while i < sequence_len do
        local rand = math.random()
        if rand > 0.5 then
            for j=i,i+crossover_window-1 do
                table.insert(new_sequence, sequence_a[j])
            end   
        else
            for j=i,i+crossover_window-1 do
                table.insert(new_sequence, sequence_b[j])
            end 
        end
        i = i + crossover_window
    end
    assert(#sequence_a == #sequence_b)
    assert(#new_sequence == #sequence_a)
    assert(#new_sequence == sequence_len)
    return new_sequence
end


function rollout(sequence, generation, id, all_max)
	local last_directions = {}

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
	local framecount = 0

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
            gui.text(0, 42, "All Time Max Score: " .. tostring(all_max))
            gui.text(0, 30, "Generation: " .. tostring(generation) .. " Id: " .. tostring(id))
			framecount = framecount + 1
			joypad.set(inputTable)
			emu.frameadvance()
		end
	end
	return {max_score, max_score_frame}
end

function rank_ab(a, b)
	if a['res'][1] > b['res'][1] then
		return true
	-- give priority to faster sequence
	elseif a['res'][1] == b['res'][1] then
		return a['res'][2] < b['res'][2]
	else
		return false
	end
end

function choose_crossover(population)
    local a = math.random(1, k)
    local b = math.random(1, k)
    while a == b do
        b = math.random(1, k)
    end
    return {['a']=population[a], ['b']=population[b]}
end

function main()
    population = {}
    all_max_score = 0
    best_score = 0
    print("initializing population...")
    for i=1,population_size do
	population[i] = random_sequence()
    end
    print("population initialized...")
    for gen=1,generations do
        idx_to_score = {}
        for i=1,population_size do
            clear_reset()
            res = rollout(population[i], gen, i, all_max_score)
            if res[1] > best_score then
                best_score = res[1]
            end
            table.insert(idx_to_score, {['idx']=i, ['res']=res})
            all_max_score = math.max(all_max_score, best_score)
	    print("score: " .. tostring(res[1]))
            print("best score: " .. tostring(best_score))
        end
        print("getting top k...")
        table.sort(idx_to_score, rank_ab)
        new_population = {}
        for i=1,population_size do
            print("ranked score # " .. tostring(i) .. ": " .. tostring(idx_to_score[i]['res'][1]))
        end
	    assert(idx_to_score[1]['res'][1] == all_max_score)
        for i=1,k do
            idx = idx_to_score[i]['idx']
			print(idx)
            new_population[i] = population[idx]
        end
        for i=k+1,population_size do

            local rand = math.random()
            if rand < crossover_prob then
                print("crossover...")
                chosen = choose_crossover(new_population)
                a = sequence_copy(chosen['a'])
                b = sequence_copy(chosen['b'])
                new_population[i] = crossover(a, b)
            else
                print("mutate...")
                chosen = new_population[math.random(1,k)]
				copy = sequence_copy(chosen)	
                new_population[i] = mutate(copy)
            end
        end
        population = new_population
    end
end

main()
