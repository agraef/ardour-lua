ardour {
   ["type"] = "EditorAction", name = "Meter",
   license     = "GPL",
   author      = "Albert Gräf",
   description = [[Add 'Inline Scope' Lua Processor to all Tracks]]
}

--[[

   This is based on Barlow's theory of meter and rhythm as explained in his
   book "On Musiquantics" (Section 22, "A Quantitative Approach to
   Metre"). The underlying algorithm generates rhythmic patterns for any given
   meter in an automatic fashion, assigning a unique weight to each pulse.

   In extension of the original method, our version of the algorithm also
   works with fractional pulses (duplets, triplets, etc., up to
   septuplets). If your note material calls for a still finer grid, then you
   can just choose the time signature in Ardour accordingly (e.g., using 8/8
   or 16/16 in lieu of 4/4). The algorithm can deal with any meter, including
   rather exotic ones such as 11/8 or 17/16, and will usually produce a
   fairly convincing rhythmic pattern for each meter.

   This action is designed to work on the selected MIDI region(s), so you
   first need to select at least one such region in the Ardour editor
   view. Time signatures and BBT (bar-beat-ticks) information is taken from
   the Ardour tempo map. The pulse weights computed from these can be used to
   apply the following transformations to each note list:
   
   - Map the note velocities to the given velocity range minvel..maxvel
     depending on the pulse weights.

   - Filter notes using weighted note probabilities, assigning each note a
     probability in the given range minprob..maxprob depending on the pulse
     weight.

   In either case, it is possible to "reverse polarity" of the mapping by
   swapping the min and max values. E.g., with minvel > maxvel, velocities
   will be assigned so that the *largest* weight corresponds to the *lowest*
   velocity and vice versa. Similarly, with minprob > maxprob, note
   probabilities will be *smaller* for *larger* pulse weights and vice versa.
   
   Mapping note velocities is enabled, filtering by probabilities disabled by
   default. In the interactive version, all parameters can be set using a
   parameter dialog invoked each time the action is called.

]]

function factory () return function ()

-- Set this to true for debugging output in the scripting console.
local debug = true

-- Set this to true to prompt for the minvel, maxvel parameters.
local interactive = true

-- Set this to the default minimum and maximum velocities and probabilities.
local param = { vel = true, minvel = 60, maxvel = 100,
		prob = false, minprob = 0, maxprob = 100 }

if meter_global_param then
   param = meter_global_param
end
if interactive then
   local dialog_options = {
      { type = "checkbox", key = "vel", default = param.vel, title = "Velocities" },
      { type = "number", key = "minvel", title = "minvel",  min = 0, max = 127, step = 1, digits = 0, default = param.minvel },
      { type = "number", key = "maxvel", title = "maxvel",  min = 0, max = 127, step = 1, digits = 0, default = param.maxvel },
      { type = "checkbox", key = "prob", default = param.prob, title = "Probabilities" },
      { type = "number", key = "minprob", title = "minprob",  min = 0, max = 100, step = 1, digits = 0, default = param.minprob },
      { type = "number", key = "maxprob", title = "maxprob",  min = 0, max = 100, step = 1, digits = 0, default = param.maxprob },
   }
   local dg = LuaDialog.Dialog ("Meter Setup", dialog_options)
   param = dg:run()
   if param then
      -- safe the data for the next invocation
      meter_global_param = param
   else
      -- dialog canceled, exit
      return
   end
end

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

-- for debugging purposes
local function print_region(r, tm)
   if debug then
      local meter = tm:meter_at(r:position ())
      local tempo = tm:tempo_at(r:position ()):to_tempo ()
      print (r:name (), "Pos:", r:position ():beats (),
	     "Start:", r:start ():beats (),
	     "Meter:", meter:divisions_per_bar (), "/",
	     meter:note_value (),
	     "Tempo:", tempo:quarter_notes_per_minute ())
   end
end
local function print_meter(meter)
   if debug then
      print (" Meter:", meter:divisions_per_bar (), "/",
	     meter:note_value ())
   end
end
local function print_note(n, msg)
   if debug then
      if msg then
	 print (" Note @", n:time (), n:note (),
		ARDOUR.ParameterDescriptor.midi_note_name (n:note ()),
		msg)
      else
	 print (" Note @", n:time (), n:note (),
		ARDOUR.ParameterDescriptor.midi_note_name (n:note ()),
		"Vel:", n:velocity ())
      end
   end
end

local minvel, maxvel = param.minvel, param.maxvel
local minprob, maxprob = param.minprob, param.maxprob
local sel = Editor:get_selection ()
local tm = Temporal.TempoMap.read ()
for r in sel.regions:regionlist ():iter () do
   local mr = r:to_midiregion ()
   if mr:isnil () then goto next end

   print_region (r, tm)
   local pos = r:position ()
   local pos_beats = pos:beats ()
   -- Initialize the meter to what it is at the beginning of the region.
   -- We only need to check the number of pulses here, the base pulse is
   -- taken care of by Ardour in its BBT values already.
   local m = tm:meter_at(pos):divisions_per_bar()
   local barlow_meter = Meter:new (m)
   local mm = mr:model ()
   local nl = ARDOUR.LuaAPI.note_list (mm)
   local mc = mm:new_note_diff_command ("Meter")
   for n in nl:iter () do
      -- Check for meter changes; these may occur at any time. NOTE:
      -- Since Ardour only updates the meter value *after* the
      -- corresponding time signature marker, we're checking at the
      -- *end* of the current note where it will have its proper value.
      local meter = tm:meter_at_beats (n:time() + n:length() + pos_beats)
      local m1 = meter:divisions_per_bar ()
      if m1 ~= m then
	 -- Meter has changed, update the table accordingly.
	 print_meter (meter)
	 barlow_meter:compute (m1)
	 m = m1
      end
      -- Calculate the current pulse number for the Barlow meter. Using the
      -- tempo map, Ardour gives us the BBT (bar-beats-ticks). We only need
      -- the beats and ticks, mapping these to zero-based fractional pulse
      -- numbers for our algorithm.
      local t = tm:bbt_at_beats (n:time () + pos_beats)
      -- Ardour gives 1-based beat numbers, so we need to subtract 1 here, and
      -- calculate the fractional pulse number using Ardour's global
      -- ticks_per_beat value.
      local p = t.beats-1 + t.ticks / Temporal.ticks_per_beat
      -- Use the algorithm to determine the pulse weight.
      local w, npulses = barlow_meter:pulse (p)
      if debug then
	 print(" Beat:", p, " Weight =", w, "/", npulses-1)
      end
      -- normalize the weight and compute the velocity from that value
      w = w/(npulses-1)
      local vel = n:velocity ()
      if param.vel then
	 vel = minvel + w * (maxvel-minvel)
	 -- round to nearest integer
	 vel = math.floor(vel+0.5)
      end
      -- compute weighted note probabilities
      local prob = 100
      if param.prob and (maxprob < 100 or minprob ~= maxprob) then
	 -- note probability
	 prob = minprob + w * (maxprob-minprob)
      end
      if math.random(100) > prob then
	 -- filter out
	 print_note (n, "**skipped**")
	 mc:remove (n)
      elseif param.vel then
	 -- change velocity
	 local n2 = ARDOUR.LuaAPI.new_noteptr
	 (n:channel(), n:time (), n:length (), n:note (), vel)
	 print_note (n2)
	 mc:remove (n)
	 mc:add (n2)
      end
   end
   mm:apply_command (Session, mc)
   ::next::
end

end end
