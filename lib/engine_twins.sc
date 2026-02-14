Engine_twins : CroneEngine {

var dimensionEffect, haasEffect, bitcrushEffect, saturationEffect, delayEffect, reverbEffect, shimmerEffect, tapeEffect, chewEffect, widthEffect, monobassEffect, sineEffect, wobbleEffect, lossdegradeEffect, rotateEffect, glitchEffect;
var <buffersL, <buffersR, wobbleBuffer, mixBus, postFxBus, shimmerBus, parallelBus, <voices, bufSine, pg, <liveInputBuffersL, <liveInputBuffersR, <liveInputRecorders, o, o_output, o_rec, o_grain, o_voice_peak;
var mixToParallelRouter, parallelToPostFxRouter, finalOutputRouter;
var currentSpeed, currentJitter, currentSize, currentDensity, currentDensityModAmt, currentPitch, currentPan, currentSpread, currentVolume, currentGranularGain, currentCutoff, currentHpf, currentlpfgain, currentSubharmonics1, currentSubharmonics2, currentSubharmonics3, currentOvertones1, currentOvertones2, currentPitchMode, currentTrigMode, currentDirectionMod, currentSizeVariation, currentSmoothbass, currentLowGain, currentMidGain, currentHighGain, currentProbability, liveBufferMix = 1.0, currentPitchWalkRate, currentPitchWalkStep, currentPitchRandomProb, currentPitchRandomScale, currentRatchetingProb, currentPitchLag;
var <outputRecordBuffer, <outputRecorder;
var outputBufferLength = 8, currentOutputWritePos;
var grainEnvs, pitchScaleBuffers, pitchScaleLengths;

classvar pitchScales;
*initClass {
    pitchScales = [
        [7, 12],
        [7, 12, 19, 24],
        [12],
        [12, 24],
        [1,2,3,4,5,6,7,8,9,10,11],
        [2,4,5,7,9,11],
        [2,3,5,7,8,10],
        [2,4,7,9],
        [2,4,6,8,10]
    ];
}

*new { arg context, doneCallback; ^super.new(context, doneCallback); }

readBuf { arg i, path; 
    if(buffersL[i].notNil && buffersR[i].notNil, { 
        if (File.exists(path), { 
            var numChannels = SoundFile.use(path.asString(), { |f| f.numChannels }); 
            
            Buffer.readChannel(context.server, path, 0, -1, [0], { |b| 
                voices[i].set(\buf_l, b); 
                buffersL[i].free; 
                buffersL[i] = b; 
                voices[i].set(\t_reset_pos, 1); 
                
                if (numChannels > 1, { 
                    Buffer.readChannel(context.server, path, 0, -1, [1], { |b| 
                        voices[i].set(\buf_r, b); 
                        buffersR[i].free; 
                        buffersR[i] = b; 
                        voices[i].set(\t_reset_pos, 1); 
                        NetAddr("127.0.0.1", 10111).sendMsg("/twins/buffer_loaded", i + 1);
                    }); 
                }, { 
                    voices[i].set(\buf_r, b); 
                    buffersR[i].free; 
                    buffersR[i] = b; 
                    voices[i].set(\t_reset_pos, 1); 
                    NetAddr("127.0.0.1", 10111).sendMsg("/twins/buffer_loaded", i + 1);
                }); 
            }); 
        }, {
            NetAddr("127.0.0.1", 10111).sendMsg("/twins/buffer_loaded", i + 1);
        }); 
    }); 
}

unloadAll { 2.do({ arg i, live_buffer_length; var newBufL = Buffer.alloc(context.server, context.server.sampleRate * live_buffer_length); var newBufR = Buffer.alloc(context.server, context.server.sampleRate * live_buffer_length); if(buffersL[i].notNil, { buffersL[i].free; }); if(buffersR[i].notNil, { buffersR[i].free; }); buffersL.put(i, newBufL); buffersR.put(i, newBufR); if(voices[i].notNil, { voices[i].set( \buf_l, newBufL, \buf_r, newBufR, \t_reset_pos, 1 ); }); liveInputBuffersL[i].zero; liveInputBuffersR[i].zero; if(liveInputRecorders[i].notNil, { liveInputRecorders[i].free; liveInputRecorders[i] = nil; }); }); wobbleBuffer.zero; }

saveLiveBufferToTape { arg voice, filename; var path = "/home/we/dust/audio/tape/" ++ filename; var bufL = liveInputBuffersL[voice]; var bufR = liveInputBuffersR[voice]; var interleaved = Buffer.alloc(context.server, bufL.numFrames, 2); bufL.loadToFloatArray(action: { |leftData| bufR.loadToFloatArray(action: { |rightData| var interleavedData = Array.new(leftData.size * 2); leftData.size.do { |i| interleavedData.add(leftData[i]); interleavedData.add(rightData[i]); }; interleaved.loadCollection(interleavedData, action: { interleaved.write(path, "WAV", "float"); this.readBuf(voice, path); interleaved.free; }); }); }); }

alloc {
        buffersL = Array.fill(2, { arg i; Buffer.alloc(context.server, context.server.sampleRate * 1); });
        buffersR = Array.fill(2, { arg i; Buffer.alloc(context.server, context.server.sampleRate * 1); });

        liveInputBuffersL = Array.fill(2, {Buffer.alloc(context.server, context.server.sampleRate * 8); });
        liveInputBuffersR = Array.fill(2, {Buffer.alloc(context.server, context.server.sampleRate * 8); });
        liveInputRecorders = Array.fill(2, { nil });

        outputRecordBuffer = Buffer.alloc(context.server, context.server.sampleRate * outputBufferLength, 2);

        bufSine = Buffer.alloc(context.server, 1024 * 16, 1); bufSine.sine2([2], [0.5], false);
        wobbleBuffer = Buffer.alloc(context.server, 48000 * 5, 2);
        mixBus = Bus.audio(context.server, 2);
        postFxBus = Bus.audio(context.server, 2);
        shimmerBus = Bus.audio(context.server, 2);
        parallelBus = Bus.audio(context.server, 2);

        grainEnvs = [
            Env.triangle(1, 1),
            Env.new([0, 1, 1, 0], [0.15, 0.7, 0.15], [4, 0, -4]),
            Env.perc(0.01, 0.99, 1, -4),
            Env.perc(0.99, 0.01, 1, 4),
            Env.adsr(0.25, 0.15, 0.65, 1, 1, -4, 0)
        ].collect { |env| Buffer.sendCollection(context.server, env.discretize) };
        
        pitchScaleBuffers = pitchScales.collect { |scale| Buffer.sendCollection(context.server, scale, 1) };
        pitchScaleLengths = pitchScales.collect(_.size);

        currentSpeed = [0.1, 0.1]; currentJitter = [0.25, 0.25]; currentSize = [0.1, 0.1]; currentDensity = [10, 10]; currentPitch = [1, 1]; currentPan = [0, 0]; currentSpread = [0, 0]; currentVolume = [1, 1]; currentGranularGain = [1, 1]; currentCutoff = [20000, 20000]; currentlpfgain = [0.1, 0.1]; currentHpf = [20, 20]; currentSubharmonics1 = [0, 0]; currentSubharmonics2 = [0, 0]; currentSubharmonics3 = [0, 0]; currentOvertones1 = [0, 0]; currentOvertones2 = [0, 0]; currentPitchMode = [0, 0]; currentTrigMode = [0, 0]; currentDirectionMod = [0, 0]; currentSizeVariation = [0, 0]; currentSmoothbass = [1, 1]; currentDensityModAmt = [0, 0]; currentLowGain = [0, 0]; currentMidGain = [0, 0]; currentHighGain = [0, 0]; currentProbability = [100, 100]; liveBufferMix = 1.0; currentPitchWalkRate = [2, 2]; currentPitchWalkStep = [2, 2]; currentPitchRandomProb = [0, 0]; currentPitchRandomScale = [0, 0]; currentRatchetingProb = [0, 0]; currentPitchLag = [0, 0];

        context.server.sync;

        SynthDef(\synth1, {
            arg out, voice, buf_l, buf_r, pos, speed, jitter, size, density, density_mod_amt, pitch_offset, pan, spread, gain, t_reset_pos,
            granular_gain, pitch_mode, trig_mode, subharmonics_1, subharmonics_2, subharmonics_3, overtones_1, overtones_2, 
            cutoff, hpf, hpfq, lpfgain, direction_mod, size_variation, low_gain, mid_gain, high_gain, smoothbass,
            probability, pitch_walk_rate, pitch_walk_step, env_select = 0, pitch_random_prob=0, pitch_random_scale_buf=0, pitch_random_scale_len=1, pitch_random_direction=1,
            ratcheting_prob=0, pitch_lag_time;

            var grain_trig, jitter_sig, buf_dur, pan_sig, buf_pos, sig_mix, density_mod, dry_sig, granular_sig, base_pitch, grain_pitch, grain_size;
            var main_vol = 1 / (1 + subharmonics_1 + subharmonics_2 + subharmonics_3 + overtones_1 + overtones_2);
            var subharmonic_1_vol = subharmonics_1 * main_vol * 2;
            var subharmonic_2_vol = subharmonics_2 * main_vol * 2;
            var subharmonic_3_vol = subharmonics_3 * main_vol * 2;
            var overtone_1_vol = overtones_1 * main_vol * 1.5;
            var overtone_2_vol = overtones_2 * main_vol * 1.5;
            var grain_direction, base_trig, base_grain_trig;
            var rand_val, rand_val2;
            var random_interval;
            var ratchet_gate, extra_trig;
            var signal;
            var trigger60 = Impulse.kr(60);
            var stepIndex, actualStep, direction, totalStep;
            var scaleDegree, octaveShift, semitones;
            var grain_pan, envBuf, randomEnv;
            var harmonics, volumes;
            var grains, vol, size_mults;

            speed = Lag.kr(speed, 1);
            density_mod = density * (2**(LFNoise1.kr(density).range(0, 1) * density_mod_amt));
            base_trig = Select.kr(trig_mode, [Impulse.kr(density_mod), Dust.kr(density_mod)]);
    
            ratchet_gate = base_trig * (TRand.kr(trig: base_trig, lo: 0, hi: 1) < ratcheting_prob);
            extra_trig = TDelay.kr(ratchet_gate, density_mod.reciprocal * 0.5);
            base_grain_trig = base_trig + extra_trig;
            grain_trig = CoinGate.kr(probability, base_grain_trig);

            rand_val = TRand.kr(trig: grain_trig, lo: 0, hi: 1);
            rand_val2 = TRand.kr(trig: grain_trig, lo: 0, hi: 1);
            grain_size = size * (1 + TRand.kr(trig: grain_trig, lo: size_variation.neg, hi: size_variation));
            grain_direction = Select.kr(pitch_mode, [1, Select.kr(speed.abs > 0.001, [1, speed.sign])]) * Select.kr((rand_val < direction_mod), [1, -1]);
            buf_dur = BufDur.kr(buf_l);
    
            jitter_sig = TRand.kr(trig: grain_trig, lo: buf_dur.reciprocal.neg * jitter, hi: buf_dur.reciprocal * jitter);  
            buf_pos = Phasor.kr(trig: t_reset_pos, rate: buf_dur.reciprocal / ControlRate.ir * speed, start: 0, end: 1, resetPos: pos);
            dry_sig = [PlayBuf.ar(1, buf_l, speed, startPos: pos * BufFrames.kr(buf_l), trigger: t_reset_pos, loop: 1), PlayBuf.ar(1, buf_r, speed, startPos: pos * BufFrames.kr(buf_r), trigger: t_reset_pos, loop: 1)];
            dry_sig = Balance2.ar(dry_sig[0], dry_sig[1], pan);

            grain_pitch = Lag.kr(Select.kr(pitch_mode, [speed * pitch_offset, pitch_offset]), pitch_lag_time) * if(pitch_walk_rate > 0, {var walkTrig, stepIndex, actualStep, direction, totalStep, scaleDegree, octaveShift, semitones, scale;
              walkTrig = Impulse.kr(pitch_walk_rate.clip(0.1, 20));
              stepIndex = TWChoose.kr(walkTrig, (1..7), [0.5, 0.25, 0.12, 0.07, 0.04, 0.015, 0.005].normalizeSum);
              actualStep = stepIndex.min(pitch_walk_step.clip(1, 7));
              direction = TIRand.kr(0, 1, walkTrig) * 2 - 1;
              direction = Lag.kr(direction, 0.5);
              totalStep = Integrator.kr(actualStep * direction * walkTrig, 0.995); 
              scaleDegree = totalStep.abs.mod(5); 
              octaveShift = (totalStep / 7).floor.clip(-2, 2) * 12;
              scale = [0, 2, 4, 7, 9];
              semitones = Select.kr(scaleDegree, scale) + octaveShift;
              2 ** (semitones / 12)
            }, 1);

            random_interval = BufRd.kr(1, pitch_random_scale_buf, TIRand.kr(0, (pitch_random_scale_len - 1).max(0), grain_trig));
            grain_pitch = grain_pitch * (2 ** (((rand_val2 < pitch_random_prob) * random_interval * pitch_random_direction)/12));
            grain_pan = (pan + TRand.kr(trig: grain_trig, lo: spread.neg, hi: spread)).clip(-1, 1);
            randomEnv = TIRand.kr(0, 5, grain_trig);
            envBuf = Select.kr(env_select, [-1] ++ grainEnvs ++ [Select.kr(randomEnv, grainEnvs)]);

            harmonics = [1, 1/2, 1/4, 1/8, 2, 4];
            volumes = [main_vol, subharmonic_1_vol, subharmonic_2_vol, subharmonic_3_vol, overtone_1_vol, overtone_2_vol];
            size_mults = [1, smoothbass, smoothbass, smoothbass, 1, 1];
            
            grains = harmonics.collect { |harmonic, i|
                GrainBuf.ar(
                    numChannels: 2,
                    trigger: grain_trig, 
                    dur: grain_size * size_mults[i], 
                    sndbuf: buf_l, 
                    rate: grain_pitch * harmonic * grain_direction, 
                    pos: buf_pos + jitter_sig, 
                    interp: 2, 
                    pan: grain_pan,
                    envbufnum: envBuf, 
                    mul: volumes[i]
                );
            };
            
            grains = grains ++ harmonics.collect { |harmonic, i|
                GrainBuf.ar(
                    numChannels: 2,
                    trigger: grain_trig, 
                    dur: grain_size * size_mults[i], 
                    sndbuf: buf_r, 
                    rate: grain_pitch * harmonic * grain_direction, 
                    pos: buf_pos + jitter_sig, 
                    interp: 2, 
                    pan: grain_pan,
                    envbufnum: envBuf, 
                    mul: volumes[i]
                );
            };
            
            granular_sig = Mix.ar(grains);
            sig_mix = dry_sig * (1 - granular_gain) + (granular_sig * granular_gain);
     
            sig_mix = BLowShelf.ar(sig_mix, 60, 6, low_gain);
            sig_mix = BPeakEQ.ar(sig_mix, 700, 1, mid_gain);
            sig_mix = BHiShelf.ar(sig_mix, 3900, 6, high_gain);
    
            sig_mix = HPF.ar(sig_mix, Lag.kr(hpf, 0.6));
            sig_mix = MoogFF.ar(sig_mix, Lag.kr(cutoff, 0.6), lpfgain);
            
            SendReply.kr(trigger60, '/buf_pos', [voice, buf_pos]);
            SendReply.kr(grain_trig, '/grain_pos', [voice, Wrap.kr(buf_pos + jitter_sig), grain_size]);
            signal = sig_mix * Lag.kr(gain) * 1.25;
            SendReply.kr(trigger60, '/voice_peak', [voice, Peak.kr(signal[0], trigger60), Peak.kr(signal[1], trigger60)]);

            Out.ar(out, signal);
        }).add;

        context.server.sync;

        pg = ParGroup.head(context.xg);
        voices = Array.fill(2, { arg i;
            Synth(\synth1, [
                \out, mixBus.index, 
                \buf_l, buffersL[i],
                \buf_r, buffersR[i],
                \voice, i,
                \pitch_random_scale_buf, pitchScaleBuffers[0].bufnum,
                \pitch_random_scale_len, pitchScaleLengths[0]
            ], target: pg);
        });

        context.server.sync;

        SynthDef(\liveDirect, {
            arg out, pan, gain, cutoff, hpf, low_gain, mid_gain, high_gain, isMono, lpfgain;
            var sig = SoundIn.ar([0, 1]);
            sig = Select.ar(isMono, [sig, [sig[0], sig[0]] ]);
            sig = BLowShelf.ar(sig, 60, 6, low_gain);
            sig = BPeakEQ.ar(sig, 700, 1, mid_gain);
            sig = BHiShelf.ar(sig, 3900, 6, high_gain);
            sig = HPF.ar(sig, Lag.kr(hpf, 0.6));
            sig = MoogFF.ar(sig, Lag.kr(cutoff, 0.6), lpfgain);
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

        SynthDef(\delay, {
            arg inBus, outBus, mix=0.0, delay=0.5, fb_amt=0.3, dhpf=20, lpf=20000, w_rate=0.0, w_depth=0.0, stereo=0.27;
            var input, local, fb, delayed, wet, fbGain;
            var mod1, mod2, mod3, combinedMod;
            var lfo1Rate, lfo2Rate, lfo3Rate;
            var drift, microWobble, macroWobble;
            input = In.ar(inBus, 2);
            local = LocalIn.ar(2);
            fb = LPF.ar(HPF.ar(local, dhpf), lpf);
            fbGain = 1.35 * (1 - (stereo * 0.35));
            fb = (fbGain * [fb[1] * fb_amt, fb[0] * fb_amt]).softclip;
            lfo1Rate = w_rate * 0.17;
            drift = LFDNoise3.kr(lfo1Rate) * w_depth * 0.4;
            lfo2Rate = w_rate * (1 + LFNoise1.kr(0.13, 0.18));
            microWobble = (LFTri.kr(lfo2Rate) + (LFDNoise1.kr(lfo2Rate * 2.3) * 0.45)) * w_depth * 0.35;
            lfo3Rate = w_rate * 0.71;
            macroWobble = ((SinOsc.kr(lfo3Rate) * LFNoise2.kr(lfo3Rate * 0.3, 0.6, 0.7)) + (LFDNoise3.kr(lfo3Rate * 1.41) * 0.4)) * w_depth * 0.25;
            combinedMod = drift + microWobble + macroWobble;
            combinedMod = combinedMod + (Latch.kr(LFNoise0.kr(w_rate * 6.3), Dust.kr(w_rate * 4.7)) * w_depth * 0.08);
            combinedMod = Lag.kr(combinedMod, 0.003);
            delayed = DelayC.ar(input + fb, 2, Lag.kr(delay, 0.7) + combinedMod);
            wet = Balance2.ar(delayed[0], delayed[1], (SinOsc.kr(1/(delay.max(0.1)*2)) + (LFNoise2.kr(0.4) * 0.3)).range(-1, 1) * stereo);
            LocalOut.ar(wet);
            Out.ar(outBus, wet * mix * 1.6);
        }).add;
        
        SynthDef(\reverb, {
            arg inBus1, inBus2, outBus, mix=0.0, t60, damp, rsize, earlyDiff, modDepth, modFreq, low, mid, high, lowcut, highcut, shimmer_mix=0.0, shimmer_lowpass=8000, shimmer_fb=0.38, shimmer_hipass=600, shimmer_oct=2;
            var combined, reverb_input, reverb_output, pitch_shifted, pitch_feedback, reverb_feedback, limited_feedback;
            combined = In.ar(inBus1, 2) + In.ar(inBus2, 2);
            reverb_feedback = LocalIn.ar(2);
            limited_feedback = (reverb_feedback * 0.6).tanh * 2;
            pitch_shifted = PitchShift.ar(limited_feedback, 0.5, shimmer_oct, 0.03, 0.01, mul:5);
            pitch_shifted = LPF.ar(pitch_shifted, shimmer_lowpass);
            pitch_shifted = HPF.ar(pitch_shifted, shimmer_hipass);
            pitch_feedback = (pitch_shifted * shimmer_fb.clip(0, 0.95)).tanh;
            reverb_input = combined + (pitch_feedback * shimmer_mix);
            reverb_input = reverb_input.softclip;
            reverb_output = JPverb.ar(reverb_input, t60, damp, rsize, earlyDiff, modDepth, modFreq, low, mid, high, lowcut, highcut);
            LocalOut.ar(reverb_output);
            Out.ar(outBus, reverb_output * mix * 1.4);
        }).add;

        SynthDef(\shimmer, {
            arg inBus, outBus, reverbBus, mix=0.0, lowpass1=13000, hipass1=1400, pitchv1=0.02, fb1=0.0, fbDelay1=0.15, shimmer_oct1=2;
            var input = In.ar(inBus, 2);
            var hpf = HPF.ar(input, hipass1);
            var pit = PitchShift.ar(hpf, 0.5, shimmer_oct1, pitchv1, 1, mul:4);
            var fbSig = LocalIn.ar(2);
            var fbProcessed = fbSig * fb1;
            pit = LPF.ar((pit + fbProcessed), lowpass1);
            LocalOut.ar(DelayN.ar(pit, 0.5, fbDelay1));
            Out.ar(reverbBus, pit * mix);
            Out.ar(outBus, pit * mix * 1.4);
        }).add;

        SynthDef(\monobass, {
            arg bus, mix=0.0;
            var sig = In.ar(bus, 2);
            sig = BHiPass.ar(sig,190)+Pan2.ar(BLowPass.ar(sig[0]+sig[1],190));
            ReplaceOut.ar(bus, sig);
        }).add;  
        
        SynthDef(\bitcrush, {
            arg bus, mix=0.0, rate=44100, bits=24;
            var sig = In.ar(bus, 2);
            var mod = LFNoise1.kr(0.25).range(0.4, 1);
            var bit = LPF.ar(Decimator.ar(sig, Lag.kr(rate, 0.6) * mod, bits), 10000);
            ReplaceOut.ar(bus, XFade2.ar(sig, bit, mix * 2 - 1));
        }).add;

        SynthDef(\sine, {
            arg bus, sine_drive_wet=0;
            var orig = In.ar(bus, 2);
            var shaped = Shaper.ar(bufSine, orig);
            ReplaceOut.ar(bus, SelectX.ar(sine_drive_wet, [orig, shaped]));
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
        
        SynthDef(\glitch, {
            arg bus, mix=0.0, probability=3, glitchRatio=0.5, minLength=0.01, maxLength=0.2, reverse=0.3, pitch=0.2;
            var sig, glitchBuffer, trigOn, trigOff, isGlitching, writePos, glitchLength, glitchStart, shouldReverse, pitchShift, readRate, glitchPos, glitched, env, wet;
            sig = In.ar(bus, 2);
            glitchBuffer = LocalBuf(48000 * 0.5, 2);
            trigOn = Dust.kr(probability * glitchRatio);
            trigOff = Dust.kr(probability * (1 - glitchRatio));
            isGlitching = SetResetFF.kr(trigOn, trigOff);
            writePos = Phasor.ar(0, 1, 0, BufFrames.kr(glitchBuffer));
            BufWr.ar(sig, glitchBuffer, writePos);
            glitchLength = TRand.kr(minLength, maxLength, trigOn) * SampleRate.ir;
            glitchStart = TRand.kr(0, BufFrames.kr(glitchBuffer) - glitchLength, trigOn);
            shouldReverse = TRand.kr(0, 1, trigOn) < reverse;
            pitchShift = TRand.kr(0.5, 2, trigOn);
            readRate = Select.kr(shouldReverse, [1, -1]) * Select.kr(TRand.kr(0, 1, trigOn) < pitch, [1, pitchShift]);
            glitchPos = Phasor.ar(trigOn, readRate, glitchStart, glitchStart + glitchLength, glitchStart);
            glitched = BufRd.ar(2, glitchBuffer, glitchPos, interpolation: 2);
            env = EnvGen.kr(Env.asr(0.002, 1, 0.005), gate: isGlitching);
            wet = SelectX.ar(env, [sig, glitched]);
            ReplaceOut.ar(bus, XFade2.ar(sig, wet, mix * 2 - 1));
        }).add;

        SynthDef(\tape, {
            arg bus, mix=0.0;
            var orig = In.ar(bus, 2);
            var wet = AnalogTape.ar(orig, 0.93, 0.93, 0.93, 0, 0) * 0.85;
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
            var loss = AnalogLoss.ar(sig,0.5,1,0.5,0.5);
            var depth=LFPar.kr(1/5,Rand(0,2),0.4,0.5);
	          var amount=LFPar.kr(1/2,Rand(0,2),0.4,0.5);
	          var variance=LFPar.kr(1/3,Rand(0,2),0.4,0.5);
	          var envelope=LFPar.kr(1/4,Rand(0,2),0.4,0.5);
            var degrade = AnalogDegrade.ar(loss,depth,amount,variance,envelope);
            ReplaceOut.ar(bus, XFade2.ar(sig, degrade, mix * 2 - 1));
        }).add;
        
        SynthDef(\saturation, {
            arg bus, drive=0.0, tone=0.5, character=0.5;
            var dry = In.ar(bus, 2);
            var stage1 = ((1 + (drive * 0.3)) * dry).softclip;
            var stage2 = ((1 + (drive * 0.4)) * stage1).tanh;
            var tube = SelectX.ar(character, [stage2, (stage2.abs * stage2.sign)]);
            var filtered = LPF.ar(tube, 16000 - (drive * 4000));
            ReplaceOut.ar(bus, XFade2.ar(dry, filtered, drive * 2 - 1));
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
        sineEffect = Synth.new(\sine, [\bus, mixBus.index, \sine_drive_wet, 0.0], context.xg, 'addToTail');
        tapeEffect = Synth.new(\tape, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');  
        wobbleEffect = Synth.new(\wobble, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');
        chewEffect = Synth.new(\chew, [\bus, mixBus.index, \chew_depth, 0.0], context.xg, 'addToTail');
        lossdegradeEffect = Synth.new(\lossdegrade, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');
        glitchEffect = Synth.new(\glitch, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');
        saturationEffect = Synth.new(\saturation, [\bus, mixBus.index, \drive, 0.0], context.xg, 'addToTail');

        delayEffect = Synth.new(\delay, [\inBus, mixBus.index, \outBus, parallelBus.index, \mix, 0.0], context.xg, 'addToTail');
        shimmerEffect = Synth.new(\shimmer, [\inBus, mixBus.index, \outBus, parallelBus.index, \reverbBus, shimmerBus.index, \mix, 0.0], context.xg, 'addToTail');
        reverbEffect = Synth.new(\reverb, [\inBus1, mixBus.index, \inBus2, shimmerBus.index, \outBus, parallelBus.index, \mix, 0.0], context.xg, 'addToTail');

        mixToParallelRouter = Synth.new(\output, [\in, mixBus.index, \out, parallelBus.index], context.xg, 'addToTail');
        parallelToPostFxRouter = Synth.new(\output, [\in, parallelBus.index, \out, postFxBus.index], context.xg, 'addToTail');

        dimensionEffect = Synth.new(\dimension, [\bus, postFxBus.index], context.xg, 'addToTail');
        haasEffect = Synth.new(\haas, [\bus, postFxBus.index, \haas, 0.0], context.xg, 'addToTail');
        monobassEffect = Synth.new(\monobass, [\bus, postFxBus.index, \mix, 0.0], context.xg, 'addToTail');
        widthEffect = Synth.new(\width, [\bus, postFxBus.index, \width, 1.0], context.xg, 'addToTail');
        rotateEffect = Synth.new(\rotate, [\bus, postFxBus.index], context.xg, 'addToTail');
        
        outputRecorder = Synth.new(\outputRecorder, [\buf, outputRecordBuffer, \inBus, postFxBus.index], context.xg, 'addToTail');
        finalOutputRouter = Synth.new(\output, [\in, postFxBus.index, \out, context.out_b.index], context.xg, 'addToTail');

        this.addCommand(\mix, "f", { arg msg; delayEffect.set(\mix, msg[1]); delayEffect.run(msg[1] > 0); });
        this.addCommand(\delay, "f", { arg msg; delayEffect.set(\delay, msg[1]); });
        this.addCommand(\fb_amt, "f", { arg msg; delayEffect.set(\fb_amt, msg[1]); });
        this.addCommand(\dhpf, "f", { arg msg; delayEffect.set(\dhpf, msg[1]); });
        this.addCommand(\lpf, "f", { arg msg; delayEffect.set(\lpf, msg[1]); });
        this.addCommand(\w_rate, "f", { arg msg; delayEffect.set(\w_rate, msg[1]); });
        this.addCommand(\w_depth, "f", { arg msg; delayEffect.set(\w_depth, msg[1]/100); });
        this.addCommand("stereo", "f", { arg msg; delayEffect.set(\stereo, msg[1]); });
        
        this.addCommand("reverb_mix", "f", { arg msg; reverbEffect.set(\mix, msg[1]); reverbEffect.run(msg[1] > 0); });
        this.addCommand("shimmer_mix", "f", { arg msg; reverbEffect.set(\shimmer_mix, msg[1]); });
        this.addCommand("shimmer_lowpass", "f", { arg msg; reverbEffect.set(\shimmer_lowpass, msg[1]); });
        this.addCommand("shimmer_hipass", "f", { arg msg; reverbEffect.set(\shimmer_hipass, msg[1]); });
        this.addCommand("shimmer_fb", "f", { arg msg; reverbEffect.set(\shimmer_fb, msg[1]); });
        this.addCommand("shimmer_oct", "f", { arg msg; reverbEffect.set(\shimmer_oct, msg[1]); });
        this.addCommand("t60", "f", { arg msg; reverbEffect.set(\t60, msg[1]); });
        this.addCommand("damp", "f", { arg msg; reverbEffect.set(\damp, msg[1]); });
        this.addCommand("rsize", "f", { arg msg; reverbEffect.set(\rsize, msg[1]); });
        this.addCommand("earlyDiff", "f", { arg msg; reverbEffect.set(\earlyDiff, msg[1]); });
        this.addCommand("modDepth", "f", { arg msg; reverbEffect.set(\modDepth, msg[1]); });
        this.addCommand("modFreq", "f", { arg msg; reverbEffect.set(\modFreq, msg[1]); });
        this.addCommand("low", "f", { arg msg; reverbEffect.set(\low, msg[1]); });
        this.addCommand("mid", "f", { arg msg; reverbEffect.set(\mid, msg[1]); });
        this.addCommand("high", "f", { arg msg; reverbEffect.set(\high, msg[1]); });
        this.addCommand("lowcut", "f", { arg msg; reverbEffect.set(\lowcut, msg[1]); });
        this.addCommand("highcut", "f", { arg msg; reverbEffect.set(\highcut, msg[1]); });
        
        this.addCommand("shimmer_mix1", "f", { arg msg; shimmerEffect.set(\mix, msg[1]); shimmerEffect.run(msg[1] > 0); });
        this.addCommand("shimmer_oct1", "f", { arg msg; shimmerEffect.set(\shimmer_oct1, msg[1]); });
        this.addCommand("lowpass1", "f", { arg msg; shimmerEffect.set(\lowpass1, msg[1]); });
        this.addCommand("hipass1", "f", { arg msg; shimmerEffect.set(\hipass1, msg[1]); });
        this.addCommand("pitchv1", "f", { arg msg; shimmerEffect.set(\pitchv1, msg[1]); });
        this.addCommand("fb1", "f", { arg msg; shimmerEffect.set(\fb1, msg[1]); });
        this.addCommand("fbDelay1", "f", { arg msg; shimmerEffect.set(\fbDelay1, msg[1]); });

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
        this.addCommand("pitch_random_scale_type", "ii", { arg msg; var voice = msg[1] - 1; var scaleType = msg[2]; currentPitchRandomScale[voice] = scaleType; voices[voice].set(\pitch_random_scale_buf, pitchScaleBuffers[scaleType].bufnum, \pitch_random_scale_len, pitchScaleLengths[scaleType]); });
        this.addCommand("pitch_random_prob", "if", { arg msg; var voice = msg[1] - 1; currentPitchRandomProb[voice] = msg[2]; voices[voice].set(\pitch_random_prob, msg[2].abs * 0.01); voices[voice].set(\pitch_random_direction, msg[2].sign); });
        this.addCommand("pitch_walk_rate", "if", { arg msg; var voice = msg[1] - 1; currentPitchWalkRate[voice] = msg[2]; voices[voice].set(\pitch_walk_rate, msg[2]); });
        this.addCommand("pitch_walk_step", "if", { arg msg; var voice = msg[1] - 1; currentPitchWalkStep[voice] = msg[2]; voices[voice].set(\pitch_walk_step, msg[2]); });
        this.addCommand("ratcheting_prob", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\ratcheting_prob, msg[2] * 0.01); });
        this.addCommand("max_ratchets", "ii", { arg msg; var voice = msg[1] - 1; voices[voice].set(\max_ratchets, msg[2]); });

        this.addCommand("bitcrush_mix", "f", { arg msg; bitcrushEffect.set(\mix, msg[1]); bitcrushEffect.run(msg[1] > 0); });
        this.addCommand("bitcrush_rate", "f", { arg msg; bitcrushEffect.set(\rate, msg[1]); });
        this.addCommand("bitcrush_bits", "f", { arg msg; bitcrushEffect.set(\bits, msg[1]); });
        
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
        this.addCommand("sine_drive_wet", "f", { arg msg; sineEffect.set(\sine_drive_wet, msg[1]); sineEffect.run(msg[1] > 0); });
        this.addCommand("drive", "f", { arg msg; saturationEffect.set(\drive, msg[1]); saturationEffect.run(msg[1] > 0); });

        this.addCommand("glitch_mix", "f", { arg msg; glitchEffect.set(\mix, msg[1]); glitchEffect.run(msg[1] > 0); });
        this.addCommand("glitch_probability", "f", { arg msg; glitchEffect.set(\probability, msg[1]); });
        this.addCommand("glitch_ratio", "f", { arg msg; glitchEffect.set(\glitchRatio, msg[1]); });
        this.addCommand("glitch_min_length", "f", { arg msg; glitchEffect.set(\minLength, msg[1]); });
        this.addCommand("glitch_max_length", "f", { arg msg; glitchEffect.set(\maxLength, msg[1]); });
        this.addCommand("glitch_reverse", "f", { arg msg; glitchEffect.set(\reverse, msg[1]); });
        this.addCommand("glitch_pitch", "f", { arg msg; glitchEffect.set(\pitch, msg[1]); });

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
        this.addCommand("eq_mid_gain", "if", { arg msg; var voice = msg[1] - 1; currentMidGain[voice] = msg[2]; voices[voice].set(\mid_gain, msg[2]); });
        this.addCommand("eq_high_gain", "if", { arg msg; var voice = msg[1] - 1; currentHighGain[voice] = msg[2]; voices[voice].set(\high_gain, msg[2]); });

        this.addCommand("width", "f", { arg msg; widthEffect.set(\width, msg[1]); widthEffect.run(msg[1] != 1); });
        this.addCommand("dimension_mix", "f", { arg msg; dimensionEffect.set(\mix, msg[1]); dimensionEffect.run(msg[1] > 0); });
        this.addCommand("monobass_mix", "f", { arg msg; monobassEffect.set(\mix, msg[1]); monobassEffect.run(msg[1] > 0); });
        this.addCommand("rspeed", "f", { arg msg; rotateEffect.set(\rspeed, msg[1]); rotateEffect.run(msg[1] > 0); });
        this.addCommand("haas", "i", { arg msg; haasEffect.set(\haas, msg[1]); haasEffect.run(msg[1] > 0); });
        this.addCommand("pitch_lag", "if", { arg msg; var voice = msg[1] - 1; currentPitchLag[voice] = msg[2]; voices[voice].set(\pitch_lag_time, msg[2]); });

        this.addCommand("set_live_input", "ii", { arg msg; var voice = msg[1] - 1; var enable = msg[2]; if (enable == 1, { if (liveInputRecorders[voice].notNil, { liveInputRecorders[voice].free; }); liveInputRecorders[voice] = Synth.new(\liveInputRecorder, [ \bufL, liveInputBuffersL[voice], \bufR, liveInputBuffersR[voice], \mix, liveBufferMix, \voice, voice ], context.xg, 'addToHead'); voices[voice].set( \buf_l, liveInputBuffersL[voice], \buf_r, liveInputBuffersR[voice], \t_reset_pos, 1); }, { if (liveInputRecorders[voice].notNil, { liveInputRecorders[voice].free; }); liveInputRecorders[voice] = nil; }); });
        this.addCommand("live_buffer_mix", "f", { arg msg; liveBufferMix = msg[1]; liveInputRecorders.do({ arg recorder; if (recorder.notNil, {recorder.set(\mix, liveBufferMix);}); }); });
        this.addCommand("live_direct", "ii", { arg msg; var voice = msg[1] - 1; var enable = msg[2]; var currentParams, scaleType; if (enable == 1, { if (voices[voice].notNil, { voices[voice].free; }); if (liveInputRecorders[voice].notNil, { liveInputRecorders[voice].free; }); voices[voice] = Synth.new(\liveDirect, [ \out, mixBus.index,\pan, currentPan[voice] ? 0,\spread, currentSpread[voice] ? 0,\gain, currentVolume[voice] ? 1,\cutoff, currentCutoff[voice] ? 20000,\lpfgain, currentlpfgain[voice] ? 0.1,\hpf, currentHpf[voice] ? 20,\low_gain, currentLowGain[voice] ? 0,\mid_gain, currentMidGain[voice] ? 0,\high_gain, currentHighGain[voice] ? 0 ], target: pg); }, { if (voices[voice].notNil, { voices[voice].free; }); scaleType = currentPitchRandomScale[voice] ? 0; currentParams = Dictionary.newFrom([\speed, currentSpeed[voice] ? 0.1,\jitter, currentJitter[voice] ? 0.25,\size, currentSize[voice] ? 0.1,\density, currentDensity[voice] ? 10,\pitch_offset, currentPitch[voice] ? 1,\pan, currentPan[voice] ? 0,\spread, currentSpread[voice] ? 0,\gain, currentVolume[voice] ? 1,\granular_gain, currentGranularGain[voice] ? 1,\cutoff, currentCutoff[voice] ? 20000,\lpfgain, currentlpfgain[voice] ? 0.1,\hpf, currentHpf[voice] ? 20,\subharmonics_1, currentSubharmonics1[voice] ? 0,\subharmonics_2, currentSubharmonics2[voice] ? 0,\subharmonics_3, currentSubharmonics3[voice] ? 0,\overtones_1, currentOvertones1[voice] ? 0,\overtones_2, currentOvertones2[voice] ? 0,\pitch_mode, currentPitchMode[voice] ? 0,\trig_mode, currentTrigMode[voice] ? 0,\direction_mod, currentDirectionMod[voice] ? 0,\size_variation, currentSizeVariation[voice] ? 0,\smoothbass, currentSmoothbass[voice] ? 1,\low_gain, currentLowGain[voice] ? 0,\mid_gain, currentMidGain[voice] ? 0,\high_gain, currentHighGain[voice] ? 0,\probability, currentProbability[voice] ? 100, \pitch_lag, currentPitchLag[voice] ? 0,\density_mod_amt, currentDensityModAmt[voice] ? 0,\pitch_walk_rate, currentPitchWalkRate[voice] ? 2,\pitch_walk_step, currentPitchWalkStep[voice] ? 2,\pitch_random_prob, currentPitchRandomProb[voice] ? 0,\pitch_random_scale_buf, pitchScaleBuffers[scaleType].bufnum,\pitch_random_scale_len, pitchScaleLengths[scaleType],\ratcheting_prob, currentRatchetingProb[voice] ? 0]); voices[voice] = Synth.new(\synth1, [ \out, mixBus.index, \buf_l, buffersL[voice], \buf_r, buffersR[voice], \voice, voice ] ++ currentParams.getPairs, target: pg); voices[voice].set(\t_reset_pos, 1); }); });
        this.addCommand("isMono", "ii", { arg msg; var voice = msg[1] - 1; voices[voice].set(\isMono, msg[2]); });
        this.addCommand("live_mono", "ii", { arg msg; var voice = msg[1] - 1; var mono = msg[2]; if(liveInputRecorders[voice].notNil, {liveInputRecorders[voice].set(\isMono, mono); }); });
        this.addCommand("unload_all", "", {this.unloadAll(); });
        this.addCommand("save_live_buffer", "is", { arg msg; var voice = msg[1] - 1; var filename = msg[2]; var bufL = liveInputBuffersL[voice]; var bufR = liveInputBuffersR[voice]; this.saveLiveBufferToTape(voice, filename); });
        this.addCommand("live_buffer_length", "f", { arg msg; var length = msg[1]; liveInputBuffersL.do({ arg buf; buf.free; }); liveInputBuffersR.do({ arg buf; buf.free; }); liveInputBuffersL = Array.fill(2, {Buffer.alloc(context.server, context.server.sampleRate * length);}); liveInputBuffersR = Array.fill(2, {Buffer.alloc(context.server, context.server.sampleRate * length);}); liveInputRecorders.do({ arg recorder, i; if (recorder.notNil, {recorder.free; liveInputRecorders[i] = Synth.new(\liveInputRecorder, [ \bufL, liveInputBuffersL[i], \bufR, liveInputBuffersR[i], \mix, liveBufferMix, \voice, i], context.xg, 'addToHead'); voices[i].set( \buf_l, liveInputBuffersL[i], \buf_r, liveInputBuffersR[i], \t_reset_pos, 1); }); }); });
        this.addCommand("set_output_buffer_length", "f", { arg msg; var newLength = msg[1]; outputBufferLength = newLength; if (outputRecorder.notNil) { outputRecorder.free; }; if (outputRecordBuffer.notNil) {outputRecordBuffer.free; }; outputRecordBuffer = Buffer.alloc(context.server, context.server.sampleRate * outputBufferLength, 2); outputRecorder = Synth.new(\outputRecorder, [\buf, outputRecordBuffer, \inBus, postFxBus.index], context.xg, 'addToTail'); });
        this.addCommand("save_output_buffer", "s", { arg msg; var filename, path, interleaved, gainBoost = 2.8, crossfadeSamples, actualLength, splitPoint, finalLength, writePos; filename = msg[1]; path = "/home/we/dust/audio/tape/" ++ filename; crossfadeSamples = context.server.sampleRate.asInteger; actualLength = outputRecordBuffer.numFrames; writePos = (currentOutputWritePos ? 0.5) * actualLength; splitPoint = writePos.asInteger;  finalLength = actualLength - crossfadeSamples; interleaved = Buffer.alloc(context.server, finalLength, 2); outputRecordBuffer.loadToFloatArray(action: { |stereoData| var interleavedData = FloatArray.newClear(finalLength * 2), idx = 0, piInv = pi.reciprocal, crossfadeInv = crossfadeSamples.reciprocal; finalLength.do { |sampleIdx| var blendL, blendR; if (sampleIdx < crossfadeSamples) {var crossfadePos = sampleIdx * crossfadeInv, fadeInGain = (1 - cos(crossfadePos * pi)) * 0.5, fadeOutGain = (1 + cos(crossfadePos * pi)) * 0.5, splitIdx = (splitPoint + sampleIdx) % actualLength, beforeIdx = (splitPoint - crossfadeSamples + sampleIdx) % actualLength; blendL = (stereoData[splitIdx * 2] * fadeInGain) + (stereoData[beforeIdx * 2] * fadeOutGain); blendR = (stereoData[splitIdx * 2 + 1] * fadeInGain) + (stereoData[beforeIdx * 2 + 1] * fadeOutGain);} {var sourceIdx = (splitPoint + sampleIdx) % actualLength; blendL = stereoData[sourceIdx * 2]; blendR = stereoData[sourceIdx * 2 + 1];}; interleavedData[idx] = blendL * gainBoost; interleavedData[idx + 1] = blendR * gainBoost; idx = idx + 2; }; interleaved.loadCollection(interleavedData, action: { interleaved.write(path, "WAV", "float"); NetAddr("127.0.0.1", 10111).sendMsg("/twins/output_saved", path); NetAddr("127.0.0.1", 10111).sendMsg("/twins/save_complete"); interleaved.free; }); }); });
        this.addCommand("save_output_buffer_only", "s", { arg msg; var filename, path, interleaved, gainBoost = 2.8, crossfadeSamples, actualLength, splitPoint, finalLength, writePos; filename = msg[1]; path = "/home/we/dust/audio/tape/" ++ filename; crossfadeSamples = context.server.sampleRate.asInteger; actualLength = outputRecordBuffer.numFrames; writePos = (currentOutputWritePos ? 0.5) * actualLength; splitPoint = writePos.asInteger; finalLength = actualLength - crossfadeSamples; interleaved = Buffer.alloc(context.server, finalLength, 2); outputRecordBuffer.loadToFloatArray(action: { |stereoData| var interleavedData = FloatArray.newClear(finalLength * 2), idx = 0, crossfadeInv = crossfadeSamples.reciprocal; finalLength.do { |sampleIdx| var blendL, blendR; if (sampleIdx < crossfadeSamples) {var crossfadePos = sampleIdx * crossfadeInv, fadeInGain = (1 - cos(crossfadePos * pi)) * 0.5, fadeOutGain = (1 + cos(crossfadePos * pi)) * 0.5, splitIdx = (splitPoint + sampleIdx) % actualLength, beforeIdx = (splitPoint - crossfadeSamples + sampleIdx) % actualLength; blendL = (stereoData[splitIdx * 2] * fadeInGain) + (stereoData[beforeIdx * 2] * fadeOutGain); blendR = (stereoData[splitIdx * 2 + 1] * fadeInGain) + (stereoData[beforeIdx * 2 + 1] * fadeOutGain);} {var sourceIdx = (splitPoint + sampleIdx) % actualLength; blendL = stereoData[sourceIdx * 2]; blendR = stereoData[sourceIdx * 2 + 1]; }; interleavedData[idx] = blendL * gainBoost; interleavedData[idx + 1] = blendR * gainBoost; idx = idx + 2; }; interleaved.loadCollection(interleavedData, action: { interleaved.write(path, "WAV", "float"); NetAddr("127.0.0.1", 10111).sendMsg("/twins/save_complete"); interleaved.free; }); }); });

        o = OSCFunc({ |msg| var voice, pos; voice = msg[3].asInteger; pos = msg[4]; NetAddr("127.0.0.1", 10111).sendMsg("/twins/buf_pos", voice, pos); }, '/buf_pos', context.server.addr);
        o_rec = OSCFunc({ |msg| var voice, pos; voice = msg[3].asInteger; pos = msg[4]; NetAddr("127.0.0.1", 10111).sendMsg("/twins/rec_pos", voice, pos); }, '/rec_pos', context.server.addr);
        o_grain = OSCFunc({ |msg| var voice, pos, size; voice = msg[3].asInteger; pos = msg[4]; size = msg[5]; NetAddr("127.0.0.1", 10111).sendMsg("/twins/grain_pos", voice, pos, size);}, '/grain_pos', context.server.addr);
        o_output = OSCFunc({ |msg| var pos; pos = msg[3]; currentOutputWritePos = pos;}, '/output_write_pos', context.server.addr);
        o_voice_peak = OSCFunc({ |msg| var voice, peakL, peakR; voice = msg[3].asInteger; peakL = msg[4]; peakR = msg[5]; NetAddr("127.0.0.1", 10111).sendMsg("/twins/voice_peak", voice, peakL, peakR); }, '/voice_peak', context.server.addr);
    }

free {
        voices.do({ arg voice; if (voice.notNil) { voice.free; }; });
        buffersL.do({ arg b; if (b.notNil) { b.free; }; });
        buffersR.do({ arg b; if (b.notNil) { b.free; }; });
        liveInputBuffersL.do({ arg b; if (b.notNil) { b.free; }; });
        liveInputBuffersR.do({ arg b; if (b.notNil) { b.free; }; });
        liveInputRecorders.do({ arg s; if (s.notNil) { s.free; }; });
        pitchScaleBuffers.do({ arg b; if (b.notNil) { b.free; }; });
        if (grainEnvs.notNil) { grainEnvs.do({ arg buf; if (buf.notNil) { buf.free; }; }); };
        if (outputRecorder.notNil) { outputRecorder.free; outputRecorder = nil; };
        if (outputRecordBuffer.notNil) { outputRecordBuffer.free; outputRecordBuffer = nil; };
        if (o.notNil) { o.free; o = nil; };
        if (o_rec.notNil) { o_rec.free; o_rec = nil; };
        if (o_grain.notNil) { o_grain.free; o_grain = nil; };
        if (o_output.notNil) { o_output.free; o_output = nil; };
        if (o_voice_peak.notNil) { o_voice_peak.free; o_voice_peak = nil; };
        if (wobbleBuffer.notNil) { wobbleBuffer.free; wobbleBuffer = nil; };
        if (mixBus.notNil) { mixBus.free; mixBus = nil; };
        if (postFxBus.notNil) { postFxBus.free; postFxBus = nil; };
        if (shimmerBus.notNil) { shimmerBus.free; shimmerBus = nil; };
        if (parallelBus.notNil) { parallelBus.free; parallelBus = nil; };
        if (bufSine.notNil) { bufSine.free; bufSine = nil; };
        if (bitcrushEffect.notNil) { bitcrushEffect.free; bitcrushEffect = nil; };
        if (shimmerEffect.notNil) { shimmerEffect.free; shimmerEffect = nil; };
        if (saturationEffect.notNil) { saturationEffect.free; saturationEffect = nil; };
        if (tapeEffect.notNil) { tapeEffect.free; tapeEffect = nil; };
        if (chewEffect.notNil) { chewEffect.free; chewEffect = nil; };
        if (widthEffect.notNil) { widthEffect.free; widthEffect = nil; };
        if (monobassEffect.notNil) { monobassEffect.free; monobassEffect = nil; };
        if (lossdegradeEffect.notNil) { lossdegradeEffect.free; lossdegradeEffect = nil; };
        if (sineEffect.notNil) { sineEffect.free; sineEffect = nil; };
        if (wobbleEffect.notNil) { wobbleEffect.free; wobbleEffect = nil; };
        if (glitchEffect.notNil) { glitchEffect.free; glitchEffect = nil; };
        if (delayEffect.notNil) { delayEffect.free; delayEffect = nil; };
        if (reverbEffect.notNil) { reverbEffect.free; reverbEffect = nil; };
        if (rotateEffect.notNil) { rotateEffect.free; rotateEffect = nil; };
        if (haasEffect.notNil) { haasEffect.free; haasEffect = nil; };
        if (dimensionEffect.notNil) { dimensionEffect.free; dimensionEffect = nil; };
        if (mixToParallelRouter.notNil) { mixToParallelRouter.free; mixToParallelRouter = nil; };
        if (parallelToPostFxRouter.notNil) { parallelToPostFxRouter.free; parallelToPostFxRouter = nil; };
        if (finalOutputRouter.notNil) { finalOutputRouter.free; finalOutputRouter = nil; };
    }
}