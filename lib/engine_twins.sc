Engine_twins : CroneEngine {

var dimensionEffect, haasEffect, bitcrushEffect, delayEffect, saturationEffect,jpverbEffect, shimmerEffect, tapeEffect, chewEffect, widthEffect, monobassEffect, sineEffect, wobbleEffect, lossdegradeEffect, rotateEffect, outputSynth;
var <buffersL, <buffersR, wobbleBuffer, mixBus, <voices, bufSine, pg, <liveInputBuffersL, <liveInputBuffersR, <liveInputRecorders, o, o_output, o_rec, o_grain;
var currentSpeed, currentJitter, currentSize, currentDensity, currentDensityModAmt, currentPitch, currentPan, currentSpread, currentVolume, currentGranularGain, currentCutoff, currentHpf, currentlpfgain, currentSubharmonics1, currentSubharmonics2, currentSubharmonics3, currentOvertones1, currentOvertones2, currentPitchMode, currentTrigMode, currentDirectionMod, currentSizeVariation, currentSmoothbass, currentLowGain, currentHighGain, currentProbability, liveBufferMix = 1.0, currentPitchWalkRate, currentPitchWalkStep, currentPitchRandomProb, currentPitchRandomScale, currentRatchetingProb;
var <outputRecordBuffer, <outputRecorder;
var outputBufferLength = 8, currentOutputWritePos;
var grainEnvs;

*new { arg context, doneCallback; ^super.new(context, doneCallback); }

readBuf { arg i, path; if(buffersL[i].notNil && buffersR[i].notNil, { if (File.exists(path), { var numChannels = SoundFile.use(path.asString(), { |f| f.numChannels }); Buffer.readChannel(context.server, path, 0, -1, [0], { |b| voices[i].set(\buf_l, b);         buffersL[i].free; buffersL[i] = b; voices[i].set(\t_reset_pos, 1); if (numChannels > 1, { Buffer.readChannel(context.server, path, 0, -1, [1], { |b| voices[i].set(\buf_r, b); buffersR[i].free; buffersR[i] = b; voices[i].set(\t_reset_pos, 1); }); }, {          voices[i].set(\buf_r, b); buffersR[i].free; buffersR[i] = b; voices[i].set(\t_reset_pos, 1); }); }); }); }); }

unloadAll { 2.do({ arg i, live_buffer_length; var newBufL = Buffer.alloc(context.server, context.server.sampleRate * live_buffer_length); var newBufR = Buffer.alloc(context.server, context.server.sampleRate * live_buffer_length); if(buffersL[i].notNil, { buffersL[i].free; }); if(buffersR[i].notNil, { buffersR[i].free; }); buffersL.put(i, newBufL); buffersR.put(i, newBufR); if(voices[i].notNil, { voices[i].set( \buf_l, newBufL, \buf_r, newBufR, \t_reset_pos, 1 ); }); liveInputBuffersL[i].zero; liveInputBuffersR[i].zero; if(liveInputRecorders[i].notNil, { liveInputRecorders[i].free; liveInputRecorders[i] = nil; }); }); wobbleBuffer.zero; }

saveLiveBufferToTape { arg voice, filename; var path = "/home/we/dust/audio/tape/" ++ filename; var bufL = liveInputBuffersL[voice]; var bufR = liveInputBuffersR[voice]; var interleaved = Buffer.alloc(context.server, bufL.numFrames, 2); bufL.loadToFloatArray(action: { |leftData| bufR.loadToFloatArray(action: { |rightData| var interleavedData = Array.new(leftData.size * 2); leftData.size.do { |i| interleavedData.add(leftData[i]); interleavedData.add(rightData[i]); }; interleaved.loadCollection(interleavedData, action: { interleaved.write(path, "WAV", "float"); this.readBuf(voice, path); interleaved.free; }); }); }); }

alloc {
        buffersL = Array.fill(2, { arg i; Buffer.alloc(context.server, context.server.sampleRate * 1); });
        buffersR = Array.fill(2, { arg i; Buffer.alloc(context.server, context.server.sampleRate * 1); });

        liveInputBuffersL = Array.fill(2, {Buffer.alloc(context.server, context.server.sampleRate * 8); });
        liveInputBuffersR = Array.fill(2, {Buffer.alloc(context.server, context.server.sampleRate * 8); });
        liveInputRecorders = Array.fill(2, { nil });

        outputRecordBuffer = Buffer.alloc(context.server, context.server.sampleRate * outputBufferLength, 2);

        bufSine = Buffer.alloc(context.server, 1024 * 16, 1);
        bufSine.sine2([2], [0.5], false);
        wobbleBuffer = Buffer.alloc(context.server, 48000 * 5, 2);
        mixBus = Bus.audio(context.server, 2);

        grainEnvs = [
            Env.sine(1, 1),
            Env.new([0, 1, 1, 0], [0.15, 0.7, 0.15], [4, 0, -4]),
            Env.triangle(1, 1), 
            Env.step([1, 0], [1, 1]),
            Env.perc(0.01, 1, 1, -4),
            Env.perc(0.99, 0.01, 1, 4),
            Env.adsr(0.25, 0.15, 0.65, 1, 1, -4, 0)
        ].collect { |env| Buffer.sendCollection(context.server, env.discretize) };
        
        currentSpeed = [0.1, 0.1]; currentJitter = [0.25, 0.25]; currentSize = [0.1, 0.1]; currentDensity = [10, 10]; currentPitch = [1, 1]; currentPan = [0, 0]; currentSpread = [0, 0]; currentVolume = [1, 1]; currentGranularGain = [1, 1]; currentCutoff = [20000, 20000]; currentlpfgain = [0.1, 0.1]; currentHpf = [20, 20]; currentSubharmonics1 = [0, 0]; currentSubharmonics2 = [0, 0]; currentSubharmonics3 = [0, 0]; currentOvertones1 = [0, 0]; currentOvertones2 = [0, 0]; currentPitchMode = [0, 0]; currentTrigMode = [0, 0]; currentDirectionMod = [0, 0]; currentSizeVariation = [0, 0]; currentSmoothbass = [1, 1]; currentDensityModAmt = [0, 0]; currentLowGain = [0, 0]; currentHighGain = [0, 0]; currentProbability = [100, 100]; liveBufferMix = 1.0; currentPitchWalkRate = [2, 2]; currentPitchWalkStep = [2, 2]; currentPitchRandomProb = [0, 0]; currentPitchRandomScale = [[0], [0]]; currentRatchetingProb = [0, 0];

        context.server.sync;

SynthDef(\synth1, {
    arg out, voice, buf_l, buf_r, pos, speed, jitter, size, density, density_mod_amt, pitch_offset, pan, spread, gain, t_reset_pos,
    granular_gain, pitch_mode, trig_mode, subharmonics_1, subharmonics_2, subharmonics_3, overtones_1, overtones_2, 
    cutoff, hpf, hpfq, lpfgain, direction_mod, size_variation, low_gain, mid_gain, high_gain, smoothbass,
    probability, pitch_walk_rate, pitch_walk_step, env_select = 0, pitch_random_prob=0, pitch_random_scale_type, pitch_random_direction=1,
    ratcheting_prob=0;

    var grainBufFunc, processGrains;
    var grain_trig, jitter_sig, buf_dur, pan_sig, buf_pos, pos_sig, sig_l, sig_r, sig_mix, density_mod, dry_sig, granular_sig, base_pitch, grain_pitch, shaped, grain_size;
    var invDenom = 1 / (1 + subharmonics_1 + subharmonics_2 + subharmonics_3 + overtones_1 + overtones_2);
    var subharmonic_1_vol = subharmonics_1 * invDenom * 2;
    var subharmonic_2_vol = subharmonics_2 * invDenom * 2;
    var subharmonic_3_vol = subharmonics_3 * invDenom * 2;
    var overtone_1_vol = overtones_1 * invDenom * 2;
    var overtone_2_vol = overtones_2 * invDenom * 2;
    var grain_direction, base_trig;
    var rand_val, rand_val2, scale_type, random_interval;
    var ratchet_active;
    
    speed = Lag.kr(speed);
    density_mod = density * (2**(LFNoise1.kr(density).range(0, 1) * density_mod_amt));
    base_trig = Select.kr(trig_mode, [Impulse.kr(density_mod), Dust.kr(density_mod)]);
    
    ratchet_active = Trig1.kr(base_trig * (TRand.kr(trig: base_trig, lo: 0, hi: 1) < ratcheting_prob), TChoose.kr(base_trig, [1, 2]) * density_mod.reciprocal * 0.5);
    grain_trig = Select.kr(trig_mode, [Impulse.kr(density_mod * (1 + ratchet_active)), Dust.kr(density_mod * (1 + ratchet_active))]) * (TRand.kr(trig: base_trig, lo: 0, hi: 1) < probability);
    
    rand_val = TRand.kr(trig: grain_trig, lo: 0, hi: 1);
    rand_val2 = TRand.kr(trig: grain_trig, lo: 0, hi: 1);
    grain_size = size * (1 + TRand.kr(trig: grain_trig, lo: size_variation.neg, hi: size_variation));
    grain_direction = Select.kr(pitch_mode, [1, Select.kr(speed.abs > 0.001, [1, speed.sign])]) * Select.kr((rand_val < direction_mod), [1, -1]);
    buf_dur = BufDur.kr(buf_l);
    
    jitter_sig = TRand.kr(trig: grain_trig, lo: buf_dur.reciprocal.neg * jitter, hi: buf_dur.reciprocal * jitter);  
    buf_pos = Phasor.kr(trig: t_reset_pos, rate: buf_dur.reciprocal / ControlRate.ir * speed, resetPos: pos);
    pos_sig = Wrap.kr(buf_pos);
    dry_sig = [PlayBuf.ar(1, buf_l, speed, startPos: pos * BufFrames.kr(buf_l), trigger: t_reset_pos, loop: 1), PlayBuf.ar(1, buf_r, speed, startPos: pos * BufFrames.kr(buf_r), trigger: t_reset_pos, loop: 1)];
    dry_sig = Balance2.ar(dry_sig[0], dry_sig[1], pan);

    grain_pitch = Lag.kr(Select.kr(pitch_mode, [speed * pitch_offset, pitch_offset]);) * if(pitch_walk_rate > 0, {
        var trig = Dust.kr(pitch_walk_rate);
        var step = TIRand.kr(0, pitch_walk_step, trig, Array.series(25, 25, -1).sqrt);
        var totalStep = step * TChoose.kr(trig, [1, -1]);
        var scaleDegree = totalStep.mod(7);
        2 ** ((Select.kr(scaleDegree, [0,1,2,3,5,7,9]) + ((totalStep - scaleDegree) / 7 * 12)) / 12);
    }, 1);

    random_interval = Select.kr(pitch_random_scale_type, [
        Select.kr((rand_val * 2).floor, [7,12]),
        Select.kr((rand_val * 4).floor, [7,12,19,24]),
        Select.kr((rand_val * 1).floor, [12]),
        Select.kr((rand_val * 2).floor, [12,24]),
        Select.kr((rand_val * 11).floor, [1,2,3,4,5,6,7,8,9,10,11]),
        Select.kr((rand_val * 6).floor, [2,4,5,7,9,11]),
        Select.kr((rand_val * 6).floor, [2,3,5,7,8,10]),
        Select.kr((rand_val * 4).floor, [2,4,7,9]),
        Select.kr((rand_val * 5).floor, [2,4,6,8,10]) ]);
    grain_pitch = grain_pitch * (2 ** (((rand_val2 < pitch_random_prob) * random_interval * pitch_random_direction)/12));
    
    grainBufFunc = { |buf, pitch, size, vol, dir, pos, jitter|
        var changeTrig, heldEnv, envBuf;
        changeTrig = grain_trig * (TRand.kr(0, 1, grain_trig) < 0.5);
        heldEnv = Latch.kr(TIRand.kr(0, 6, changeTrig), changeTrig);
        envBuf = Select.kr(Select.kr(env_select, [0, 1, 2, 3, 4, 5, 6, heldEnv]), grainEnvs);
        GrainBuf.ar(1, grain_trig, size, buf, pitch * dir, pos + jitter, 2, envbufnum: envBuf, mul: vol)
    };

    processGrains = { |buf_l, buf_r, pitch, size, vol, dir, pos, jitter| [buf_l, buf_r].collect { |buf| grainBufFunc.(buf, pitch, size, vol, dir, pos, jitter) }};
    #sig_l, sig_r = processGrains.(buf_l, buf_r, grain_pitch, grain_size, invDenom, grain_direction, pos_sig, jitter_sig);
    ([1/2, 1/4, 1/8] ++ [2, 4]).do { |harmonic, i| var vol = [subharmonic_1_vol, subharmonic_2_vol, subharmonic_3_vol, overtone_1_vol, overtone_2_vol][i]; 
        var size_mult = if(i < 3) { smoothbass } { 1 }; var grains = processGrains.(buf_l, buf_r, grain_pitch * harmonic, grain_size * size_mult, vol, grain_direction, pos_sig, jitter_sig);
        #sig_l, sig_r = [sig_l + grains[0], sig_r + grains[1]];};
    
    pan_sig = Lag.kr(TRand.kr(trig: grain_trig,	lo: spread.neg,	hi: spread), 0.05);
    granular_sig = Balance2.ar(sig_l, sig_r, pan + pan_sig);
    sig_mix = ((dry_sig * (1 - granular_gain)) + (granular_sig * granular_gain));
     
    sig_mix = BLowShelf.ar(sig_mix, 70, 6, low_gain);
    sig_mix = BPeakEQ.ar(sig_mix, 850, 1, mid_gain);
    sig_mix = BHiShelf.ar(sig_mix, 3900, 6, high_gain);
    
    sig_mix = HPF.ar(sig_mix, Lag.kr(hpf, 0.5));
    sig_mix = MoogFF.ar(sig_mix, Lag.kr(cutoff, 0.5), lpfgain);
    
    SendReply.kr(Impulse.kr(30), '/buf_pos', [voice, buf_pos]);
    SendReply.kr(grain_trig, '/grain_pos', [voice, Wrap.kr(pos_sig + jitter_sig)]);

    Out.ar(out, sig_mix * gain * 1.4);
}).add;
        
        context.server.sync;

        pg = ParGroup.head(context.xg);
        voices = Array.fill(2, { arg i;
            Synth(\synth1, [
                \out, mixBus.index, 
                \buf_l, buffersL[i],
                \buf_r, buffersR[i],
                \voice, i
            ], target: pg);
        });

        context.server.sync;

        SynthDef(\liveDirect, {
            arg out, pan, gain, cutoff, hpf, low_gain, mid_gain, high_gain, isMono, lpfgain;
            var sig = SoundIn.ar([0, 1]);
            sig = Select.ar(isMono, [sig, [sig[0], sig[0]] ]);
            sig = BLowShelf.ar(sig, 70, 6, low_gain);
            sig = BPeakEQ.ar(sig, 850, 1, mid_gain);
            sig = BHiShelf.ar(sig, 3900, 6, high_gain);
            sig = HPF.ar(sig, Lag.kr(hpf, 0.5));
            sig = MoogFF.ar(sig, Lag.kr(cutoff, 0.5), lpfgain);
            sig = Balance2.ar(sig[0], sig[1], pan);
            Out.ar(out, sig * gain);
        }).add;
        
        SynthDef(\liveInputRecorder, {
            arg bufL, bufR, isMono=0, mix, voice;
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
            SendReply.kr(Impulse.kr(30), '/rec_pos', [voice, phasor / BufFrames.kr(bufL)]);
        }).add;
        
        SynthDef(\outputRecorder, {
            arg buf, inBus;
            var sig, phasor, numFrames;
            sig = In.ar(inBus, 2);
            numFrames = BufFrames.kr(buf);
            phasor = Phasor.ar(0, 1, 0, numFrames);
            BufWr.ar(sig, buf, phasor);
            SendReply.kr(Impulse.kr(10), '/output_write_pos', [phasor / numFrames]);
        }).add;

        SynthDef(\monobass, {
            arg bus, mix=0.0;
            var sig = In.ar(bus, 2);
            sig = BHiPass.ar(sig,200)+Pan2.ar(BLowPass.ar(sig[0]+sig[1],200));
            ReplaceOut.ar(bus, sig);
        }).add;  
        
        SynthDef(\bitcrush, {
            arg bus, mix=0.0, rate=44100, bits=24;
            var sig = In.ar(bus, 2);
            var mod = LFNoise1.kr(0.25).range(0.4, 1);
            var bit = LPF.ar(Decimator.ar(sig,rate*mod,bits), 10000);
            ReplaceOut.ar(bus, XFade2.ar(sig, bit, mix * 2 - 1));
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
            ReplaceOut.ar(bus, XFade2.ar(orig, pit, mix - 1));
        }).add;
        
        SynthDef(\sine, {
            arg bus, sine_drive=0.0;
            var orig = In.ar(bus, 2);
            var shaped = Shaper.ar(bufSine, orig * sine_drive);
            ReplaceOut.ar(bus, shaped);
        }).add;
        
        SynthDef(\dimension, {
            arg bus, mix=0;
            var sig = In.ar(bus, 2);
            var wet, depth = 0.3, rate = 0.6, predelay = 0.025, voice1, voice2, voice3, voice4, mid, side, wide;
            var chorus = { |input, delayTime, rate, depth| var mod = SinOsc.kr(rate, [0, pi/2, pi, 3*pi/2]).range(-1, 1) * depth; var delays = delayTime + (mod * 0.02); DelayC.ar(input, 0.05, delays); };
            voice1 = chorus.(sig, predelay * 0.5, rate * 0.99, depth * 0.8);
            voice2 = chorus.(sig, predelay * 0.65, rate * 1.01, depth * 0.9);
            voice3 = chorus.(sig, predelay * 0.85, rate * 0.98, depth * 1.0);
            voice4 = chorus.(sig, predelay * 1.05, rate * 1.02, depth * 0.7);
            wet = [voice1[0] * 0.25 + voice2[0] * 0.25 + voice3[1] * 0.25 + voice4[1] * 0.25,
                   voice1[1] * 0.25 + voice2[1] * 0.25 + voice3[0] * 0.25 + voice4[0] * 0.25];
            mid = (wet[0] + wet[1]) * 0.5;
            side = ((wet[0] - wet[1]) * 0.5 * 1.5);
            wide = [mid + side, mid - side] * 4;
            ReplaceOut.ar(bus, XFade2.ar(sig, wide, mix * 2 - 1));
        }).add;
        
        SynthDef(\tape, {
            arg bus, mix=0.0;
            var orig = In.ar(bus, 2);
            var wet = AnalogTape.ar(orig, 0.9, 1.05, 1.1, 0, 0) * 0.93;
            ReplaceOut.ar(bus, XFade2.ar(orig, wet, mix * 2 - 1));
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
            ReplaceOut.ar(bus, XFade2.ar(dry, wet, mix * 2 - 1));
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
            var loss = AnalogLoss.ar(sig,0.5,0.5,0.5,1);
            var degrade = AnalogDegrade.ar(loss,0.2,0.5,0.1,0.5);
            ReplaceOut.ar(bus, XFade2.ar(sig, degrade, mix * 2 - 1));
        }).add;
        
        SynthDef(\saturation, {
            arg bus, drive=0.0;
            var dry, wet, shaped;
            dry = In.ar(bus, 2);
            wet = dry * (50 * drive + 1);
            shaped = wet.tanh * 0.08;
            ReplaceOut.ar(bus, XFade2.ar(dry, shaped, drive * 2 - 1));
        }).add;

        SynthDef(\delay, { |bus, delay=0.5, fb_amt=0.3, dhpf=20, lpf=20000, w_rate=0.0, w_depth=0.0, stereo=0.27, mix=0.0|
            var input, local, fb, delayed, out, panPos, modRate;
            input = In.ar(bus, 2);
            local = LocalIn.ar(2);
            fb = [input[0] + (local[1] * fb_amt), input[1] + (local[0] * fb_amt)]; 
            fb = Limiter.ar(fb, 0.9).softclip;
            modRate = w_rate * (1 + LFNoise1.kr(0.25, 0.05));
            delayed = DelayC.ar(input + fb, 2, Lag.kr(delay, 1) + LFPar.kr(modRate, mul: w_depth));
            delayed = LPF.ar(HPF.ar(delayed, dhpf), lpf);
            panPos = LFPar.kr(1/(delay*2)).range(-1, 1) * stereo;
            out = [delayed[0] * panPos.max(0) + (delayed[0] * (1-stereo)), delayed[1] * panPos.min(0).neg + (delayed[1] * (1-stereo))];
            LocalOut.ar(out);
            ReplaceOut.ar(bus, XFade2.ar(input, out, mix - 1));
        }).add;

        SynthDef(\jpverb, {
            arg bus, mix=0.0, t60, damp, rsize, earlyDiff, modDepth, modFreq, low, mid, high, lowcut, highcut;
            var dry = In.ar(bus, 2);
            var wet = JPverb.ar(dry, t60, damp, rsize, earlyDiff, modDepth, modFreq, low, mid, high, lowcut, highcut);
            ReplaceOut.ar(bus, XFade2.ar(dry, wet, mix - 1));
        }).add;
    
        SynthDef(\rotate, {
            arg bus, rspeed;
            var sig = In.ar(bus, 2);
            var rot = Rotate2.ar(sig[0], sig[1], LFSaw.kr(rspeed));
            ReplaceOut.ar(bus, rot);
        }).add;
        
        SynthDef(\haas, {
            arg bus, haas=0;
            var sig = In.ar(bus, 2);
            var out = [sig[0], DelayC.ar(sig[1], 0.05, 0.02)];
            ReplaceOut.ar(bus, out);
        }).add;

        SynthDef(\width, {
            arg bus, width=1.0;
            var sig = In.ar(bus, 2);
            var mid = (sig[0] + sig[1]) * 0.5;
            var side = ((sig[0] - sig[1]) * 0.5 * width);
            sig = [mid + side, mid - side];
            ReplaceOut.ar(bus, sig);
        }).add;
               
        SynthDef(\output, {
            arg in, out;
            var sig = In.ar(in, 2);
            Out.ar(out, sig);
        }).add;

        context.server.sync;
        
        bitcrushEffect = Synth.new(\bitcrush, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');
        shimmerEffect = Synth.new(\shimmer, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');
        sineEffect = Synth.new(\sine, [\bus, mixBus.index, \sine_drive, 0.0], context.xg, 'addToTail');
        tapeEffect = Synth.new(\tape, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');  
        wobbleEffect = Synth.new(\wobble, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');
        chewEffect = Synth.new(\chew, [\bus, mixBus.index, \chew_depth, 0.0], context.xg, 'addToTail');
        lossdegradeEffect = Synth.new(\lossdegrade, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');
        delayEffect = Synth.new(\delay, [\bus, mixBus.index, \mix, 0.0,], context.xg, 'addToTail');
        saturationEffect = Synth.new(\saturation, [\bus, mixBus.index, \drive, 0.0], context.xg, 'addToTail');
        widthEffect = Synth.new(\width, [\bus, mixBus.index, \width, 1.0], context.xg, 'addToTail');
        dimensionEffect = Synth.new(\dimension, [\bus, mixBus.index], context.xg, 'addToTail');
        haasEffect = Synth.new(\haas, [\bus, mixBus.index, \haas, 0.0], context.xg, 'addToTail');
        monobassEffect = Synth.new(\monobass, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');
        jpverbEffect = Synth.new(\jpverb, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');
        rotateEffect = Synth.new(\rotate, [\bus, mixBus.index], context.xg, 'addToTail');
        outputSynth = Synth.new(\output, [\in, mixBus.index,\out, context.out_b.index], context.xg, 'addToTail');
        outputRecorder = Synth.new(\outputRecorder, [\buf, outputRecordBuffer, \inBus, mixBus.index], context.xg, 'addToTail');

        this.addCommand(\mix, "f", { arg msg; delayEffect.set(\mix, msg[1]); delayEffect.run(msg[1] > 0); });
        this.addCommand(\delay, "f", { arg msg; delayEffect.set(\delay, msg[1]);	});
    	  this.addCommand(\fb_amt, "f", { arg msg; delayEffect.set(\fb_amt, msg[1]);	});
    	  this.addCommand(\dhpf, "f", { arg msg; delayEffect.set(\dhpf, msg[1]);	});
    	  this.addCommand(\lpf, "f", { arg msg; delayEffect.set(\lpf, msg[1]);	});
    	  this.addCommand(\w_rate, "f", { arg msg; delayEffect.set(\w_rate, msg[1]);	});
    	  this.addCommand(\w_depth, "f", { arg msg; delayEffect.set(\w_depth, msg[1]/100);	});
    	  this.addCommand("stereo", "f", { arg msg; delayEffect.set(\stereo, msg[1]); });

        this.addCommand("reverb_mix", "f", { arg msg; jpverbEffect.set(\mix, msg[1]); jpverbEffect.run(msg[1] > 0); });
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
        this.addCommand("env_select", "ii", { arg msg; var voice = msg[1] - 1; voices[voice].set(\env_select, msg[2]); });
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
        this.addCommand("smoothbass", "if", { arg msg; var voice = msg[1] - 1; currentSmoothbass[voice] = msg[2]; voices[voice].set(\smoothbass, msg[2]); });
        this.addCommand("probability", "if", { arg msg; var voice = msg[1] - 1; currentProbability[voice] = msg[2]; voices[voice].set(\probability, msg[2]); });
        this.addCommand("pitch_random_scale_type", "ii", { arg msg; var voice = msg[1] - 1; currentPitchRandomScale[voice] = msg[2]; voices[voice].set(\pitch_random_scale_type, msg[2]); });
        this.addCommand("pitch_random_prob", "if", { arg msg; var voice = msg[1] - 1; currentPitchRandomProb[voice] = msg[2]; voices[voice].set(\pitch_random_prob, msg[2].abs * 0.01); voices[voice].set(\pitch_random_direction, msg[2].sign); });
        this.addCommand("pitch_walk_rate", "if", { arg msg; var voice = msg[1] - 1; currentPitchWalkRate[voice] = msg[2]; voices[voice].set(\pitch_walk_rate, msg[2]); });
        this.addCommand("pitch_walk_step", "if", { arg msg; var voice = msg[1] - 1; currentPitchWalkStep[voice] = msg[2]; voices[voice].set(\pitch_walk_step, msg[2]); });
        this.addCommand("ratcheting_prob", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\ratcheting_prob, msg[2] * 0.01); });
        this.addCommand("max_ratchets", "ii", { arg msg; var voice = msg[1] - 1; voices[voice].set(\max_ratchets, msg[2]); });

        this.addCommand("bitcrush_mix", "f", { arg msg; bitcrushEffect.set(\mix, msg[1]); bitcrushEffect.run(msg[1] > 0); });
        this.addCommand("bitcrush_rate", "f", { arg msg; bitcrushEffect.set(\rate, msg[1]); });
        this.addCommand("bitcrush_bits", "f", { arg msg; bitcrushEffect.set(\bits, msg[1]); });
        
        this.addCommand("shimmer_mix", "f", { arg msg; shimmerEffect.set(\mix, msg[1]); shimmerEffect.run(msg[1] > 0); });
        this.addCommand("lowpass", "f", { arg msg; shimmerEffect.set(\lowpass, msg[1]); });
        this.addCommand("hipass", "f", { arg msg; shimmerEffect.set(\hipass, msg[1]); });
        this.addCommand("pitchv", "f", { arg msg; shimmerEffect.set(\pitchv, msg[1]); });
        this.addCommand("fb", "f", { arg msg; shimmerEffect.set(\fb, msg[1]); });
        this.addCommand("fbDelay", "f", { arg msg; shimmerEffect.set(\fbDelay, msg[1]); });
        this.addCommand("o2", "i", { arg msg; shimmerEffect.set(\o2, msg[1]); });
        
        this.addCommand("read", "is", { arg msg; this.readBuf(msg[1] - 1, msg[2]); });
        this.addCommand("seek", "if", { arg msg; var voice = msg[1] - 1; var pos = msg[2]; voices[voice].set(\pos, pos); voices[voice].set(\t_reset_pos, 1); });
        this.addCommand("speed", "if", { arg msg; var voice = msg[1] - 1; currentSpeed[voice] = msg[2]; voices[voice].set(\speed, msg[2]); });
        this.addCommand("jitter", "if", { arg msg; var voice = msg[1] - 1; currentJitter[voice] = msg[2]; voices[voice].set(\jitter, msg[2] / 2); });
        this.addCommand("size", "if", { arg msg; var voice = msg[1] - 1; currentSize[voice] = msg[2]; voices[voice].set(\size, msg[2]); });
        this.addCommand("density", "if", { arg msg; var voice = msg[1] - 1; currentDensity[voice] = msg[2]; voices[voice].set(\density, msg[2]); });
        this.addCommand("pan", "if", { arg msg; var voice = msg[1] - 1; currentPan[voice] = msg[2]; voices[voice].set(\pan, msg[2]); });
        this.addCommand("spread", "if", { arg msg; var voice = msg[1] - 1; currentSpread[voice] = msg[2]; voices[voice].set(\spread, msg[2]); });
        this.addCommand("volume", "if", { arg msg; var voice = msg[1] - 1; currentVolume[voice] = msg[2]; voices[voice].set(\gain, msg[2]); });

        this.addCommand("tape_mix", "f", { arg msg; tapeEffect.set(\mix, msg[1]); tapeEffect.run(msg[1] > 0); });
        this.addCommand("sine_drive", "f", { arg msg; sineEffect.set(\sine_drive, msg[1]); sineEffect.run(msg[1] > 0); });
        this.addCommand("drive", "f", { arg msg; saturationEffect.set(\drive, msg[1]); saturationEffect.run(msg[1] > 0); });

        this.addCommand("wobble_mix", "f", { arg msg; wobbleEffect.set(\mix, msg[1]); wobbleEffect.run(msg[1] > 0); });
        this.addCommand("wobble_amp", "f", { arg msg; wobbleEffect.set(\wobble_amp, msg[1]); });
        this.addCommand("wobble_rpm", "f", { arg msg; wobbleEffect.set(\wobble_rpm, msg[1]); });
        this.addCommand("flutter_amp", "f", { arg msg; wobbleEffect.set(\flutter_amp, msg[1]); });
        this.addCommand("flutter_freq", "f", { arg msg; wobbleEffect.set(\flutter_freq, msg[1]); });
        this.addCommand("flutter_var", "f", { arg msg; wobbleEffect.set(\flutter_var, msg[1]); });
        this.addCommand("chew_depth", "f", { arg msg; chewEffect.set(\chew_depth, msg[1]); chewEffect.run(msg[1] > 0); });
        this.addCommand("chew_freq", "f", { arg msg; chewEffect.set(\chew_freq, msg[1]); });
        this.addCommand("chew_variance", "f", { arg msg; chewEffect.set(\chew_variance, msg[1]); });
        this.addCommand("lossdegrade_mix", "f", { arg msg; lossdegradeEffect.set(\mix, msg[1]); lossdegradeEffect.run(msg[1] > 0); });
        
        this.addCommand("eq_low_gain", "if", { arg msg; var voice = msg[1] - 1; currentLowGain[voice] = msg[2]; voices[voice].set(\low_gain, msg[2]); });
        this.addCommand("eq_mid_gain", "if", { arg msg; var voice = msg[1] - 1; currentLowGain[voice] = msg[2]; voices[voice].set(\mid_gain, msg[2]); });
        this.addCommand("eq_high_gain", "if", { arg msg; var voice = msg[1] - 1; currentHighGain[voice] = msg[2]; voices[voice].set(\high_gain, msg[2]); });

        this.addCommand("width", "f", { arg msg; widthEffect.set(\width, msg[1]); widthEffect.run(msg[1] != 1); });
        this.addCommand("dimension_mix", "f", { arg msg; dimensionEffect.set(\mix, msg[1]); dimensionEffect.run(msg[1] > 0); });
        this.addCommand("monobass_mix", "f", { arg msg; monobassEffect.set(\mix, msg[1]); monobassEffect.run(msg[1] > 0); });
        this.addCommand("rspeed", "f", { arg msg; rotateEffect.set(\rspeed, msg[1]); rotateEffect.run(msg[1] > 0); });
        this.addCommand("haas", "i", { arg msg; haasEffect.set(\haas, msg[1]); haasEffect.run(msg[1] > 0); });

        this.addCommand("set_live_input", "ii", { arg msg; var voice = msg[1] - 1; var enable = msg[2]; if (enable == 1, { if (liveInputRecorders[voice].notNil, { liveInputRecorders[voice].free; }); liveInputRecorders[voice] = Synth.new(\liveInputRecorder, [ \bufL, liveInputBuffersL[voice], \bufR, liveInputBuffersR[voice], \mix, liveBufferMix, \voice, voice ], context.xg, 'addToHead'); voices[voice].set( \buf_l, liveInputBuffersL[voice], \buf_r, liveInputBuffersR[voice], \t_reset_pos, 1); }, { if (liveInputRecorders[voice].notNil, { liveInputRecorders[voice].free; }); liveInputRecorders[voice] = nil; }); });
        this.addCommand("live_buffer_mix", "f", { arg msg; liveBufferMix = msg[1]; liveInputRecorders.do({ arg recorder; if (recorder.notNil, {recorder.set(\mix, liveBufferMix);}); }); });
        this.addCommand("live_direct", "ii", { arg msg; var voice = msg[1] - 1; var enable = msg[2]; var currentParams; if (enable == 1, { if (voices[voice].notNil, { voices[voice].free; }); if (liveInputRecorders[voice].notNil, { liveInputRecorders[voice].free; }); voices[voice] = Synth.new(\liveDirect, [ \out, mixBus.index,\pan, currentPan[voice] ? 0,\spread, currentSpread[voice] ? 0,\gain, currentVolume[voice] ? 1,\cutoff, currentCutoff[voice] ? 20000,\lpfgain, currentlpfgain[voice] ? 0.1,\hpf, currentHpf[voice] ? 20,\low_gain, currentLowGain[voice] ? 0,\high_gain, currentHighGain[voice] ? 0 ], target: pg); }, { if (voices[voice].notNil, { voices[voice].free; }); currentParams = Dictionary.newFrom([\speed, currentSpeed[voice] ? 0.1,\jitter, currentJitter[voice] ? 0.25,\size, currentSize[voice] ? 0.1,\density, currentDensity[voice] ? 10,\pitch_offset, currentPitch[voice] ? 1,\pan, currentPan[voice] ? 0,\spread, currentSpread[voice] ? 0,\gain, currentVolume[voice] ? 1,\granular_gain, currentGranularGain[voice] ? 1,\cutoff, currentCutoff[voice] ? 20000,\lpfgain, currentlpfgain[voice] ? 0.1,\hpf, currentHpf[voice] ? 20,\subharmonics_1, currentSubharmonics1[voice] ? 0,\subharmonics_2, currentSubharmonics2[voice] ? 0,\subharmonics_3, currentSubharmonics3[voice] ? 0,\overtones_1, currentOvertones1[voice] ? 0,\overtones_2, currentOvertones2[voice] ? 0,\pitch_mode, currentPitchMode[voice] ? 0,\trig_mode, currentTrigMode[voice] ? 0,\direction_mod, currentDirectionMod[voice] ? 0,\size_variation, currentSizeVariation[voice] ? 0,\smoothbass, currentSmoothbass[voice] ? 1,\low_gain, currentLowGain[voice] ? 0,\high_gain, currentHighGain[voice] ? 0,\probability, currentProbability[voice] ? 100]); voices[voice] = Synth.new(\synth1, [ \out, mixBus.index, \buf_l, buffersL[voice], \buf_r, buffersR[voice], \voice, voice ] ++ currentParams.getPairs, target: pg); voices[voice].set(\t_reset_pos, 1); }); });
        this.addCommand("isMono", "ii", { arg msg; var voice = msg[1] - 1; voices[voice].set(\isMono, msg[2]); });
        this.addCommand("live_mono", "ii", { arg msg; var voice = msg[1] - 1; var mono = msg[2]; if(liveInputRecorders[voice].notNil, {liveInputRecorders[voice].set(\isMono, mono); }); });
        this.addCommand("unload_all", "", {this.unloadAll(); });
        this.addCommand("save_live_buffer", "is", { arg msg; var voice = msg[1] - 1; var filename = msg[2]; var bufL = liveInputBuffersL[voice]; var bufR = liveInputBuffersR[voice]; this.saveLiveBufferToTape(voice, filename); });
        this.addCommand("live_buffer_length", "f", { arg msg; var length = msg[1]; liveInputBuffersL.do({ arg buf; buf.free; }); liveInputBuffersR.do({ arg buf; buf.free; }); liveInputBuffersL = Array.fill(2, {Buffer.alloc(context.server, context.server.sampleRate * length);}); liveInputBuffersR = Array.fill(2, {Buffer.alloc(context.server, context.server.sampleRate * length);}); liveInputRecorders.do({ arg recorder, i; if (recorder.notNil, {recorder.free; liveInputRecorders[i] = Synth.new(\liveInputRecorder, [ \bufL, liveInputBuffersL[i], \bufR, liveInputBuffersR[i], \mix, liveBufferMix ], context.xg, 'addToHead'); voices[i].set( \buf_l, liveInputBuffersL[i], \buf_r, liveInputBuffersR[i], \t_reset_pos, 1); }); }); });
        this.addCommand("set_output_buffer_length", "f", { arg msg; var newLength = msg[1]; outputBufferLength = newLength; if (outputRecorder.notNil) { outputRecorder.free; }; if (outputRecordBuffer.notNil) {outputRecordBuffer.free; }; outputRecordBuffer = Buffer.alloc(context.server, context.server.sampleRate * outputBufferLength, 2); outputRecorder = Synth.new(\outputRecorder, [\buf, outputRecordBuffer, \inBus, mixBus.index], context.xg, 'addToTail'); });
        this.addCommand("save_output_buffer", "s", { arg msg; var filename, path, interleaved, gainBoost = 2.8, crossfadeSamples, actualLength, splitPoint, finalLength, writePos; filename = msg[1]; path = "/home/we/dust/audio/tape/" ++ filename; crossfadeSamples = context.server.sampleRate.asInteger; actualLength = outputRecordBuffer.numFrames; writePos = (currentOutputWritePos ? 0.5) * actualLength; splitPoint = writePos.asInteger;  finalLength = actualLength - crossfadeSamples; interleaved = Buffer.alloc(context.server, finalLength, 2); outputRecordBuffer.loadToFloatArray(action: { |stereoData| var interleavedData = FloatArray.newClear(finalLength * 2), idx = 0, piInv = pi.reciprocal, crossfadeInv = crossfadeSamples.reciprocal; finalLength.do { |sampleIdx| var blendL, blendR; if (sampleIdx < crossfadeSamples) {var crossfadePos = sampleIdx * crossfadeInv, fadeInGain = (1 - cos(crossfadePos * pi)) * 0.5, fadeOutGain = (1 + cos(crossfadePos * pi)) * 0.5, splitIdx = (splitPoint + sampleIdx) % actualLength, beforeIdx = (splitPoint - crossfadeSamples + sampleIdx) % actualLength; blendL = (stereoData[splitIdx * 2] * fadeInGain) + (stereoData[beforeIdx * 2] * fadeOutGain); blendR = (stereoData[splitIdx * 2 + 1] * fadeInGain) + (stereoData[beforeIdx * 2 + 1] * fadeOutGain);} {var sourceIdx = (splitPoint + sampleIdx) % actualLength; blendL = stereoData[sourceIdx * 2]; blendR = stereoData[sourceIdx * 2 + 1];}; interleavedData[idx] = blendL * gainBoost; interleavedData[idx + 1] = blendR * gainBoost; idx = idx + 2; }; interleaved.loadCollection(interleavedData, action: { interleaved.write(path, "WAV", "float"); NetAddr("127.0.0.1", 10111).sendMsg("/twins/output_saved", path); NetAddr("127.0.0.1", 10111).sendMsg("/twins/save_complete"); interleaved.free; }); }); });
        this.addCommand("save_output_buffer_only", "s", { arg msg; var filename, path, interleaved, gainBoost = 2.8, crossfadeSamples, actualLength, splitPoint, finalLength, writePos; filename = msg[1]; path = "/home/we/dust/audio/tape/" ++ filename; crossfadeSamples = context.server.sampleRate.asInteger; actualLength = outputRecordBuffer.numFrames; writePos = (currentOutputWritePos ? 0.5) * actualLength; splitPoint = writePos.asInteger; finalLength = actualLength - crossfadeSamples; interleaved = Buffer.alloc(context.server, finalLength, 2); outputRecordBuffer.loadToFloatArray(action: { |stereoData| var interleavedData = FloatArray.newClear(finalLength * 2), idx = 0, crossfadeInv = crossfadeSamples.reciprocal; finalLength.do { |sampleIdx| var blendL, blendR; if (sampleIdx < crossfadeSamples) {var crossfadePos = sampleIdx * crossfadeInv, fadeInGain = (1 - cos(crossfadePos * pi)) * 0.5, fadeOutGain = (1 + cos(crossfadePos * pi)) * 0.5, splitIdx = (splitPoint + sampleIdx) % actualLength, beforeIdx = (splitPoint - crossfadeSamples + sampleIdx) % actualLength; blendL = (stereoData[splitIdx * 2] * fadeInGain) + (stereoData[beforeIdx * 2] * fadeOutGain); blendR = (stereoData[splitIdx * 2 + 1] * fadeInGain) + (stereoData[beforeIdx * 2 + 1] * fadeOutGain);} {var sourceIdx = (splitPoint + sampleIdx) % actualLength; blendL = stereoData[sourceIdx * 2]; blendR = stereoData[sourceIdx * 2 + 1]; }; interleavedData[idx] = blendL * gainBoost; interleavedData[idx + 1] = blendR * gainBoost; idx = idx + 2; }; interleaved.loadCollection(interleavedData, action: { interleaved.write(path, "WAV", "float"); NetAddr("127.0.0.1", 10111).sendMsg("/twins/save_complete"); interleaved.free; }); }); });

        o = OSCFunc({ |msg| var voice, pos; voice = msg[3].asInteger; pos = msg[4]; NetAddr("127.0.0.1", 10111).sendMsg("/twins/buf_pos", voice, pos); }, '/buf_pos', context.server.addr);
        o_rec = OSCFunc({ |msg| var voice, pos; voice = msg[3].asInteger; pos = msg[4]; NetAddr("127.0.0.1", 10111).sendMsg("/twins/rec_pos", voice, pos); }, '/rec_pos', context.server.addr);
        o_grain = OSCFunc({ |msg| var voice, pos; voice = msg[3].asInteger; pos = msg[4]; NetAddr("127.0.0.1", 10111).sendMsg("/twins/grain_pos", voice, pos); }, '/grain_pos', context.server.addr);   
        o_output = OSCFunc({ |msg| var pos; pos = msg[3]; currentOutputWritePos = pos;}, '/output_write_pos', context.server.addr);
    }

free {
        voices.do({ arg voice; if (voice.notNil) { voice.free; }; });
        buffersL.do({ arg b; if (b.notNil) { b.free; }; });
        buffersR.do({ arg b; if (b.notNil) { b.free; }; });
        liveInputBuffersL.do({ arg b; if (b.notNil) { b.free; }; });
        liveInputBuffersR.do({ arg b; if (b.notNil) { b.free; }; });
        liveInputRecorders.do({ arg s; if (s.notNil) { s.free; }; });
        if (grainEnvs.notNil) { grainEnvs.do({ arg buf; if (buf.notNil) { buf.free; }; }); };
        if (outputRecorder.notNil) { outputRecorder.free; outputRecorder = nil; };
        if (outputRecordBuffer.notNil) { outputRecordBuffer.free; outputRecordBuffer = nil; };
        if (o.notNil) { o.free; o = nil; };
        if (o_rec.notNil) { o_rec.free; o_rec = nil; };
        if (o_grain.notNil) { o_grain.free; o_grain = nil; };
        if (o_output.notNil) { o_output.free; o_output = nil; };
        if (wobbleBuffer.notNil) { wobbleBuffer.free; wobbleBuffer = nil; };
        if (mixBus.notNil) { mixBus.free; mixBus = nil; };
        if (bufSine.notNil) { bufSine.free; bufSine = nil; };
        if (jpverbEffect.notNil) { jpverbEffect.free; jpverbEffect = nil; };
        if (shimmerEffect.notNil) { shimmerEffect.free; shimmerEffect = nil; };
        if (saturationEffect.notNil) { saturationEffect.free; saturationEffect = nil; };
        if (tapeEffect.notNil) { tapeEffect.free; tapeEffect = nil; };
        if (chewEffect.notNil) { chewEffect.free; chewEffect = nil; };
        if (widthEffect.notNil) { widthEffect.free; widthEffect = nil; };
        if (monobassEffect.notNil) { monobassEffect.free; monobassEffect = nil; };
        if (lossdegradeEffect.notNil) { lossdegradeEffect.free; lossdegradeEffect = nil; };
        if (sineEffect.notNil) { sineEffect.free; sineEffect = nil; };
        if (wobbleEffect.notNil) { wobbleEffect.free; wobbleEffect = nil; };
        if (outputSynth.notNil) { outputSynth.free; outputSynth = nil; };
        if (delayEffect.notNil) { delayEffect.free; delayEffect = nil; };
        if (bitcrushEffect.notNil) { bitcrushEffect.free; bitcrushEffect = nil; };
        if (rotateEffect.notNil) { rotateEffect.free; rotateEffect = nil; };
        if (haasEffect.notNil) { haasEffect.free; haasEffect = nil; };
        if (dimensionEffect.notNil) { dimensionEffect.free; dimensionEffect = nil; };
    }
}