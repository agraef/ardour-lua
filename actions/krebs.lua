ardour { ["type"] = "EditorAction", name = "Krebs" }

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
	 local n = nl:back ()
         if n then
	    -- p is the end of the sequence
	    local p = n:time () + n:length ()
	    local mc = mm:new_note_diff_command ("Krebs")
	    for n in nl:iter () do
	       -- reflect the sequence so that it runs from right to left,
	       -- starting at p
	       local p2 = p - n:time () - n:length ()
	       local n2 = ARDOUR.LuaAPI.new_noteptr
	       (n:channel(), p2, n:length (), n:note (), n:velocity ())
	       print_note (n2)
	       mc:remove (n)
	       mc:add (n2)
	    end
	    mm:apply_command (Session, mc)
	 end
	 ::next::
      end
end end
