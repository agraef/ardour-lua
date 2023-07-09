# Ardour Lua Scripts

Here are some Lua scripts I wrote for an Ardour course. These require a fairly recent Ardour version (tested with Ardour 7.4 and 7.5). Note that the arpeggiator plugins (*_arp.lua) need Ardour 7.5 or later, since they rely on the [new time_info data](https://discourse.ardour.org/t/lua-arpeggiator-plugin-anyone/108862) for dsp scripts.

Documentation still needs to be written for the most part, so you'll have to take a look at the scripts themselves for further details. Below is a quick rundown of the scripts that are currently available. Please note that the action and dsp scripts can be found in corresponding subdirectories.

## Action Scripts

These are some helper scripts, mostly for doing twelve-tone music and similar serial stuff. They generally take a selected MIDI region as input.

- reihe.lua: This lets you quickly create a twelve-tone row from an empty MIDI region, or a region containing exactly one note (which will become the first note of the sequence). If the region already contains more than one note, invoking the script permutes the notes, so that you get a new sequence of the same notes each time you run the script on the same region.

- krebs.lua: Reverses a MIDI note sequence in time.

- umkehr.lua: Computes the inversion of a sequence (inverts intervals).

- tonleiter.lua: This is similar to reihe.lua, but lets you create different kinds of scales which you can choose from a dialog. (This is still unfinished, please send me a PR if you have other interesting scales to add.)

- meter.lua: This takes an existing note sequence, assigns pulse strengths to notes and maps these to note velocities and/or probabilities. The pulse strengths are computed using the time signature from the Ardour tempo map, by applying a formula by the contemporary composer Clarence Barlow which can deal with meters of any kind; please check the script for details.

## DSP Scripts

These are MIDI effects which go as a plugin into a MIDI track. Currently the following scripts are available:

- simple_arp.lua: A simple monophonic arpeggiator which takes chords as MIDI input and turns them into arpeggios when transport is rolling. Various controls let you modify parameters such as velocities, octave range, and pattern mode.
- barlow_arp.lua: This is like simple_arp.lua, but uses the "indispensability" formula by Clarence Barlow (the same formula that's also used in meter.lua, see above) in order to compute more sophisticated pulse strengths for any kind of meter. It produces more detailed rhythmic accents and includes a pulse filter which can be used to filter notes depending on the current pulse strength. It's also a bit heavier on the cpu (occasionally).
- raptor_arp.lua: This is a much more advanced arpeggiator based on Barlow's comprehensive theories of harmony and meter. It is really a full-blown algorithmic composition program in disguise. Note that the barlow_arp plugin is a much simpler program which only implements some of the basic features of the full Raptor program, but it's also much easier to use.

Sadly, Clarence Barlow passed away at the end of June 2023. The barlow_arp and raptor_arp plugins are dedicated to his memory. This is quite fitting since the original versions of these programs were developed in close collaboration with him. Rest in peace, Clarence.

## Using the Arpeggiators

Here is a brief introduction to the simple_arp and barlow_arp plugins. (The raptor_lua plugin is discussed in its own section below. It can be used in a similar fashion, but has a lot more parameters.)

Simply place the arpeggiator you prefer on a MIDI track, usually right in front of the instrument. There are a bunch of parameters that you can change, which can also be automated and saved in presets. The common ones are:

- **Latch** and **Sync**: These are toggles which engage latch and sync mode, respectively. In latch mode, the arpeggiator keeps playing if you release the keys on your MIDI keyboard, which makes changing chords easier. In sync mode, the arpeggiator playback is synchronized to bars and beats, so that the same note of the pattern sounds at each position in the cycle. This also works with patterns spanning multiple bars, and often creates a much smoother arpeggio than just cycling through the pattern (the default mode). Both modes are there to help imprecise players (like me) who tend to miss beats in chord changes, and make playing the arpeggiators much easier.
- **Bypass**: This toggle, when engaged, suspends the arpeggiator and passes through its input as is. This provides a means to monitor the input to the arpeggiator, but can also be used as a performance tool. (Disabling the plugin in Ardour has a similar effect, but doesn't silence existing notes during playback. The bypass toggle eliminates this problem.)
- **Division**: Sets the desired number of subdivisions of the beat. E.g., in a 4/4 meter a division value of 2 gives you duplets (eighth notes), 3 gives you (eighth) triplets, etc. The resulting number of steps you get is the numerator of the meter times the number of subdivisions.
- **Octave up/down**: Sets the octave range. Input notes will be repeated in the given number of octaves above and below the input.
- **Pattern**: Sets the style of pattern to play. The usual pattern types are supported and can be selected in the setup: **up**, **down**, up-down (**exclusive** and **inclusive** modes, which differ in whether the down sequence excludes or includes the highest note), **order** (notes are played in input order, which is useful, e.g., when playing a drumkit), and **random** (a new random order of the notes is generated after each chord change).
- **Gate**: Sets the length of notes as a fraction (0-1 range value) of the note division. Decreasing the value gives increasingly shorter staccato notes; a value of 1 means legato. The zero gate value (which wouldn't normally be terribly useful as it would indicate zero-length notes) is special. It *also* indicates legato and can thus be used just like a gate of 1, but also has a special meaning as "forced legato" in conjunction with the pulse filter of the Barlow Arpeggiator, see below.
- **Swing**: This is the customary swing control found on many hardware instruments which lets you specify the swing amount as a fraction ranging from 0.5 (no swing) to 0.75; 0.67 gives a triplet feel. This control is only available in the Simple Arpeggiator, but the Barlow Arpeggiator lets you create a triplet feel with a pulse filter instead, see below.

### Note Velocities

Both arpeggiators generate full-scale note velocities no matter what the input velocities are. The Simple Arpeggiator lets you select three different velocity levels for bar, beat and subdivision steps (**Velocity 1-3**).

The Barlow Arpeggiator uses a more sophisticated scheme which assigns a unique pulse strength to each step in a bar and lets you determine the output velocity range (**Min** and **Max Velocity**). Thus each step gets its unique velocity value in accordance with the current time signature and number of subdivisions. (The Min and Max values can also be reversed in order to get lower velocities for higher pulse strengths and vice versa.)

### Step Filters

The Barlow Arpeggiator also lets you filter notes by pulse strengths with the **Min** and **Max Filter** values. (This is made possible by the way unique pulse strengths are computed for each step. The Simple Arpeggiator doesn't have this feature, but offers a more traditional swing control instead.)

Raising the minimum strength gradually thins out the note sequence while retaining the more salient steps, and lowering the maximum strength produces an off-beat kind of rhythm. In particular, the pulse filter gives you a way to create a triplet feel without a swing control (e.g., in 4/4 try a triplet division along with a minimum pulse strength of 0.3).

Note that by default, the pulse filter will produce a rest for each skipped step, but you can also set the gate control to 0 to force each note to extend across the skipped steps instead. (This special "forced legato" gate setting will only make a difference in the Barlow Arpeggiator, and only if the pulse filter is active. Otherwise the 0 gate value has the same effect as a gate of 1.)

### Factory Presets

Both arpeggiators include some factory presets for illustration purposes, these can be selected from the presets dropdown in Ardour's plugin dialog as usual. (This needs Ardour 7.5-78 or later to work.) The list is still rather short at the time of this writing, so contributions are appreciated. If you have any cool presets that you might want to share, please let me know.

## Using Raptor

A complete description of the raptor_arp arpeggiator is beyond the scope of this README, so please check https://github.com/agraef/raptor-lua for the Pd version of this program, which offers extensive information on the Raptor algorithm and its features.

Raptor is really an algorithmic composition program driven by note input. It keeps track of the chords you play like any arpeggiator, but the note output it generates is in general much more varied than just playing back the input notes in a given pattern. This functionality is available with the "raptor" control. If it is disabled, Raptor will still apply some basic parameters to the velocities and note filters, and produce a traditional arpeggio from the notes you play. If it is enabled, however, Raptor will pick notes more or less at random from a set of *candidate notes* determined by various harmonic criteria. Depending on the parameter settings, the generated notes may be close to the input, or at least harmonically related, or they may be entirely different, so the output can change from tonal to atonal and even anti-tonal in a continuous way. Moreover, Raptor can also vary the tonal strength automatically for each step based on the corresponding pulse strength (a.k.a. Barlow indispensabilties).

In the following we give an overview of the available controls. In Ardour, the controls also have tooltips with a quick description, and there are various factory presets included for illustration purposes which you can use as a starting point for your own presets.

Ranges are given in parentheses. Continuous values use the 0 - 1 or -1 - +1 range and can be arbitrary floating point values. These generally denote probabilities or other normalized values (such as indispensabilities, harmonicities, and modulation values) expressed as percentages; some of these (in particular, the modulation parameters) can also be negative to reverse polarity. Switches are denoted 0/1 (off/on). Other ranges denote integer values, such as MIDI note or channel numbers, or enumerations such as the pattern and pitch tracker modes.

### MIDI Controls

These controls let you change the MIDI program and the MIDI channels for input and output.

- pgm (0-128): Sets the MIDI program (instrument sound) of a connected synthesizer. pgm = 0 (the default) means no change, otherwise a MIDI program change message is sent to the output channel.
- inchan, outchan (0-16): Sets the MIDI input and output channels. inchan = 0 (omni) means that notes on all channels will be received, otherwise MIDI input on all other channels will be ignored. outchan = 0 means that output goes to the input channel; otherwise it goes to the given MIDI channel. The default is inchan = outchan = 0, which means that MIDI input will be received on all channels and output goes to the last channel on which input was received. This is usually what you want, but setting the inchan lets you distinguish input from different MIDI controllers, and you may want to set outchan if different Raptor instances emit notes which are then routed to the same multitimbral instrument.

### Arpeggiator Modes

These controls are 0/1 switches which control various global modes of the arpeggiator.

- bypass, latch, mute (0/1): The bypass and latch controls work like with the other arpeggiators (see the previous section above). The mute control suppresses note output of the arpeggiator (the arpeggiator still keeps tracking input notes, so that it is ready to go immediately when you unmute it again).
- raptor (0/1): Toggles raptor mode, which enables additional functionality (see Raptor Controls below).
- loop (0/1), loopsize (0-16): This engages Raptor's built-in looper which repeats the last few bars of output from the arpeggiator. The loopsize control specifies the number of bars to loop. If input runs short then the looper will use what it has, but it needs at least one complete bar to commence loop playback. You can toggle the loop control at any time and it will switch between loop playback and arpeggiator output immediately. This can be handy if you want to loop a few bars created with the arpeggiator, e.g., to record that precious pattern before it vanishes forever, or if you need your hands free to play a solo on a different track.

### Arpeggiator Controls

These controls are always in effect, i.e., no matter whether raptor mode is on or off. The modulation controls (velmod, gatemod, pmod) vary the corresponding parameters according to normalized pulse weights (i.e., indispensabilities) of the current step. These values can also be negative which reverses polarity. E.g., velmod = 1 means that the note velocity varies from minvel to maxvel, *increasing* with the pulse weight, whereas velmod = -1 varies the velocities from maxvel to minvel, *decreasing* with the weight. If velmod = 0, then the velocity remains constant at the maxvel value. The other modulation controls work in an analogous fashion.

- division (1-7): Number of subdivisions of the base pulse (same as with the other arpeggiators).
- up, down (-2 - +2): Range of octaves up and down. This is a bit different from the other arpeggiators in that both values can also be negative. Typically, you'd use a positive (or zero) value for the up, and a negative (or zero) value for the down control. But you also might want to use positive or negative values for both, if you need to transpose the octave range up or down, respectively.
- mode (0-5): Sets the pattern mode. The collection is a bit different from the other arpeggiators, but should nevertheless be familiar and cover most use cases: 0 = random, 1 = up, 2 = down, 3 = up-down, 4 = down-up, 5 = outside-in (alternate between low and high notes). Default is 1 = up.
- minvel, maxvel (0-127), velmod (-1 - +1): Sets minimum and maximum velocity. The actual velocity varies with the pulse weight, by an amount given by the velmod control.
- gain (0-1): This determines a kind of "wet-dry" mix between the actual velocities of the input notes (averaged out by computing a velocity envelope) and the velocities computed by the arpeggiator (as set with the minvel and maxvel parameters). A gain value of 1 means that only the computed velocities will be used (giving you full scale velocities like with barlow_arp and simple_arp). A lower gain value reduces the velocities according to how loud you actually play, thus producing human dynamic variation and giving you more possibilities for expression. Note that in either case the output velocities *will* be shaped by the computed velocity values, so that the rhythmic pattern remains present.
- gate (0-1), gatemod (-1 - +1): Sets the gate (length of each note as a fraction of the pulse length). The actual gate value varies with the pulse weight, by an amount given by the gatemod control. An actual gate value of 0 forces legato, as with barlow_arp.
- wmin, wmax (0-1): Deterministic pulse filter (same as in barlow_arp). Pulses with a weight outside the given wmin - wmax range will be filtered out.
- pmin, pmax (0-1), pmod (-1 - +1): Probabilistic pulse filter. The given minimum and maximum probability values along with the corresponding modulation determine through a random choice whether a pulse produces any notes. You can disable this by setting pmax = 1 and pmod = 0 (which are the defaults).

### Raptor Controls

These controls only affect the arpeggiator if it runs in raptor mode.The modulation controls (hmod, prefmod, smod, nmod) work as described above to vary the corresponding parameter with the pulse weight of the current step. The controls filter and order candidate output notes according to various criteria, which determines which notes are eventually output by the arpeggiator in each step.

- hmin, hmax (0-1), hmod (-1 - +1): This filters candidate notes by comparing their modulated average harmonicity with respect to the input chord to the given bounds hmin and hmax. The harmonicity function being used here is a variation of the one being used in Barlow's Autobusk program, please see my [ICMC 2006 paper](https://github.com/agraef/raptor-lua/blob/master/scale.pdf), Section 8, for details. Some interesting harmonicity thresholds are at about 0.21 (the 5th), 0.17  (the 4th), 0.1 (major 2nd and 3rd), and 0.09 (minor 7th and 3rd). To hear the effect, try varying the hmin value while playing a single note.
- pref (-1 - +1), prefmod (-1 - +1): This parameter doesn't affect the candidate notes, but sorts them according to harmonic preference. The arpeggiator will prefer notes with high harmonicity if the value is positive, notes with low harmonicity if it is negative, and simply choose notes at random if it is zero. The effective harmonicity value also varies according to the prefmod modulation control with the current pulse weight. Basically, a high pref value tends towards tonal, a low one towards anti-tonal, and zero towards atonal music, but of course this also depends on the hamonicity range set with the hmin and hmax parameters. Within those limits, the pref control can be very effective; e.g., with pref = 1 it will give you a high degree of tonality even if hmin is very low, as long as it has enough highly harmonic candidate notes to choose from.
- smin, smax (-12 - +12), smod (-1 - +1): Determines the minimum and maximum step size in semitones between consecutive steps. Note that these values can also be negative, allowing down-steps in an "up" pattern, and the step size can be modulated according to pulse weight. Since Raptor picks notes more or less at random, these parameters give you some control over how large the steps can be. You can also effectively disable this (set smin = 0 and smax = 12), but in this case make sure to also enable uniq mode (see below), so that you don't end up playing the same note over and over again.
- nmax (0-10), nmod (-1 - +1): Sets the maximum number of simultaneous notes (modulated according to pulse weight). Thus Raptor, unlike the other arpeggiators, can play more than one note at a time, but this only works in raptor mode.
- uniq (0/1): When set to 1, makes sure that notes are not repeated between consecutive steps.
- pitchhi, pitchlo (-36 - +36), pitchtracker (0-3): Set this to extend the octave range (up/down) by the given number of semitones. This gives you finer control over the range of candidate notes in raptor mode. Also, using the pitchtracker control, you can have the arpeggiator follow the (highest and lowest) notes you play and automatically adjust the range of candidate notes accordingly, taking into account the up/down and pitchhi/pitchlo settings. The pitch tracker can be run in four different modes, 0 = off, 1 = on (follow both high and low notes), 2 = treble (only follow the high notes), 3 = bass (only follow the low notes).


Copyright © 2023 by Albert Gräf \<<aggraef@gmail.com>\>, please check the individual files for license information. MIT means the MIT license (see MIT-LICENSE.txt), GPL the GNU Public License v3 or later (see COPYING); if no license is given, the file is in the public domain. Please also check my GitHub page at https://agraef.github.io/.
