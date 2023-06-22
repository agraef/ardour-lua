ardour {
   ["type"]    = "dsp",
   name        = "Barlow Arpeggiator",
   category    = "Effect",
   author      = "Albert Gräf",
   license     = "GPL",
   description = [[Simple monophonic arpeggiator example with sample-accurate triggering and velocities computed using Barlow's indispensability formula. This automatically adjusts to the current time signature and division to produce rhythmic accents in accordance with the meter by varying the note velocities in a given range.

Explanation of the controls:

- Division: Number of pulses to subdivide the meter as given by the time signature.
- Octave up/down: Sets the octave range for the output.
- Pattern: Choose any of the usual arpeggiator patterns (up, down, random, etc.).
- Min and Max Velocity: Range for automatic note velocities.
- Min and Max Filter: Pulse strength filter: Pulses outside the given pulse strength range (normalized values between 0 and 1) will be skipped.
- Latch: Enable latch mode (keep playing with no input).
]]
}

-- Copyright (c) 2023 Albert Gräf, GPLv3+

-- This is basically the same as simple_arp.lua (which see), but computes note
-- velocities using the Barlow indispensability formula which produces more
-- detailed rhythmic accents and handles arbitrary time signatures with ease.
-- It also offers a pulse filter which lets you filter notes by normalized
-- pulse strengths. Any pulse with a strength below/above the given
-- minimum/maximum values in the 0-1 range will be skipped.

-- NOTE: A limitation of the present algorithm is that only subdivisions <= 7
-- (a.k.a. septuplets) are supported, but if you really need more, then you
-- may also just change the time signature accordingly.

function dsp_ioconfig ()
   return { { midi_in = 1, midi_out = 1, audio_in = -1, audio_out = -1}, }
end

function dsp_options ()
   return { time_info = true }
end

function dsp_params ()
   return
      {
	 { type = "input", name = "Division", min = 1, max = 7, default = 1, integer = true },
	 { type = "input", name = "Octave up", min = 0, max = 5, default = 0, integer = true },
	 { type = "input", name = "Octave down", min = 0, max = 5, default = 0, integer = true },
	 { type = "input", name = "Pattern", min = 1, max = 6, default = 1, integer = true,
	   scalepoints =
	      {	["1 up"] = 1, ["2 down"] = 2, ["3 exclusive"] = 3, ["4 inclusive"] = 4, ["5 order"] = 5, ["6 random"] = 6 } },
	 { type = "input", name = "Min Velocity", min = 0, max = 127, default = 60, integer = true },
	 { type = "input", name = "Max Velocity", min = 0, max = 127, default = 120, integer = true },
	 { type = "input", name = "Min Filter", min = 0, max = 1, default = 0 },
	 { type = "input", name = "Max Filter", min = 0, max = 1, default = 1 },
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

-- Meter object
Meter = {}
Meter.__index = Meter

function Meter:new(m) -- constructor
   -- n = maximum subdivision, septoles seem to work reasonably well
   -- meter = meter, {4} a.k.a. common time is default
   -- indisp = indispensability tables, computed below
   local x = setmetatable({ n = 7, meter = {4}, indisp = {} }, Meter)
   x:compute(m)
   return x
end

-- Computes the best subdivision q in the range 1..n and pulse p in the range
-- 0..q so that p/q matches the given phase f in the floating point range 0..1
-- as closely as possible. Returns p, q and the absolute difference between f
-- and p/q. NB: Seems to work best for q values up to 7.

local function subdiv(n, f)
   local best_p, best_q, best = 0, 0, 1
   for q = 1, n do
      local p = math.floor(f*q+0.5) -- round towards nearest pulse
      local diff = math.abs(f-p/q)
      if diff < best then
	 best_p, best_q, best = p, q, diff
      end
   end
   return best_p, best_q, best
end

-- prime factors of integers
local function factor(n)
   local factors = {}
   if n<0 then n = -n end
   while n % 2 == 0 do
      table.insert(factors, 2)
      n = math.floor(n / 2)
   end
   local p = 3
   while p <= math.sqrt(n) do
      while n % p == 0 do
	 table.insert(factors, p)
	 n = math.floor(n / p)
      end
      p = p + 2
   end
   if n > 1 then -- n must be prime
      table.insert(factors, n)
   end
   return factors
end

-- reverse a table

local function reverse(list)
   local res = {}
   for k, v in ipairs(list) do
      table.insert(res, 1, v)
   end
   return res
end

-- arithmetic sequences

local function seq(from, to, step)
   step = step or 1;
   local sgn = step>=0 and 1 or -1
   local res = {}
   while sgn*(to-from) >= 0 do
      table.insert(res, from)
      from = from + step
   end
   return res
end

-- some functional programming goodies

local function map(list, fn)
   local res = {}
   for k, v in ipairs(list) do
      table.insert(res, fn(v))
   end
   return res
end

local function reduce(list, acc, fn)
   for k, v in ipairs(list) do
      acc = fn(acc, v)
   end
   return acc
end

local function collect(list, acc, fn)
   local res = {acc}
   for k, v in ipairs(list) do
      acc = fn(acc, v)
      table.insert(res, acc)
   end
   return res
end

local function sum(list)
   return reduce(list, 0, function(a,b) return a+b end)
end

local function prd(list)
   return reduce(list, 1, function(a,b) return a*b end)
end

local function sums(list)
   return collect(list, 0, function(a,b) return a+b end)
end

local function prds(list)
   return collect(list, 1, function(a,b) return a*b end)
end

-- indispensabilities (Barlow's formula)
local function indisp(q)
   function ind(q, k)
      -- prime indispensabilities
      function pind(q, k)
	 function ind1(q, k)
	    local i = ind(reverse(factor(q-1)), k)
	    local j = i >= math.floor(q / 4) and 1 or 0;
	    return i+j
	 end
	 if q <= 3 then
	    return (k-1) % q
	 elseif k == q-2 then
	    return math.floor(q / 4)
	 elseif k == q-1 then
	    return ind1(q, k-1)
	 else
	    return ind1(q, k)
	 end
      end
      local s = prds(q)
      local t = reverse(prds(reverse(q)))
      return
	 sum(
	    map(seq(1, #q),
		function(i)
		   return s[i] *
		      pind(q[i], (math.floor((k-1) % t[1] / t[i+1]) + 1) % q[i])
		end
	 ))
   end
   if type(q) == "number" then
      q = factor(q)
   end
   if type(q) ~= "table" then
      error("invalid argument, must be an integer or table of primes")
   else
      return map(seq(0,prd(q)-1), function(k) return ind(q,k) end)
   end
end

local function tableconcat(t1,t2)
   local res = {}
   for i=1,#t1 do
      table.insert(res, t1[i])
   end
   for i=1,#t2 do
      table.insert(res, t2[i])
   end
   return res
end

-- This optionally takes a new meter as argument and (re)computes the
-- indispensability tables. NOTE: This can be called (and the meter be
-- changed) at any time.
function Meter:compute(meter)
   meter = meter or self.meter
   -- a number is interpreted as a singleton list
   meter = type(meter) == "number" and {meter} or meter
   self.meter = meter
   local n = 1
   local m = {}
   for i,q in ipairs(meter) do
      if q ~= math.floor(q) then
	 error("meter: levels must be integer")
      elseif q < 1 then
	 error("meter: levels must be positive")
      end
      -- factorize each level as Barlow's formula assumes primes
      m = tableconcat(m, factor(q))
      n = n*q
   end
   self.beats = n
   self.last_q = nil
   if self.beats > 1 then
      self.indisp[1] = indisp(m)
      for q = 2, self.n do
	 local qs = tableconcat(m, factor(q))
	 self.indisp[q] = indisp(qs)
      end
   else
      self.indisp[1] = {0}
      for q = 2, self.n do
	 self.indisp[q] = indisp(q)
      end
   end
end

-- This takes the (possibly fractional) pulse and returns the pulse strength
-- along with the total number of beats.
function Meter:pulse(f)
   if type(f) ~= "number" then
      error("meter: beat index must be a number")
   elseif f < 0 then
      error("meter: beat index must be nonnegative")
   end
   local beat, f = math.modf(f)
   -- take the beat index modulo the total number of beats
   beat = beat % self.beats
   if self.n > 0 then
      local p, q = subdiv(self.n, f)
      if self.last_q then
	 local x = self.last_q / q
	 if math.floor(x) == x then
	    -- If the current best match divides the previous one, stick to
	    -- it, in order to prevent the algorithm from quickly changing
	    -- back to the root meter at each base pulse. XXFIXME: This may
	    -- stick around indefinitely until the meter changes. Maybe we'd
	    -- rather want to reset this automatically after some time (such
	    -- as a complete bar without non-zero phases)?
	    p, q = x*p, x*q
	 end
      end
      self.last_q = q
      -- The overall zero-based pulse index is beat*q + p. We add 1 to
      -- that to get a 1-based index into the indispensabilities table.
      local w = self.indisp[q][beat*q+p+1]
      return w, self.beats*q
   else
      local w = self.indisp[1][beat+1]
      return w, self.beats
   end
end

-- NOTE: Computing the necessary tables for the Barlow meter is a fairly
-- cpu-intensive operation, so changing the time signature mid-flight might
-- cause some cpu spikes and thus x-runs. To mitigate this, we cache each
-- meter as soon as we first encounter it, so that no costly recomputations
-- are needed later. An initial scan of the timeline makes sure that the cache
-- is well-populated from the get-go.

local last_mdiv
-- cached Barlow meters
local barlow_meters = { [4] = Meter:new() } -- common time
-- current Barlow meter
local barlow_meter = barlow_meters[4]

function dsp_init (rate)
   local loc = Session:locations():session_range_location()
   if loc then
      local tm = Temporal.TempoMap.read ()
      local a, b = loc:start():beats(), loc:_end():beats()
      if debug >= 1 then
	 print(loc:name(), a, b)
      end
      -- Scan through the timeline to find all time signatures and cache the
      -- resulting Barlow meters. Note that only care about the number of
      -- divisions here, that's all the algorithm needs.
      while a <= b do
	 local m = tm:meter_at_beats(a)
	 local mdiv = m:divisions_per_bar()
	 if not barlow_meters[mdiv] then
	    if debug >= 1 then
	       print(a, string.format("%d/%d", mdiv, m:note_value()))
	    end
	    barlow_meters[mdiv] = Meter:new(mdiv)
	 end
	 a = a:next_beat()
      end
   elseif debug >= 1 then
      print("empty session")
   end
end

function dsp_run (_, _, n_samples)
   assert (type(midiout) == "table")
   assert (type(time) == "table")
   assert (type(midiout) == "table")

   local ctrl = CtrlPorts:array ()
   -- We need to make sure that these are integer values. (The GUI enforces
   -- this, but fractional values may occur through automation.)
   local subdiv, up, down, mode = math.floor(ctrl[1]), math.floor(ctrl[2]), math.floor(ctrl[3]), math.floor(ctrl[4])
   local minvel, maxvel = math.floor(ctrl[5]), math.floor(ctrl[6])
   -- these are floating point values in the 0-1 range
   local minw, maxw = ctrl[7], ctrl[8]
   -- latch toggle
   local latch = ctrl[9] > 0
   -- rolling state
   local rolling = Session:transport_rolling ()
   -- whether the pattern must be recomputed, due to parameter changes or MIDI
   -- input
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
	 if latch and next(chord) == nil then
	    -- new pattern, get rid of latched notes
	    latched = {}
	 end
	 chord_index = chord_index+1
	 chord[num] = chord_index
	 if latch and latched[num] then
	    -- avoid double notes in latch mode
	    latched[num] = nil
	 else
	    changed = true
	 end
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
	    -- Detect meter changes and update the Barlow meter object
	    -- accordingly.
	    local mdiv = meter:divisions_per_bar()
	    if mdiv ~= last_mdiv then
	       if not barlow_meters[mdiv] then
		  if debug >= 1 then
		     print(bt, string.format("%d/%d", mdiv, meter:note_value()))
		  end
		  barlow_meters[mdiv] = Meter:new(mdiv)
	       end
	       barlow_meter = barlow_meters[mdiv]
	       last_mdiv = mdiv
	    end
	    -- Use the algorithm to determine the pulse weight.
	    local w, npulses = barlow_meter:pulse (p)
	    if debug >= 4 then
	       print(" Beat:", p, " Weight =", w, "/", npulses-1)
	    end
	    -- normalize the weight to the 0-1 range
	    w = w/(npulses-1)
	    -- filter notes
	    if w >= minw and w <= maxw then
	       -- compute the velocity, round to nearest integer
	       local v = minvel + w * (maxvel-minvel)
	       v = math.floor(v+0.5)
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
      end
   else
      -- transport not rolling; reset the last beat number
      last_beat = nil
   end

end
