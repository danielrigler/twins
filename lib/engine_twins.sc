Engine_twins : CroneEngine {
    classvar nvoices = 2;

    var delayEffect;
    var saturationEffect;
    var jpverbEffect;
    var shimmerEffect;
    var tapeEffect;
    var chewEffect;
    var widthEffect;
    var widthEffect2;
    var monobassEffect;
    var sineEffect;
    var wobbleEffect;
    var lossdegradeEffect;
    var outputSynth;
    var <buffersL;
    var <buffersR;
    var wobbleBuffer;
    var <voices;
    var mixBus;
    var bufSine;
    var pg;
    var <liveInputBuffersL;
    var <liveInputBuffersR;
    var <liveInputRecorders;
    var currentSpeed, currentJitter, currentSize, currentDensity, currentDensityModAmt, currentPitch, currentPan, currentSpread;
    var currentVolume, currentGranularGain, currentCutoff, currentHpf, currentlpfgain;
    var currentSubharmonics1, currentSubharmonics2, currentSubharmonics3;
    var currentOvertones1, currentOvertones2;
    var currentPitchMode, currentTrigMode, currentDirectionMod;
    var currentSizeVariation, currentPitchRandomPlus, currentPitchRandomMinus;
    var currentSmoothbass, currentLowGain, currentHighGain;
    var currentProbability;
    var liveBufferMix = 1.0;

    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

readBuf { arg i, path;
    if(buffersL[i].notNil && buffersR[i].notNil, {
        if (File.exists(path), {
            var numChannels = SoundFile.use(path.asString(), { |f| f.numChannels });
            Buffer.readChannel(context.server, path, 0, -1, [0], { |b|
                voices[i].set(\buf_l, b);
                buffersL[i].free;
                buffersL[i] = b;
                voices[i].set(\pos, 0, \t_reset_pos, 1);
                if (numChannels > 1, {
                    Buffer.readChannel(context.server, path, 0, -1, [1], { |b|
                        voices[i].set(\buf_r, b);
                        buffersR[i].free;
                        buffersR[i] = b;
                    });
                }, {
                    voices[i].set(\buf_r, b);
                    buffersR[i].free;
                    buffersR[i] = b;
                });
            });
        });
    });
}

unloadAll {
    nvoices.do({ arg i, live_buffer_length;
        var newBufL = Buffer.alloc(context.server, context.server.sampleRate * live_buffer_length);
        var newBufR = Buffer.alloc(context.server, context.server.sampleRate * live_buffer_length);
        if(buffersL[i].notNil, { buffersL[i].free; });
        if(buffersR[i].notNil, { buffersR[i].free; });
        buffersL.put(i, newBufL);
        buffersR.put(i, newBufR);
        if(voices[i].notNil, {
            voices[i].set(
                \buf_l, newBufL,
                \buf_r, newBufR,
                \t_reset_pos, 1
            );
        });
        liveInputBuffersL[i].zero;
        liveInputBuffersR[i].zero;
        if(liveInputRecorders[i].notNil, {
            liveInputRecorders[i].free;
            liveInputRecorders[i] = nil;
        });
    });
    wobbleBuffer.zero;
}

saveLiveBufferToTape { arg voice, filename;
    var path = "/home/we/dust/audio/tape/" ++ filename;
    var bufL = liveInputBuffersL[voice];
    var bufR = liveInputBuffersR[voice];
    var interleaved = Buffer.alloc(context.server, bufL.numFrames, 2);
    bufL.loadToFloatArray(action: { |leftData|
        bufR.loadToFloatArray(action: { |rightData|
            var interleavedData = Array.new(leftData.size * 2);
            leftData.size.do { |i|
                interleavedData.add(leftData[i]);
                interleavedData.add(rightData[i]); };
            interleaved.loadCollection(interleavedData, action: {
                interleaved.write(path, "WAV", "float");
                this.readBuf(voice, path);
                interleaved.free;
            });
        });
    });
}

alloc {
        buffersL = Array.fill(nvoices, { arg i;
            Buffer.alloc(context.server, context.server.sampleRate * 1);
        });

        buffersR = Array.fill(nvoices, { arg i;
            Buffer.alloc(context.server, context.server.sampleRate * 1);
        });
        
        liveInputBuffersL = Array.fill(nvoices, {
            Buffer.alloc(context.server, context.server.sampleRate * 8);
        });
        
        liveInputBuffersR = Array.fill(nvoices, {
            Buffer.alloc(context.server, context.server.sampleRate * 8);
        });

        bufSine = Buffer.alloc(context.server, 1024 * 16, 1);
        bufSine.sine2([2], [0.5], false);
        wobbleBuffer = Buffer.alloc(context.server, 48000 * 5, 2);
        mixBus = Bus.audio(context.server, 2);
        
        context.server.sync;
     
        currentSpeed = [0.1, 0.1];         
        currentJitter = [0.25, 0.25];      
        currentSize = [0.1, 0.1];          
        currentDensity = [10, 10];         
        currentPitch = [1, 1];             
        currentPan = [0, 0];               
        currentSpread = [0, 0];            
        currentVolume = [1, 1];            
        currentGranularGain = [1, 1];     
        currentCutoff = [20000, 20000];
        currentlpfgain = [0.1, 0.1];
        currentHpf = [20, 20];             
        currentSubharmonics1 = [0, 0];    
        currentSubharmonics2 = [0, 0];      
        currentSubharmonics3 = [0, 0];      
        currentOvertones1 = [0, 0];         
        currentOvertones2 = [0, 0];         
        currentPitchMode = [0, 0];          
        currentTrigMode = [0, 0];           
        currentDirectionMod = [0, 0];
        currentSizeVariation = [0, 0];
        currentPitchRandomPlus = [0, 0];
        currentPitchRandomMinus = [0, 0];
        currentSmoothbass = [1, 1];
        currentDensityModAmt = [0, 0];
        currentLowGain = [0, 0];
        currentHighGain = [0, 0];
        currentProbability = [100, 100];
      
        SynthDef(\synth, {
            arg out, buf_l, buf_r,
            pos, speed, jitter, size, density, density_mod_amt, pitch_offset, pan, spread, gain,
            t_reset_pos,
            granular_gain,
            pitch_mode,
            trig_mode,
            subharmonics_1, 
            subharmonics_2,
            subharmonics_3,
            overtones_1, 
            overtones_2, 
            cutoff, hpf, lpfgain=0.1,
            direction_mod,
            size_variation,
            low_gain, high_gain,
            smoothbass,
            pitch_random_plus, pitch_random_minus,
            probability;
 
            var grain_trig, jitter_sig1, jitter_sig2, jitter_sig3, jitter_sig4, jitter_sig5, jitter_sig6, buf_dur, pan_sig, buf_pos, pos_sig, sig_l, sig_r, sig_mix, density_mod, dry_sig, granular_sig, base_pitch, grain_pitch, shaped, grain_size;
            var invDenom = 1.5 / (1 + subharmonics_1 + subharmonics_2 + subharmonics_3 + overtones_1 + overtones_2);
            var subharmonic_1_vol = subharmonics_1 * invDenom;
            var subharmonic_2_vol = subharmonics_2 * invDenom;
            var subharmonic_3_vol = subharmonics_3 * invDenom;
            var overtone_1_vol = overtones_1 * invDenom;
            var overtone_2_vol = overtones_2 * invDenom;
            var lagPitchOffset = Lag.kr(pitch_offset);
            var grain_direction = Select.kr(pitch_mode, [1, Select.kr(speed.abs > 0.001, [1, speed.sign])]) * ((LFNoise1.kr(density).range(0,1) < direction_mod).linlin(0,1,1,-1));
            var low, high;
            var positive_intervals = [12, 24], negative_intervals = [-12, -24];
            var interval_plus, interval_minus, final_interval;
            var base_trig;
            
            speed = Lag.kr(speed);
            density_mod = density * (2**(LFNoise1.kr(density) * density_mod_amt));
            base_trig = Select.kr(trig_mode, [Impulse.kr(density_mod), Dust.kr(density_mod)]);
            grain_trig = base_trig * (TRand.kr(trig: base_trig, lo: 0, hi: 1) < probability);
            buf_dur = BufDur.kr(buf_l);
            
            #jitter_sig1, jitter_sig2, jitter_sig3 = {TRand.kr(trig: grain_trig, lo: buf_dur.reciprocal.neg * jitter, hi: buf_dur.reciprocal * jitter) }.dup(3);            
            buf_pos = Phasor.kr(trig: t_reset_pos, rate: buf_dur.reciprocal / ControlRate.ir * speed, resetPos: pos);
            pos_sig = Wrap.kr(buf_pos);
            dry_sig = [PlayBuf.ar(1, buf_l, speed, startPos: pos * BufFrames.kr(buf_l), trigger: t_reset_pos, loop: 1), PlayBuf.ar(1, buf_r, speed, startPos: pos * BufFrames.kr(buf_r), trigger: t_reset_pos, loop: 1)];
            dry_sig = Balance2.ar(dry_sig[0], dry_sig[1], pan);
            
            base_pitch = Select.kr(pitch_mode, [speed * lagPitchOffset, lagPitchOffset]);
            interval_plus = (LFNoise1.kr(density).range(0, 1) < pitch_random_plus) * TChoose.kr(grain_trig, positive_intervals);
            interval_minus = (LFNoise1.kr(density).range(0, 1) < pitch_random_minus) * TChoose.kr(grain_trig, negative_intervals);
            final_interval = interval_plus + interval_minus;

            grain_pitch = base_pitch * (2 ** (final_interval/12));
            grain_size = size * (1 + TRand.kr(trig: grain_trig, lo: size_variation.neg, hi: size_variation)); 

            ~grainBufFunc = { |buf, pitch, size, vol, dir, pos, jitter| GrainBuf.ar(1, grain_trig, size, buf, pitch * dir, pos + jitter, 2, mul: vol)};
            ~processGrains = { |buf_l, buf_r, pitch, size, vol, dir, pos, jitter| [~grainBufFunc.(buf_l, pitch, size, vol, dir, pos, jitter), ~grainBufFunc.(buf_r, pitch, size, vol, dir, pos, jitter)]};
            #sig_l, sig_r = ~processGrains.(buf_l, buf_r, grain_pitch, grain_size, invDenom, grain_direction, pos_sig, jitter_sig1);
            [1/2, 1/4, 1/8].do { |div, i|
                var vol = [subharmonic_1_vol, subharmonic_2_vol, subharmonic_3_vol][i];
                #sig_l, sig_r = [
                    sig_l + ~grainBufFunc.(buf_l, grain_pitch * div, grain_size * smoothbass, vol, grain_direction, pos_sig, jitter_sig2),
                    sig_r + ~grainBufFunc.(buf_r, grain_pitch * div, grain_size * smoothbass, vol, grain_direction, pos_sig, jitter_sig2)];};
            [2, 4].do { |mult, i|
                var vol = [overtone_1_vol, overtone_2_vol][i];
                #sig_l, sig_r = [
                    sig_l + ~grainBufFunc.(buf_l, grain_pitch * mult, grain_size, vol, grain_direction, pos_sig, jitter_sig3),
                    sig_r + ~grainBufFunc.(buf_r, grain_pitch * mult, grain_size, vol, grain_direction, pos_sig, jitter_sig3)];};

            pan_sig = Lag.kr(TRand.kr(trig: grain_trig, lo: spread.neg, hi: spread));
            granular_sig = Balance2.ar(sig_l, sig_r, pan + pan_sig);
            sig_mix = (dry_sig * (1 - granular_gain)) + (granular_sig * granular_gain);
            
            low = BLowShelf.ar(sig_mix, 130, 6, low_gain);
            high = BHiShelf.ar(sig_mix, 3900, 6, high_gain);
            sig_mix = low + high;
            
            sig_mix = HPF.ar(sig_mix, Lag.kr(hpf));
            sig_mix = MoogFF.ar(sig_mix, Lag.kr(cutoff), lpfgain);

            sig_mix = Compander.ar(sig_mix, sig_mix, 0.4, 1, 0.5, 0.03, 0.3) * 0.7;

            Out.ar(out, sig_mix * gain);
        }).add;
        
        SynthDef(\liveDirect, {
            arg out, pan, gain, cutoff, hpf, low_gain, high_gain, isMono, lpfgain=0.1;
            var low, high;
            var sig = SoundIn.ar([0, 1]);
            sig = Select.ar(isMono, [sig, [sig[0], sig[0]] ]);
            low = BLowShelf.ar(sig, 130, 6, low_gain);
            high = BHiShelf.ar(sig, 3900, 6, high_gain);
            sig = low + high;
            sig = HPF.ar(sig, Lag.kr(hpf));
            sig = MoogFF.ar(sig, Lag.kr(cutoff), lpfgain);
            sig = Balance2.ar(sig[0], sig[1], Lag.kr(pan));
            sig = Compander.ar(sig, sig, 0.4, 1, 0.5, 0.03, 0.3) * 0.7;
            Out.ar(out, sig * gain);
        }).add;
        
        SynthDef(\liveInputRecorder, {
            arg bufL, bufR, isMono=0, mix;
            var in = SoundIn.ar([0, 1]);
            var phasor = Phasor.ar(0, 1, 0, BufFrames.kr(bufL));
            var oldL = BufRd.ar(1, bufL, phasor);
            var oldR = BufRd.ar(1, bufR, phasor);
            var mixedL, mixedR;
            in = Select.ar(isMono, [in, [Mix.ar(in), Mix.ar(in)]]);
            mixedL = XFade2.ar(oldL, in[0], mix * 2 - 1);
            mixedR = XFade2.ar(oldR, in[1], mix * 2 - 1);
            BufWr.ar(mixedL, bufL, phasor);
            BufWr.ar(mixedR, bufR, phasor);
        }).add;

        SynthDef(\monobass, {
            arg bus, mix=0.0;
            var sig = In.ar(bus, 2);
            sig = BHiPass.ar(sig,200)+Pan2.ar(BLowPass.ar(sig[0]+sig[1],200));
            ReplaceOut.ar(bus, sig);
        }).add;  

        SynthDef(\shimmer, {
            arg bus, mix=0.0, lowpass=13000, hipass=1400, pitchv=0.02, fb=0.0, fbDelay=0.15, o2=1;
            var orig = In.ar(bus, 2);
            var hpf = HPF.ar(orig, hipass);
            var pit = PitchShift.ar(hpf, 0.5, 2, pitchv, 1, mul:4);
            var pit2 = PitchShift.ar(hpf, 0.4, 4, pitchv, 1, mul:2.5*o2);
            var fbSig = LocalIn.ar(2);
            var fbProcessed = fbSig * fb;
            pit = LPF.ar((pit + pit2 + fbProcessed),lowpass);
            LocalOut.ar(DelayC.ar(pit, 0.5, fbDelay));
            ReplaceOut.ar(bus, LinXFade2.ar(orig, orig + pit, mix * 2 - 1));
        }).add;
        
        SynthDef(\sine, {
            arg bus, sine_drive=0.0;
            var orig = In.ar(bus, 2);
            var shaped = Shaper.ar(bufSine, orig * sine_drive);
            ReplaceOut.ar(bus, shaped);
        }).add;
        
        SynthDef(\tape, {
            arg bus, mix=0.0;
            var orig = In.ar(bus, 2);
            var wet = AnalogTape.ar(orig, 0.86, 0.86, 0.86, 2, 0);
            ReplaceOut.ar(bus, LinXFade2.ar(orig, wet, mix * 2 - 1));
        }).add;
        
        SynthDef(\wobble, {
            arg bus, mix=0.0, wobble_amp=0.05, wobble_rpm=33, flutter_amp=0.03, flutter_freq=6, flutter_var=2;
            var pr, pw, rate, wet, flutter, wow, dry;
            dry = In.ar(bus, 2);
            wow = wobble_amp * SinOsc.kr(wobble_rpm/60, mul:0.2);
            flutter = flutter_amp * SinOsc.kr(flutter_freq + LFNoise2.kr(flutter_var), mul:0.1);
            rate = 1 + (wow + flutter);
            pw = Phasor.ar(0, BufRateScale.kr(wobbleBuffer), 0, BufFrames.kr(wobbleBuffer));
            BufWr.ar(dry, wobbleBuffer, pw);
            pr = DelayL.ar(Phasor.ar(0, BufRateScale.kr(wobbleBuffer)*rate, 0, BufFrames.kr(wobbleBuffer)), 0.2, 0.2);
            wet = BufRd.ar(2, wobbleBuffer, pr, interpolation:4);
            ReplaceOut.ar(bus, LinXFade2.ar(dry, wet, mix * 2 - 1));
        }).add;
        
        SynthDef(\chew, {
            arg bus, chew_depth=0.0, chew_freq=0.5, chew_variance=0.5;
            var orig = In.ar(bus, 2);
            var wet = AnalogChew.ar(orig, chew_depth, chew_freq, chew_variance);
            ReplaceOut.ar(bus, wet);
        }).add;

        SynthDef(\lossdegrade, {
            arg bus, mix=0.0;
            var sig = In.ar(bus, 2);
            var loss = AnalogLoss.ar(sig,0.4,0.38,0.5,1);
            var degrade = AnalogDegrade.ar(loss,0.3,0.3,0.5,0.5);
            ReplaceOut.ar(bus, LinXFade2.ar(sig, degrade, mix * 2 - 1));
        }).add;
        
        SynthDef(\saturation, {
            arg bus, drive=0.0;
            var dry, wet, shaped;
            dry = In.ar(bus, 2);
            wet = dry * (drive * 10 + 1);
            shaped = wet.tanh * 0.3;
            ReplaceOut.ar(bus, LinXFade2.ar(dry, shaped, drive * 2 - 1));
        }).add;

        SynthDef(\delay, {
            arg bus, mix=0.0, time=0.5, feedback=0.5, delayLPF=6000, stereo=1, mod_rate, mod_depth;
            var sig = In.ar(bus, 2);
            var fb = LocalIn.ar(2);
            var fbInput = [sig[0] + (fb[1] * feedback), sig[1] + (fb[0] * feedback)].softclip;
            var modulation = LFPar.kr(mod_rate, mul: mod_depth);
            var delayedL = DelayC.ar(fbInput[0], 4.0, time + modulation);
            var delayedR = DelayC.ar(fbInput[1], 4.0, time + modulation);
            var processedL = LPF.ar(delayedL, delayLPF);
            var processedR = LPF.ar(delayedR, delayLPF);  
            var panPos = LFPar.kr(1/(time*2), iphase: 0).range(-1, 1) * stereo;
            var outputL = processedL * panPos.max(0) + (processedL * (1-stereo));
            var outputR = processedR * panPos.min(0).neg + (processedR * (1-stereo));
            LocalOut.ar([outputL, outputR]);
            ReplaceOut.ar(bus, LinXFade2.ar(sig, sig + [outputL, outputR], mix * 2 - 1));
        }).add;

        SynthDef(\jpverb, {
            arg bus, mix=0.0, t60, damp, rsize, earlyDiff, modDepth, modFreq, low, mid, high, lowcut, highcut;
            var dry = In.ar(bus, 2);
            var wet = JPverb.ar(dry, t60, damp, rsize, earlyDiff, modDepth, modFreq, low, mid, high, lowcut, highcut);
            ReplaceOut.ar(bus, LinXFade2.ar(dry, wet, mix * 2 - 1));
        }).add;
        
        SynthDef(\width, {
            arg bus, width=1.0;
            var sig = In.ar(bus, 2);
            var mid = (sig[0] + sig[1]) * 0.5;
            var side = ((sig[0] - sig[1]) * 0.5 * width).tanh;
            sig = [mid + side, mid - side];
            ReplaceOut.ar(bus, sig);
        }).add;         
        
        SynthDef(\output, {
            arg in, out;
            var sig = In.ar(in, 2);
            Out.ar(out, sig);
        }).add;

        context.server.sync;
        
        pg = ParGroup.head(context.xg);
        
        voices = Array.fill(nvoices, { arg i;
            Synth.new(\synth, [
                \out, mixBus.index, 
                \buf_l, buffersL[i],
                \buf_r, buffersR[i],
            ], target: pg);
        });
        
        liveInputRecorders = Array.fill(nvoices, { nil });
        
        context.server.sync;

        shimmerEffect = Synth.new(\shimmer, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');    
        sineEffect = Synth.new(\sine, [\bus, mixBus.index, \sine_drive, 0.0], context.xg, 'addToTail');  
        tapeEffect = Synth.new(\tape, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');  
        wobbleEffect = Synth.new(\wobble, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');
        chewEffect = Synth.new(\chew, [\bus, mixBus.index, \chew_depth, 0.0], context.xg, 'addToTail');
        lossdegradeEffect = Synth.new(\lossdegrade, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');
        delayEffect = Synth.new(\delay, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');
        widthEffect = Synth.new(\width, [\bus, mixBus.index, \width, 1.0], context.xg, 'addToTail');
        saturationEffect = Synth.new(\saturation, [\bus, mixBus.index, \drive, 0.0], context.xg, 'addToTail');
        jpverbEffect = Synth.new(\jpverb, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');
        widthEffect2 = Synth.new(\width, [\bus, mixBus.index, \width, 1.0], context.xg, 'addToTail');
        monobassEffect = Synth.new(\monobass, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');
        outputSynth = Synth.new(\output, [\in, mixBus.index,\out, context.out_b.index], context.xg, 'addToTail');   

        this.addCommand("reverb_mix", "f", { arg msg; var mix = msg[1]; jpverbEffect.set(\mix, mix); jpverbEffect.run(mix > 0); });
        this.addCommand("t60", "f", { arg msg; jpverbEffect.set(\t60, msg[1]); });
        this.addCommand("damp", "f", { arg msg; jpverbEffect.set(\damp, msg[1]); });
        this.addCommand("rsize", "f", { arg msg; jpverbEffect.set(\rsize, msg[1]); });
        this.addCommand("earlyDiff", "f", { arg msg; jpverbEffect.set(\earlyDiff, msg[1]); });
        this.addCommand("modDepth", "f", { arg msg; jpverbEffect.set(\modDepth, msg[1]); });
        this.addCommand("modFreq", "f", { arg msg; jpverbEffect.set(\modFreq, msg[1]); });
        this.addCommand("low", "f", { arg msg; jpverbEffect.set(\low, msg[1]); });
        this.addCommand("mid", "f", { arg msg; jpverbEffect.set(\mid, msg[1]); });
        this.addCommand("high", "f", { arg msg; jpverbEffect.set(\high, msg[1]); });
        this.addCommand("lowcut", "f", { arg msg; jpverbEffect.set(\lowcut, msg[1]); });
        this.addCommand("highcut", "f", { arg msg; jpverbEffect.set(\highcut, msg[1]); });
        
        this.addCommand("cutoff", "if", { arg msg; var voice = msg[1] - 1; currentCutoff[voice] = msg[2]; voices[voice].set(\cutoff, msg[2]); });
        this.addCommand("lpfgain", "if", { arg msg; var voice = msg[1] - 1; currentlpfgain[voice] = msg[2]; voices[voice].set(\lpfgain, msg[2]); });
        this.addCommand("hpf", "if", { arg msg; var voice = msg[1] - 1; currentHpf[voice] = msg[2]; voices[voice].set(\hpf, msg[2]); });
        
        this.addCommand("granular_gain", "if", { arg msg; var voice = msg[1] - 1; currentGranularGain[voice] = msg[2]; voices[voice].set(\granular_gain, msg[2]); });
        this.addCommand("density_mod_amt", "if", { arg msg; var voice = msg[1] - 1; currentDensityModAmt[voice] = msg[2]; voices[voice].set(\density_mod_amt, msg[2]); });
        this.addCommand("trig_mode", "ii", { arg msg; var voice = msg[1] - 1; currentTrigMode[voice] = msg[2]; voices[voice].set(\trig_mode, msg[2]); });
        this.addCommand("subharmonics_1", "if", { arg msg; var voice = msg[1] - 1; currentSubharmonics1[voice] = msg[2]; voices[voice].set(\subharmonics_1, msg[2]); });
        this.addCommand("subharmonics_2", "if", { arg msg; var voice = msg[1] - 1; currentSubharmonics2[voice] = msg[2]; voices[voice].set(\subharmonics_2, msg[2]); });
        this.addCommand("subharmonics_3", "if", { arg msg; var voice = msg[1] - 1; currentSubharmonics3[voice] = msg[2]; voices[voice].set(\subharmonics_3, msg[2]); });
        this.addCommand("overtones_1", "if", { arg msg; var voice = msg[1] - 1; currentOvertones1[voice] = msg[2]; voices[voice].set(\overtones_1, msg[2]); });
        this.addCommand("overtones_2", "if", { arg msg; var voice = msg[1] - 1; currentOvertones2[voice] = msg[2]; voices[voice].set(\overtones_2, msg[2]); });
        this.addCommand("pitch_mode", "ii", { arg msg; var voice = msg[1] - 1; currentPitchMode[voice] = msg[2]; voices[voice].set(\pitch_mode, msg[2]); });
        this.addCommand("pitch_offset", "if", { arg msg; var voice = msg[1] - 1; currentPitch[voice] = msg[2]; voices[voice].set(\pitch_offset, msg[2]); });
        this.addCommand("direction_mod", "if", { arg msg; var voice = msg[1] - 1; currentDirectionMod[voice] = msg[2]; voices[voice].set(\direction_mod, msg[2]); });
        this.addCommand("size_variation", "if", { arg msg; var voice = msg[1] - 1; currentSizeVariation[voice] = msg[2]; voices[voice].set(\size_variation, msg[2]); });
        this.addCommand("pitch_random_plus", "if", { arg msg; var voice = msg[1] - 1; currentPitchRandomPlus[voice] = msg[2]; voices[voice].set(\pitch_random_plus, msg[2]); });
        this.addCommand("pitch_random_minus", "if", { arg msg; var voice = msg[1] - 1; currentPitchRandomMinus[voice] = msg[2]; voices[voice].set(\pitch_random_minus, msg[2]); });
        this.addCommand("smoothbass", "if", { arg msg; var voice = msg[1] - 1; currentSmoothbass[voice] = msg[2]; voices[voice].set(\smoothbass, msg[2]); });
        this.addCommand("probability", "if", { arg msg; var voice = msg[1] - 1; currentProbability[voice] = msg[2]; voices[voice].set(\probability, msg[2]); });
        
        this.addCommand("shimmer_mix", "f", { arg msg; var mix = msg[1]; shimmerEffect.set(\mix, mix); shimmerEffect.run(mix > 0); });
        this.addCommand("lowpass", "f", { arg msg; shimmerEffect.set(\lowpass, msg[1]); });
        this.addCommand("hipass", "f", { arg msg; shimmerEffect.set(\hipass, msg[1]); });
        this.addCommand("pitchv", "f", { arg msg; shimmerEffect.set(\pitchv, msg[1]); });
        this.addCommand("fb", "f", { arg msg; shimmerEffect.set(\fb, msg[1]); });
        this.addCommand("fbDelay", "f", { arg msg; shimmerEffect.set(\fbDelay, msg[1]); });
        this.addCommand("o2", "i", { arg msg; shimmerEffect.set(\o2, msg[1]); });
        
        this.addCommand("read", "is", { arg msg; this.readBuf(msg[1] - 1, msg[2]); });
        this.addCommand("seek", "if", { arg msg; var voice = msg[1] - 1; var pos = msg[2]; voices[voice].set(\pos, pos); voices[voice].set(\t_reset_pos, 1); });
        this.addCommand("speed", "if", { arg msg; var voice = msg[1] - 1; currentSpeed[voice] = msg[2]; voices[voice].set(\speed, msg[2]); });
        this.addCommand("jitter", "if", { arg msg; var voice = msg[1] - 1; currentJitter[voice] = msg[2]; voices[voice].set(\jitter, msg[2]); });
        this.addCommand("size", "if", { arg msg; var voice = msg[1] - 1; currentSize[voice] = msg[2]; voices[voice].set(\size, msg[2]); });
        this.addCommand("density", "if", { arg msg; var voice = msg[1] - 1; currentDensity[voice] = msg[2]; voices[voice].set(\density, msg[2]); });
        this.addCommand("pan", "if", { arg msg; var voice = msg[1] - 1; currentPan[voice] = msg[2]; voices[voice].set(\pan, msg[2]); });
        this.addCommand("spread", "if", { arg msg; var voice = msg[1] - 1; currentSpread[voice] = msg[2]; voices[voice].set(\spread, msg[2]); });
        this.addCommand("volume", "if", { arg msg; var voice = msg[1] - 1; currentVolume[voice] = msg[2]; voices[voice].set(\gain, msg[2]); });

        this.addCommand("tape_mix", "f", { arg msg; var mix = msg[1]; tapeEffect.set(\mix, mix); tapeEffect.run(mix > 0); });
        this.addCommand("sine_drive", "f", { arg msg; var sine_drive = msg[1]; sineEffect.set(\sine_drive, sine_drive); sineEffect.run(sine_drive > 0); });
        this.addCommand("drive", "f", { arg msg; var drive = msg[1]; saturationEffect.set(\drive, drive); saturationEffect.run(drive > 0); });
        this.addCommand("wobble_mix", "f", { arg msg; var mix = msg[1]; wobbleEffect.set(\mix, mix); wobbleEffect.run(mix > 0); });
        this.addCommand("wobble_amp", "f", { arg msg; wobbleEffect.set(\wobble_amp, msg[1]); });
        this.addCommand("wobble_rpm", "f", { arg msg; wobbleEffect.set(\wobble_rpm, msg[1]); });
        this.addCommand("flutter_amp", "f", { arg msg; wobbleEffect.set(\flutter_amp, msg[1]); });
        this.addCommand("flutter_freq", "f", { arg msg; wobbleEffect.set(\flutter_freq, msg[1]); });
        this.addCommand("flutter_var", "f", { arg msg; wobbleEffect.set(\flutter_var, msg[1]); });
        this.addCommand("chew_depth", "f", { arg msg; var chew_depth = msg[1]; chewEffect.set(\chew_depth, chew_depth); chewEffect.run(chew_depth > 0); });
        this.addCommand("chew_freq", "f", { arg msg; chewEffect.set(\chew_freq, msg[1]); });
        this.addCommand("chew_variance", "f", { arg msg; chewEffect.set(\chew_variance, msg[1]); });
        this.addCommand("lossdegrade_mix", "f", { arg msg; var mix = msg[1]; lossdegradeEffect.set(\mix, mix); lossdegradeEffect.run(mix > 0); });
        
        this.addCommand("eq_low_gain", "if", { arg msg; var voice = msg[1] - 1; currentLowGain[voice] = msg[2]; voices[voice].set(\low_gain, msg[2]); });
        this.addCommand("eq_high_gain", "if", { arg msg; var voice = msg[1] - 1; currentHighGain[voice] = msg[2]; voices[voice].set(\high_gain, msg[2]); });

        this.addCommand("width", "f", { arg msg; var width = msg[1]; widthEffect.set(\width, width); widthEffect.run(width != 1); widthEffect2.set(\width, width); widthEffect2.run(width != 1); });
        this.addCommand("monobass_mix", "f", { arg msg; var mix = msg[1]; monobassEffect.set(\mix, mix); monobassEffect.run(mix > 0); });
        
        this.addCommand("delay_mix", "f", { arg msg; var mix = msg[1]; delayEffect.set(\mix, mix); delayEffect.run(mix > 0); });
        this.addCommand("delay_time", "f", { arg msg; var delayTime = msg[1]; delayEffect.set(\time, delayTime); });
        this.addCommand("delay_feedback", "f", { arg msg; var delayFeedback = msg[1]; delayEffect.set(\feedback, delayFeedback); });
        this.addCommand("delayLPF", "f", { arg msg; var delayLPF = msg[1]; delayEffect.set(\delayLPF, delayLPF); });
        this.addCommand("stereo", "f", { arg msg; var stereo = msg[1]; delayEffect.set(\stereo, stereo); });
        this.addCommand("delay_mod_rate", "f", { arg msg; delayEffect.set(\mod_rate, msg[1]); });
        this.addCommand("delay_mod_depth", "f", { arg msg; delayEffect.set(\mod_depth, msg[1]); });

        this.addCommand("set_live_input", "ii", { arg msg;
            var voice = msg[1] - 1;
            var enable = msg[2];
            if (enable == 1, {
                if (liveInputRecorders[voice].notNil, { 
                    liveInputRecorders[voice].free; 
                });
                liveInputRecorders[voice] = Synth.new(\liveInputRecorder, [
                    \bufL, liveInputBuffersL[voice],
                    \bufR, liveInputBuffersR[voice],
                    \mix, liveBufferMix
                ], context.xg, 'addToHead');
                voices[voice].set(
                    \buf_l, liveInputBuffersL[voice],
                    \buf_r, liveInputBuffersR[voice],
                    \t_reset_pos, 1);
            }, {
                if (liveInputRecorders[voice].notNil, { 
                    liveInputRecorders[voice].free; 
                });
                liveInputRecorders[voice] = nil;
            });
        });
        
        this.addCommand("live_buffer_mix", "f", { arg msg; 
            liveBufferMix = msg[1]; 
            liveInputRecorders.do({ arg recorder;
                if (recorder.notNil, {
                    recorder.set(\mix, liveBufferMix);
                });
            });
        });
        
        this.addCommand("live_direct", "ii", { arg msg;
            var voice = msg[1] - 1;
            var enable = msg[2];
            var currentParams;
            if (enable == 1, {
                if (voices[voice].notNil, { voices[voice].free; });
                if (liveInputRecorders[voice].notNil, { liveInputRecorders[voice].free; });
                voices[voice] = Synth.new(\liveDirect, [
                    \out, mixBus.index,
                    \pan, currentPan[voice] ? 0,
                    \spread, currentSpread[voice] ? 0,
                    \gain, currentVolume[voice] ? 1,
                    \cutoff, currentCutoff[voice] ? 20000,
                    \lpfgain, currentlpfgain[voice] ? 0.1,
                    \hpf, currentHpf[voice] ? 20,
                    \low_gain, currentLowGain[voice] ? 0,
                    \high_gain, currentHighGain[voice] ? 0
                ], target: pg);
            }, {
                if (voices[voice].notNil, { voices[voice].free; });
                currentParams = Dictionary.newFrom([
                    \speed, currentSpeed[voice] ? 0.1,
                    \jitter, currentJitter[voice] ? 0.25,
                    \size, currentSize[voice] ? 0.1,
                    \density, currentDensity[voice] ? 10,
                    \pitch_offset, currentPitch[voice] ? 1,
                    \pan, currentPan[voice] ? 0,
                    \spread, currentSpread[voice] ? 0,
                    \gain, currentVolume[voice] ? 1,
                    \granular_gain, currentGranularGain[voice] ? 1,
                    \cutoff, currentCutoff[voice] ? 20000,
                    \lpfgain, currentlpfgain[voice] ? 0.1,
                    \hpf, currentHpf[voice] ? 20,
                    \subharmonics_1, currentSubharmonics1[voice] ? 0,
                    \subharmonics_2, currentSubharmonics2[voice] ? 0,
                    \subharmonics_3, currentSubharmonics3[voice] ? 0,
                    \overtones_1, currentOvertones1[voice] ? 0,
                    \overtones_2, currentOvertones2[voice] ? 0,
                    \pitch_mode, currentPitchMode[voice] ? 0,
                    \trig_mode, currentTrigMode[voice] ? 0,
                    \direction_mod, currentDirectionMod[voice] ? 0,
                    \size_variation, currentSizeVariation[voice] ? 0,
                    \pitch_random_plus, currentPitchRandomPlus[voice] ? 0,
                    \pitch_random_minus, currentPitchRandomMinus[voice] ? 0,
                    \smoothbass, currentSmoothbass[voice] ? 1,
                    \low_gain, currentLowGain[voice] ? 0,
                    \high_gain, currentHighGain[voice] ? 0,
                    \probability, currentProbability[voice] ? 100
                ]);
                voices[voice] = Synth.new(\synth, [
                    \out, mixBus.index, 
                    \buf_l, buffersL[voice],
                    \buf_r, buffersR[voice]
                ] ++ currentParams.getPairs, target: pg);
                voices[voice].set(\t_reset_pos, 1);
            });
        });
        
        this.addCommand("isMono", "ii", { arg msg; var voice = msg[1] - 1; voices[voice].set(\isMono, msg[2]); });
        this.addCommand("live_mono", "ii", { arg msg; var voice = msg[1] - 1; var mono = msg[2]; if(liveInputRecorders[voice].notNil, {liveInputRecorders[voice].set(\isMono, mono); }); });
        this.addCommand("unload_all", "", {this.unloadAll(); });
        this.addCommand("save_live_buffer", "is", { arg msg; var voice = msg[1] - 1; var filename = msg[2]; var bufL = liveInputBuffersL[voice]; var bufR = liveInputBuffersR[voice]; this.saveLiveBufferToTape(voice, filename); });
        this.addCommand("live_buffer_length", "f", { arg msg; var length = msg[1];
            liveInputBuffersL.do({ arg buf; buf.free; });
            liveInputBuffersR.do({ arg buf; buf.free; });
            liveInputBuffersL = Array.fill(nvoices, {Buffer.alloc(context.server, context.server.sampleRate * length);});
            liveInputBuffersR = Array.fill(nvoices, {Buffer.alloc(context.server, context.server.sampleRate * length);});
            liveInputRecorders.do({ arg recorder, i;
                if (recorder.notNil, {recorder.free;
                    liveInputRecorders[i] = Synth.new(\liveInputRecorder, [
                        \bufL, liveInputBuffersL[i],
                        \bufR, liveInputBuffersR[i],
                        \mix, liveBufferMix
                    ], context.xg, 'addToHead');
                    voices[i].set(
                        \buf_l, liveInputBuffersL[i],
                        \buf_r, liveInputBuffersR[i],
                        \t_reset_pos, 1);
        }); }); });
    }

    free {
        voices.do({ arg voice; voice.free; });
        buffersL.do({ arg b; b.free; });
        buffersR.do({ arg b; b.free; });
        liveInputBuffersL.do({ arg b; b.free; });
        liveInputBuffersR.do({ arg b; b.free; });
        liveInputRecorders.do({ arg s; if (s.notNil) { s.free; }; });
        wobbleBuffer.free;
        mixBus.free;
        bufSine.free;
        jpverbEffect.free;
        shimmerEffect.free;
        saturationEffect.free;
        tapeEffect.free;
        chewEffect.free;
        widthEffect.free;
        widthEffect2.free;
        monobassEffect.free;
        lossdegradeEffect.free;
        sineEffect.free;
        wobbleEffect.free;
        outputSynth.free;
        delayEffect.free;
    }
}