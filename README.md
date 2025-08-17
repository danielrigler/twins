## Twins

A randomized dual granular sample playground for Monome Norns.

![Screenshot](https://llllllll.co/uploads/default/original/3X/d/4/d4f2077ef24aeceebba416defd2e1cce5140f37a.png)

Inspired by @cfd90’s Twine and contains influence and code from a lot of other norns users. This is basically Twine on steroids. A granular playground. It contains a lot of effects and extra granular parameters. You can turn off granular processing and use this as a normal sample player with effects. Live input processing is also possible. My main goal was building a tool for creating nice ambient soundscapes. And no problem if you do not have external controllers. I have tweaked the GUI and controls, so it is playable even with only a norns. Let me know if you find this useful.

![Screenshot](https://llllllll.co/uploads/default/original/3X/c/f/cf1c21b15a1879fca18d932858d2aa94f17a62f6.png)

**Some of the new features:**
* Reverb, delay, tape effects, shimmer, EQ, filters, bit reduction, etc.
* Flexible volume control
* Extra granular parameters, increased parameter ranges
* Smooth transition interpolation
* Freely assignable LFOs with randomization
* On screen navigation with parameter locking
* Symmetry mode and mirroring
* Live input processing

### Requirements
norns / norns shield  
_some features might require a pi4 based unit. If you hear clicks and crackles try turning off a few effects. Most expensive ones are reverb and analog tape sim_

### Documentation
**E1**: Master Volume  
**K1**+**E2** or **K1**+**E3**: Volume 1/2  
**K1**+**E1**: Crossfade Volumes  
**K2**/**K3**: Navigate  
**E2**/**E3**: Adjust Parameters  
**K2**+**K3**: Lock Parameters  
**K2**+**K3**: HP/LP Filter toggle  
**K1**+**K2** or **K1**+**K3**: Randomize 1/2  

### Discussion
**[FORUM](https://llllllll.co/t/twins/71052)**
### Download
**v0.36**
install from Maiden Project Manager, or from Maiden REPL:
```
;install https://github.com/danielrigler/twins
```
do not forget to restart.

### Version history
* **v0.36** - Realtime seek position display, small tweaks. 
* **v0.35** - Delay tweaks, bitcrusher, stereo field rotation.
* **v0.34** - Added delay modulation.
* **v0.33** - Ping-Pong delay, smaller tweaks.
* **v0.32** - Live mode tweaks, tape saturation.
* **v0.31** - Live mode, rebuilt delay.
* **v0.30** - Symmetry, dry mode, actions.
* **v0.29** - Optimizations and tweaks.
* **v0.28** - Shimmer update.
* **v0.26** - Switch to JPverb. Locking improvements. 
* **v0.25** - Improved shimmer. Small tweaks and fixes. 
* **v0.24** - Added tape wobble. 
* **v0.23** - Added shimmer again. 0 mix is bypass to save resources. 
* **v0.22** - Seek tweak, shift vis, random tapes.
* **v0.21** - LFO bugfix, stereo width.
* **v0.20** - Added a deeper subharmonic, LFO tweaks.
* **v0.19** - Added grain octave variance.
* **v0.18** - Tap tempo for delay, engine tweaks. 
* **v0.17** - GUI changes. Lots of LFO, randomization and locking tweaks. Removed bitcrusher. 
* **v0.16** - Added Shimmer and EQ. LFO tweaks. 
* **v0.15** - Added bitcrusher, small tweaks. 
* **v0.14** - Randomization and interpolation overhaul.
* **v0.13** - Added grain size randomization controls per voice.
* **v0.12** - Volume fix, reverse direction mod
* **v0.11** - Minor tweaks and optimizations. Increased grain size range. Locking enhancements.
* **v0.10** - First release.
