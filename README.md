## Twins

A randomized dual granular sample playground for Monome Norns.

![Screenshot](https://llllllll.co/uploads/default/original/3X/d/4/d4f2077ef24aeceebba416defd2e1cce5140f37a.png)

Inspired by @cfd90’s Twine and contains influence and code from other norns users. This is basically Twine on steroids. A granular playground. It contains a lot of effects and extra granular parameters. You can turn off granular processing and use this as a normal sample player with effects. Live input processing is also possible. My main goal was building a tool for creating nice ambient soundscapes. And no problem if you do not have external controllers. I have tweaked the GUI and controls, so it is playable even with only a norns. Let me know if you find this useful.

<img width="552" height="289" alt="twins_ss png" src="https://github.com/user-attachments/assets/e2308c34-df38-47f8-b595-72deed76e240" />

**Some of the new features:**
* Morphing
* Reverb, delay, chorus, tape effects, glitch, shimmer, EQ, filters, bit reduction, etc.
* Extra granular parameters, increased parameter ranges
* Pitch quantization
* Freely assignable LFOs with randomization
* On screen navigation with parameter locking
* Symmetry mode and mirroring
* Live input processing
* Flexible volume control
* Seamless loop saving

And a lot more.

### Requirements
norns / norns shield  
_some features might require a pi4 based unit. If you hear clicks and crackles try turning off a few effects. Most expensive ones are reverb and analog tape sim_

### Documentation
**E1**: Master Volume  
**K1**+**E2**/**E3**: Volume  
Hold **K1**: Morphing  
Hold **K2**: Linked Mode  
Hold **K3**: Symmetry  
**K1**+**E1**: Crossfade/Morph  
**K2**/**K3**: Navigate  
**E2**/**E3**: Adjust Parameters  
**K2**+**K3**: Lock Parameters  
**K2**+**K3**: HP/LP Filter  
**K1**+**K2**/**K3**: Randomize  
Hold **K2**+**K3**: Assign LFOs  
**K2**+**E2**/**E3**: LFO depth  
**K3**+**E2**/**E3**: LFO offset  

### Discussion
**[FORUM](https://llllllll.co/t/twins/71052)**
### Download
**v0.51**
install from Maiden Project Manager, or from Maiden REPL:
```
;install https://github.com/danielrigler/twins
```
do not forget to restart.
