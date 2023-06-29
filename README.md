# Ardour Lua Scripts

Here are some Lua scripts I wrote for an Ardour course. These require a fairly recent Ardour version (tested with Ardour 7.4 and 7.5). Note that the arpeggiator plugins (simple_arp.lua and barlow_arp.lua) need Ardour 7.5 or later, since they rely on the [new time_info data](https://discourse.ardour.org/t/lua-arpeggiator-plugin-anyone/108862) for dsp scripts.

Documentation still needs to be written for the most part, so you'll have to take a look at the scripts themselves for further details. Below is a quick rundown of the scripts that are currently available. Please note that the action and dsp scripts can be found in corresponding subdirectories.

## Action Scripts

These are some helper scripts, mostly for doing twelve-tone music and similar serial stuff. They generally take a selected MIDI region as input.

- reihe.lua: This lets you quickly create a twelve-tone row from an empty MIDI region, or a region containing exactly one note (which will become the first note of the sequence). If the region already contains more than one note, invoking the script permutes the notes, so that you get a new sequence of the same notes each time you run the script on the same region.

- krebs.lua: Reverses a MIDI note sequence in time.

- umkehr.lua: Computes the inversion of a sequence (inverts intervals).

- tonleiter.lua: This is similar to reihe.lua, but lets you create different kinds of scales which you can choose from a dialog. (This is still unfinished, please send me a PR if you have other interesting scales to add.)

- meter.lua: This takes an existing note sequence, assigns pulse strengths to notes and maps these to note velocities and/or probabilities. The pulse strengths are computed using the time signature from the Ardour tempo map, by applying a formula by the contemporary composer Clarence Barlow which can deal with meters of any kind; please check the script for details.

## DSP Scripts

These are MIDI effects which go as a plugin into a MIDI track. Currently the following two arpeggiator scripts are available:

- simple_arp.lua: A simple monophonic arpeggiator which takes chords as MIDI input and turns them into arpeggios when transport is rolling. Various controls let you modify parameters such as velocities, octave range, and pattern mode.
- barlow_arp.lua: This is like simple_arp.lua, but uses the "indispensability" formula by Clarence Barlow (the same formula that's also used in meter.lua, see above) in order to compute more sophisticated pulse strengths for any kind of meter. It produces more detailed rhythmic accents and includes a pulse filter which can be used to filter notes depending on the current pulse strength. It's also a bit heavier on the cpu (occasionally).

### Using the Arpeggiators

Simply place the arpeggiator you prefer on a MIDI track, usually right in front of the instrument. There are a bunch of parameters that you can change, which can also be automated and saved in presets. The common ones are:

- **Latch** and **Sync**: These are toggles which engage latch and sync mode, respectively. In latch mode, the arpeggiator keeps playing if you release the keys on your MIDI keyboard, which makes changing chords easier. In sync mode, the arpeggiator playback is synchronized to bars and beats, so that the same note of the pattern sounds at each position in the cycle. This also works with patterns spanning multiple bars, and often creates a much smoother arpeggio than just cycling through the pattern (the default mode). Both modes are there to help imprecise players (like me) who tend to miss beats in chord changes, and make playing the arpeggiators much easier.
- **Division**: Sets the desired number of subdivisions of the beat. E.g., in a 4/4 meter a division value of 2 gives you duplets (eighth notes), 3 gives you (eighth) triplets, etc. The resulting number of steps you get is the numerator of the meter times the number of subdivisions.
- **Octave up/down**: Sets the octave range. Input notes will be repeated in the given number of octaves above and below the input.
- **Pattern**: Sets the style of pattern to play. The usual pattern types are supported and can be selected in the setup: **up**, **down**, up-down (**exclusive** and **inclusive** modes, which differ in whether the down sequence excludes or includes the highest note), **order** (notes are played in input order, which is useful, e.g., when playing a drumkit), and **random** (a new random order of the notes is generated after each chord change).
- **Gate**: Sets the length of notes as a fraction (0-1 range value) of the note division. Decreasing the value gives increasingly shorter staccato notes; a value of 1 means legato. The zero gate value (which wouldn't normally be terribly useful as it would indicate zero-length notes) is special. It *also* indicates legato and can thus be used just like a gate of 1, but also has a special meaning as "forced legato" in conjunction with the pulse filter of the Barlow Arpeggiator, see below.
- **Swing**: This is the customary swing control found on many hardware instruments which lets you specify the swing amount as a fraction ranging from 0.5 (no swing) to 0.75; 0.67 gives a triplet feel. This control is only available in the Simple Arpeggiator, but the Barlow Arpeggiator lets you create a triplet feel with a pulse filter instead, see below.

#### Note Velocities

Both arpeggiators generate full-scale note velocities no matter what the input velocities are. The Simple Arpeggiator lets you select three different velocity levels for bar, beat and subdivision steps (**Velocity 1-3**).

The Barlow Arpeggiator uses a more sophisticated scheme which assigns a unique pulse strength to each step in a bar and lets you determine the output velocity range (**Min** and **Max Velocity**). Thus each step gets its unique velocity value in accordance with the current time signature and number of subdivisions. (The Min and Max values can also be reversed in order to get lower velocities for higher pulse strengths and vice versa.)

#### Step Filters

The Barlow Arpeggiator also lets you filter notes by pulse strengths with the **Min** and **Max Filter** values. (This is made possible by the way unique pulse strengths are computed for each step. The Simple Arpeggiator doesn't have this feature, but offers a more traditional swing control instead.)

Raising the minimum strength gradually thins out the note sequence while retaining the more salient steps, and lowering the maximum strength produces an off-beat kind of rhythm. In particular, the pulse filter gives you a way to create a triplet feel without a swing control (e.g., in 4/4 try a triplet division along with a minimum pulse strength of 0.3).

Note that by default, the pulse filter will produce a rest for each skipped step, but you can also set the gate control to 0 to force each note to extend across the skipped steps instead. (This special "forced legato" gate setting will only make a difference in the Barlow Arpeggiator, and only if the pulse filter is active. Otherwise the 0 gate value has the same effect as a gate of 1.)

#### Factory Presets

Both arpeggiators include some factory presets for illustration purposes, these can be selected from the presets dropdown in Ardour's plugin dialog as usual. (This needs Ardour 7.5-78 or later to work.) The list is still rather short at the time of this writing, though, so contributions are appreciated. If you have any cool presets that you might want to share, please let me know.


Copyright © 2023 by Albert Gräf \<<aggraef@gmail.com>\>, please check the individual files for license information (MIT means the MIT license, GPL the GNU Public License v3 or later; if no license is given, the file is in the public domain). Please also check my GitHub page at https://agraef.github.io/.
