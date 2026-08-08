## Twins

A randomized dual granular sample playground for Monome Norns.

![Screenshot](https://llllllll.co/uploads/default/original/3X/d/4/d4f2077ef24aeceebba416defd2e1cce5140f37a.png)

Inspired by @cfd90’s Twine and contains influence and code from a lot of other norns users. This is basically Twine on steroids. A granular playground. It contains lot of effects and extra granular parameters. You can turn off granular processing and use this as a normal sample player with effects. Live input processing and MIDI input is also possible. No problem if you do not have external controllers: I have tweaked the GUI and controls, so it is very playable even with only a norns. Let me know if you find this useful.

![Screenshot](https://llllllll.co/uploads/default/original/3X/3/f/3f7a18cf86f733ed6d0e88ab2b002b1e2c22a1db.png)

**Some of the new features:**

* Morphing
* Delay, chorus, tape effects, shimmer, glitch, EQ, filters, bit reduction, etc.
* Extra granular parameters, increased parameter ranges
* Freely assignable LFOs with randomization
* On screen navigation with parameter locking
* Symmetry mode and mirroring
* Live input processing
* MIDI input - play with a keyboard
* Clock sync, arp mode, loop recording

### Requirements

norns / norns shield
*some features might require a pi4 based unit. If you hear clicks and crackles try turning off a few effects or limit grain size and density.
### Documentation

**E1**: Master Volume  
**K1**+**E2**/**E3**: Volume  
**K1**+**E1**: Crossfade/Morph  
**K2**/**K3**: Navigate  
**E2**/**E3**: Adjust Parameters  
**K1**+**K2**/**K3**: Randomize  
**K2**+**K3**: Lock Parameters  
Hold **K1**: Morphing  
Hold **K2**: Linked Mode  
Hold **K3**: Symmetry  
**K2**+**K3**+**E1**/**E2**/**E3**: Effect Mix  
**K2**/**K3**+**E1**/**E2**/**E3**: Adjust LFO  
Hold **K2**+**K3**: HPF/LPF  
Hold **K2**+**K3**: Add Random LFOs  
Hold **K1**+**K2**: Clock Sync  
Hold **K1**+**K3**: Arp Mode   
Hold **K1**+**K2**+**K3**: Randomize Arp  

### Download

**v0.76**
install from Maiden Project Manager, or from Maiden REPL:

```
;install https://github.com/danielrigler/twins
```

do not forget to restart.
