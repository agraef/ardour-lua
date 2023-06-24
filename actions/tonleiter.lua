ardour { ["type"] = "EditorAction", name = "Tonleiter" }

-- Construct a scale (German "Tonleiter"). This assumes that a MIDI region
-- with (at least) one note is selected. It lets you pick a scale from a
-- dropdown in a dialog and adds the remaining notes for the chosen scale,
-- spaced apart at whatever the length of the first note is.

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
      -- scales
      local scales = {
	 -- chromatic
	 {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12},
	 -- major
	 {0, 2, 4, 5, 7, 9, 11, 12},
	 -- melodic minor
	 {0, 2, 3, 5, 7, 9, 11, 12},
	 -- harmonic minor
	 {0, 2, 3, 5, 7, 8, 11, 12},
	 -- lydian
	 {0, 2, 4, 6, 7, 9, 11, 12},
	 -- mixolydian
	 {0, 2, 4, 5, 7, 9, 10, 12},
	 -- whole tone
	 {0, 2, 4, 6, 8, 10, 12},
      }
      local dg_opt = {
	 {
	    type = "dropdown", key = "scale", title = "Scale",
	    values = {
	       ["1 Chromatic"] = 1, ["2 Major"] = 2,
	       ["3 Melodic Minor"] = 3, ["4 Harmonic Minor"] = 4,
	       ["5 Lydian"] = 5, ["6 Mixolydian"] = 6,
	       ["7 Whole Tone"] = 7
	    }
	 }
      }
      local dg = LuaDialog.Dialog ("Select Scale", dg_opt)
      local rv = dg:run()
      local scale
      if rv then
	 scale = scales[rv.scale]
      else
	 return
      end
      local sel = Editor:get_selection ()
      local tm = Temporal.TempoMap.read ()
      for r in sel.regions:regionlist ():iter () do
	 local mr = r:to_midiregion ()
	 if mr:isnil () then goto next end

	 print_region (r)
	 local mm = mr:model ()
	 local nl = ARDOUR.LuaAPI.note_list (mm)
	 local n = nl:front ()
         if not n:isnil () then
	    -- start from the first note, spacing by length of that note
	    local p, t, l, v = n:note (), n:time (), n:length (), n:velocity ()
	    local mc = mm:new_note_diff_command ("Tonleiter")
	    for i = 2, #scale do
	       t = t + l
	       local n2 = ARDOUR.LuaAPI.new_noteptr
	       (n:channel(), t, l, p + scale[i], v)
	       print_note (n2)
	       mc:add (n2)
	    end
	    mm:apply_command (Session, mc)
	 end
	 ::next::
      end
end end
