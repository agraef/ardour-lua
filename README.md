# Ardour Lua Scripts

Here are some Lua scripts I wrote for an Ardour course. These require a fairly recent Ardour version (tested with Ardour 7.4). The simple_arp.lua script needs Ardour from git (7.4.291), since it relies on the [new time_info data](https://discourse.ardour.org/t/lua-arpeggiator-plugin-anyone/108862) for dsp scripts.

Documentation still needs to be written, so you'll have to take a look at the scripts themselves for further details. Below is just a quick rundown of the scripts that are currently available.

## Action Scripts

These are some helper scripts, mostly for doing twelve-tone music and similar serial stuff. They generally take a selected MIDI region as input.

- reihe.lua: This lets you quickly create a twelve-tone row from an empty MIDI region, or a region containing exactly one note (which will become the first note of the sequence). If the region already contains more than one note, invoking the script permutes the notes, so that you get a new sequence of the same notes each time you run the script on the same region.

- krebs.lua: Reverses a MIDI note sequence in time.

- umkehr.lua: Computes the inversion of a sequence (inverts intervals).

- tonleiter.lua: This is similar to reihe.lua, but lets you create different kinds of scales which you can choose from a dialog. (This is still unfinished, please send me a PR if you have other interesting scales to add.)

- meter.lua: This takes an existing note sequence, assigns pulse strengths to notes and maps these to note velocities and/or probabilities. The pulse strengths are computed using the time signature from the Ardour tempo map, by applying a formula by the contemporary composer Clarence Barlow which can deal with meters of any kind; please check the script for details.

## DSP Scripts

These are MIDI effects which can go as a plugin into a MIDI track. Currently the following scripts are available:

- simple_arp.lua: A simple monophonic arpeggiator which takes chords as MIDI input and turns them into arpeggios when transport is rolling. Various controls let you modify parameters such as velocities, octave range, and pattern mode.
- barlow_arp.lua: This is like simple_arp.lua, but uses the "indispensability" formula by contemporary composer Clarence Barlow (the same formula that's also used in meter.lua, see above) in order to compute more sophisticated pulse weights for any kind of meter. It produces more detailed rhythmic accents and includes a pulse filter. It's also a bit heavier on the cpu (occasionally).


Copyright © 2023 by Albert Gräf \<<aggraef@gmail.com>\>, please check the individual files for license information (MIT means the MIT license, GPL the GNU Public License v3 or later; if no license is given, the file is in the public domain). Please also check my GitHub page at https://agraef.github.io/.
