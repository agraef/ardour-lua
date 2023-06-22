ardour {
   ["type"]    = "dsp",
   name        = "Simple Arpeggiator",
   category    = "Effect",
   author      = "Albert Gräf",
   license     = "MIT",
   description = [[Simple monophonic arpeggiator example with sample-accurate triggering, demonstrates how to process the new time_info data along with BBT info from Ardour's tempo map.

Explanation of the controls:

- Division: Number of pulses to subdivide the meter as given by the time signature.
- Octave up/down: Sets the octave range for the output.
- Pattern: Choose any of the usual arpeggiator patterns (up, down, random, etc.).
- Velocity 1-3: Automatic note velocities for the different beat levels (bar, beat, subdivision pulse).
- Latch: Enable latch mode (keep playing with no input).
]]
}

-- Copyright (c) 2023 Albert Gräf, MIT License

-- The arpeggiator takes live note input from the user and constructs a new
-- cyclic pattern each time the input chord changes. Notes from the pattern
-- are triggered at each beat as transport is rolling. The plugin adjusts to
-- the current time signature, and also lets you subdivide the base pulse of
-- the meter with a control parameter in the setup. Note velocities for the
-- different levels can be adjusted in the setup as well.

-- NOTE: The scheme for varying note velocities in order to create rhythmic
-- accents is a bit on the simplistic side and only provides three distinct
-- velocity levels (bar, beat, and subdivision pulses). See barlow_arp.lua for
-- a more sophisticated implementation which uses Barlow's indispensability
-- formula.

-- The octave range can be adjusted up and down in the setup, notes from the
-- input chord are then repeated in the lower and/or upper octaves. The usual
-- pattern types are supported and can be selected in the setup: up, down,
-- up-down (exclusive and inclusive modes), order (notes are played in the
-- order in which they are input), and random. A toggle in the setup lets you
-- enable latch mode, in which the current pattern keeps playing if you
-- release all keys, until you start a new chord. All these parameters are
-- plugin controls which can be automated.

-- Last but not least, the plugin listens on all MIDI channels, and the last
-- MIDI channel used in the input also sets the MIDI channel for output. This
-- lets you play drumkits which expect their MIDI input on a certain MIDI
-- channel (usually channel 10), without having to fiddle with Ardour's MIDI
-- track parameters, provided that your MIDI controller can send data on the
-- appropriate MIDI channel.

function dsp_ioconfig ()
   return { { midi_in = 1, midi_out = 1, audio_in = -1, audio_out = -1}, }
end

function dsp_options ()
   return { time_info = true }
end

function dsp_params ()
   return
      {
	 { type = "input", name = "Division", min = 1, max = 16, default = 1, integer = true },
	 { type = "input", name = "Octave up", min = 0, max = 5, default = 0, integer = true },
	 { type = "input", name = "Octave down", min = 0, max = 5, default = 0, integer = true },
	 { type = "input", name = "Pattern", min = 1, max = 6, default = 1, integer = true,
	   scalepoints =
	      {	["1 up"] = 1, ["2 down"] = 2, ["3 exclusive"] = 3, ["4 inclusive"] = 4, ["5 order"] = 5, ["6 random"] = 6 } },
	 { type = "input", name = "Velocity 1", min = 0, max = 127, default = 100, integer = true },
	 { type = "input", name = "Velocity 2", min = 0, max = 127, default = 80, integer = true },
	 { type = "input", name = "Velocity 3", min = 0, max = 127, default = 60, integer = true },
	 { type = "input", name = "Latch", min = 0, max = 1, default = 0, toggled = true }
      }
end

-- debug level (1: print beat information in the log window, 2: also print the
-- current pattern whenever it changes, 3: also print note information, 4:
-- print everything)
local debug = 1

local chan = 0 -- MIDI output channel
local last_rolling -- last transport status, to detect changes
local last_beat -- last beat number
local last_num -- last note
local last_chan -- MIDI channel of last note
local last_up, last_down, last_mode -- previous params, to detect changes
local chord = {} -- current chord (note store)
local chord_index = 0 -- index of last chord note (0 if none)
local latched = {} -- latched notes
local pattern = {} -- current pattern
local index = 0 -- current pattern index (reset when pattern changes)

function dsp_run (_, _, n_samples)
   assert (type(midiout) == "table")
   assert (type(time) == "table")
   assert (type(midiout) == "table")

   local ctrl = CtrlPorts:array ()
   -- We need to make sure that these are integer values. (The GUI enforces
   -- this, but fractional values may occur through automation.)
   local subdiv, up, down, mode = math.floor(ctrl[1]), math.floor(ctrl[2]), math.floor(ctrl[3]), math.floor(ctrl[4])
   local vel1, vel2, vel3 = math.floor(ctrl[5]), math.floor(ctrl[6]), math.floor(ctrl[7])
   local latch = ctrl[8] > 0
   local rolling = Session:transport_rolling ()
   local changed = false

   if up ~= last_up or down ~= last_down or mode ~= last_mode then
      last_up = up
      last_down = down
      last_mode = mode
      changed = true
   end

   if not latch and next(latched) ~= nil then
      latched = {}
      changed = true
   end

   for k,ev in ipairs (midiin) do
      if not rolling then
	 -- pass through input notes
	 midiout[k] = ev
      end
      local status, num, val = table.unpack(ev.data)
      local ch = status & 0xf
      status = status & 0xf0
      if status == 0x80 or status == 0x90 and val == 0 then
	 if debug >= 4 then
	    print("note off", num, val)
	 end
	 -- keep track of latched notes
	 if latch then
	    latched[num] = chord[num]
	 else
	    changed = true
	 end
	 chord[num] = nil
      elseif status == 0x90 then
	 if debug >= 4 then
	    print("note on", num, val, "ch", ch)
	 end
	 if next(chord) == nil then
	    -- new pattern, get rid of latched notes
	    latched = {}
	 end
	 chord_index = chord_index+1
	 chord[num] = chord_index
	 -- avoid double notes in latch mode
	 latched[num] = nil
	 changed = true
	 chan = ch
      end
   end
   if changed then
      -- update the pattern
      pattern = {}
      function pattern_from_chord(pattern, chord)
	 for num, val in pairs(chord) do
	    table.insert(pattern, num)
	    for i = 1, down do
	       if num-i*12 >= 0 then
		  table.insert(pattern, num-i*12)
	       end
	    end
	    for i = 1, up do
	       if num+i*12 <= 127 then
		  table.insert(pattern, num+i*12)
	       end
	    end
	 end
      end
      pattern_from_chord(pattern, chord)
      if latch then
	 -- add any latched notes
	 pattern_from_chord(pattern, latched)
      end
      table.sort(pattern) -- order by ascending notes (up pattern)
      local n = #pattern
      if n > 0 then
	 if mode == 2 then
	    -- down pattern, reverse the list
	    table.sort(pattern, function(a,b) return a > b end)
	 elseif mode == 3 then
	    -- add the reversal of the list excluding the last element
	    for i = 1, n-2 do
	       table.insert(pattern, pattern[n-i])
	    end
	 elseif mode == 4 then
	    -- add the reversal of the list including the last element
	    for i = 1, n-1 do
	       table.insert(pattern, pattern[n-i+1])
	    end
	 elseif mode == 5 then
	    -- order the pattern by chord indices
	    local k = chord_index+1
	    local idx = {}
	    -- build a table of indices which also includes octaves up and
	    -- down, ordering them first by octave and then by index
	    function index_from_chord(idx, chord)
	       for num, val in pairs(chord) do
		  for i = 1, down do
		     if num-i*12 >= 0 then
			idx[num-i*12] = val - i*k
		     end
		  end
		  idx[num] = val
		  for i = 1, up do
		     if num+i*12 <= 127 then
			idx[num+i*12] = val + i*k
		     end
		  end
	       end
	    end
	    index_from_chord(idx, chord)
	    if latch then
	       index_from_chord(idx, latched)
	    end
	    table.sort(pattern, function(a,b) return idx[a] < idx[b] end)
	 elseif mode == 6 then
	    -- random order
	    for i = n, 2, -1 do
	       local j = math.random(i)
	       pattern[i], pattern[j] = pattern[j], pattern[i]
	    end
	 end
	 if debug >= 2 then
	    local s = "pattern:"
	    for i, num in ipairs(pattern) do
	       s = s .. " " .. num
	    end
	    print(s)
	 end
	 index = 0 -- reset pattern to the start
      else
	 chord_index = 0 -- pattern is empty, reset the chord index
	 if debug >= 2 then
	    print("pattern: <empty>")
	 end
      end
   end

   local k = #midiout + 1
   if last_rolling ~= rolling then
      last_rolling = rolling
      -- transport change, send all-notes off (we only do this when transport
      -- starts rolling, to silence any notes that may have been passed
      -- through beforehand; note that Ardour automatically sends
      -- all-notes-off to all MIDI channels anyway when transport is stopped)
      if rolling then
	 midiout[k] = { time = 1, data = { 0xb0+chan, 123, 0 } }
	 k = k+1
      end
   end

   if rolling then
      -- If transport is rolling, check whether a beat is due, so that we
      -- trigger the next note. We want to do this in a sample-accurate manner
      -- in order to avoid jitter, which makes things a little complicated.
      -- There are three cases to consider here:
      -- (1) Transport just started rolling or the playhead moved for some
      -- reason, in which case we *must* output the note immediately in order
      -- to not miss a beat (even if we're a bit late).
      -- (2) The beat occurs exactly at the beginning of a processing cycle,
      -- so we output the note immediately.
      -- (3) The beat happens some time during the cycle, in which case we
      -- calculate the sample at which the note is due.
      local denom = time.ts_denominator * subdiv
      -- beat numbers at start and end, scaled by base pulses and subdivisions
      local b1, b2 = denom/4*time.beat, denom/4*time.beat_end
      -- integral part of these
      local bf1, bf2 = math.floor(b1), math.floor(b2)
      -- sample times at start and end
      local s1, s2 = time.sample, time.sample_end
      -- current (nominal, i.e., unscaled) beat number, and its sample time
      local bt, ts
      if last_beat ~= math.floor(time.beat) or bf1 == b1 then
	 -- next beat is due immediately
	 bt, ts = time.beat, time.sample
      elseif bf2 > bf1 and bf2 ~= b2 then
	 -- next beat is due some time in this cycle (we're assuming contant
	 -- tempo here, hence this number may be off in case the tempo is
	 -- changing very quickly during the cycle -- so don't do that)
	 local d = math.ceil((b2-bf2)/(b2-b1)*(s2-s1))
	 assert(d > 0)
	 bt, ts = time.beat_end, time.sample_end - d
      end
      if ts then
	 -- save the last nominal beat so that we can detect sudden changes of
	 -- the playhead later (e.g., when transport starts rolling, or at the
	 -- end of a loop when the playhead wraps around to the beginning)
	 last_beat = math.floor(bt)
	 -- get the tempo map information
	 local tm = Temporal.TempoMap.read ()
	 local pos = Temporal.timepos_t (ts)
	 local bbt = tm:bbt_at (pos)
	 local meter = tm:meter_at (pos)
	 local tempo = tm:tempo_at (pos)
	 local n = #pattern
	 ts = ts - time.sample + 1
	 if debug >= 1 then
	    -- print some debugging information: bbt, fractional beat number,
	    -- sample offset, current meter, current tempo
	    print (string.format("%s - %g [%d] - %d/%d - %g bpm", bbt:str(),
				 math.floor(denom*bt)/denom, ts-1,
				 meter:divisions_per_bar(), meter:note_value(),
				 tempo:quarter_notes_per_minute()))
	 end
	 if last_num then
	    -- kill the old note
	    if debug >= 3 then
	       print("note off", last_num)
	    end
	    midiout[k] = { time = ts, data = { 0x80+last_chan, last_num, 100 } }
	    last_num = nil
	    k = k+1
	 end
	 if n > 0 then
	    -- calculate a fractional pulse number from the current bbt
	    local p = bbt.beats-1 + bbt.ticks / Temporal.ticks_per_beat
	    -- Calculate a basic velocity pattern: by default, 100 for the
	    -- first beat in a bar, 80 for the other non-fractional beats, 60
	    -- for everything else (subdivision pulses). These values can be
	    -- changed with the corresponding control. NOTE: There are much
	    -- more sophisticted ways to do this, but we try to keep things
	    -- simple here.
	    local v = vel3
	    if p == 0 then
	       v = vel1
	    elseif p == math.floor(p) then
	       v = vel2
	    end
	    --print("p", p, "v", v)
	    -- trigger the new note
	    index = index%n + 1
	    num = pattern[index]
	    if debug >= 3 then
	       print("note on", num, v)
	    end
	    midiout[k] = { time = ts, data = { 0x90+chan, num, v } }
	    last_num = num
	    last_chan = chan
	 end
      end
   else
      -- transport not rolling; reset the last beat number
      last_beat = nil
   end

end
