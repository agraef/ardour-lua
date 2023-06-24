ardour { ["type"] = "EditorAction", name = "Reihe" }

function factory () return function ()
      -- for debugging purposes
      local debug = true
      local function print_region(r)
	 if debug then
	    print (r:name (), "Pos:", r:position ():beats (),
		   "Start:", r:start ():beats ())
	 end
      end
      local function print_note(n)
	 if debug then
	    print (" Note @", n:time (), n:note (),
		   ARDOUR.ParameterDescriptor.midi_note_name (n:note ()),
		   "Vel:", n:velocity ())
	 end
      end
      local sel = Editor:get_selection ()
      local tm = Temporal.TempoMap.read ()
      for r in sel.regions:regionlist ():iter () do
	 local mr = r:to_midiregion ()
	 if mr:isnil () then goto next end

	 print_region (r)
	 local mm = mr:model ()
	 local nl = ARDOUR.LuaAPI.note_list (mm)
	 if nl:empty () then
	    -- the region is empty (no notes), create a scale of 12 rising
	    -- pitches with medium velocity
	    local p, t, l = 60, r:start ():beats (), Temporal.Beats (1, 0)
	    local mc = mm:new_note_diff_command ("Reihe")
	    for i = 1, 12 do
	       -- 0 = MIDI channel 1, 64 = medium velocity
	       local n2 = ARDOUR.LuaAPI.new_noteptr (0, t, l, p, 64)
	       print_note (n2)
	       mc:add (n2)
	       -- notes are spaced l beats apart, increasing pitch by 1
	       t = t + l
	       p = p + 1
	    end
	    mm:apply_command (Session, mc)
	 elseif nl:size () == 1 then
	    -- we have exactly one note, create a rising scale at that note
	    -- (same as tonleiter.lua)
	    local n = nl:front ()
	    local p, t, l = n:note (), n:time (), n:length ()
	    local mc = mm:new_note_diff_command ("Reihe")
	    for i = 2, 12 do
	       -- notes are spaced l beats apart, increasing pitch by 1
	       t = t + l
	       p = p + 1
	       local n2 = ARDOUR.LuaAPI.new_noteptr
	       (n:channel(), t, l, p, n:velocity ())
	       print_note (n2)
	       mc:add (n2)
	    end
	    mm:apply_command (Session, mc)
	 else
	    -- we have some notes (more than one), permute them at random
	    local x = {}
	    local k = 0
	    for n in nl:iter () do
	       k = k+1
	       x[k] = { note = n:note (), vel = n:velocity ()}
	    end
	    -- random permutation of notes and velocities
	    for i = k, 2, -1 do
	       local j = math.random(i)
	       x[i], x[j] = x[j], x[i]
	    end
	    -- shuffle the notes using the computed permutation
	    k = 0
	    local mc = mm:new_note_diff_command ("Reihe")
	    for n in nl:iter () do
	       k = k+1
	       local n2 = ARDOUR.LuaAPI.new_noteptr
	       (n:channel(), n:time (), n:length (), x[k].note, x[k].vel)
	       print_note (n2)
	       mc:remove (n)
	       mc:add (n2)
	    end
	    mm:apply_command (Session, mc)
	 end
	 ::next::
      end
end end
