Engine_twins : CroneEngine {

var dimensionEffect, haasEffect, bitcrushEffect, saturationEffect, delayEffect, reverbEffect, shimmerEffect, tapeEffect, chewEffect, widthEffect, monobassEffect, sineEffect, wobbleEffect, lossdegradeEffect, rotateEffect, glitchEffect;
var <silentBuffer, <buffersL, <buffersR, wobbleBuffer, glitchBuffer, mixBus, postFxBus, shimmerBus, parallelBus, <voices, bufSine, pg, <liveInputBuffersL, <liveInputBuffersR, <liveInputRecorders, <liveRecPosBuses, o, o_rec, o_grain, o_voice_peak, mixToParallelRouter, parallelToPostFxRouter, finalOutputRouter;
var liveBufferAllocGeneration = 0, grainEnvs, pitchScaleBuffers, pitchScaleLengths, nornsAddr, voicesUsingLiveBuffer, eqChain;
var o_grain_r;
var currentSpeed, currentJitter, currentSize, currentDensity, currentDensityModAmt, currentPitch, currentPan, currentSpread, currentVolume, currentGranularGain, currentCutoff, currentHpf, currentlpf_gain, currentSubharmonics1, currentSubharmonics2, currentSubharmonics3, currentOvertones1, currentOvertones2, currentPitchMode, currentTrigMode, currentDirectionMod, currentSizeVariation, currentSmoothbass, currentLowGain, currentMidGain, currentHighGain, currentProbability, liveBufferMix = 1.0, currentPitchRandomProb, currentPitchRandomScale, currentRatchetingProb, currentPitchLag, currentGlitchRatio = 0.0, currentGlitchMix = 0.0, currentStereoTrigOffset, currentStereoIndependent;

classvar pitchScales; *initClass {pitchScales = [[7, 12], [7, 12, 19, 24], [12], [12, 24], [1,2,3,4,5,6,7,8,9,10,11], [2,4,5,7,9,11], [2,3,5,7,8,10], [2,4,7,9], [2,4,6,8,10]];}

*new { arg context, doneCallback; ^super.new(context, doneCallback); }

readBuf { arg i, path; if(buffersL[i].notNil && buffersR[i].notNil, { if (File.exists(path), { var numChannels; numChannels = SoundFile.use(path.asString(), { |f| f.numChannels }); Buffer.readChannel(context.server, path, 0, -1, [0], {|b| var oldL = buffersL[i]; voices[i].set(\buf_l, b); buffersL[i] = b; oldL.free; if (numChannels <= 1, { var oldR = buffersR[i]; voices[i].set(\buf_r, b); buffersR[i] = b; if (oldR !== oldL) { oldR.free }; voices[i].run(true); }, { Buffer.readChannel(context.server, path, 0, -1, [1], { |b| var oldR = buffersR[i]; voices[i].set(\buf_r, b); buffersR[i] = b; oldR.free; voices[i].run(true); }); }); }); }); }); }

unloadAll { fork { 2.do({ arg i; if(voices[i].notNil, { voices[i].set(\buf_l, silentBuffer, \buf_r, silentBuffer, \t_reset_pos, 1); voices[i].run(false); }); voicesUsingLiveBuffer[i] = false; liveInputBuffersL[i].zero; liveInputBuffersR[i].zero; if(liveInputRecorders[i].notNil, { liveInputRecorders[i].free; liveInputRecorders[i] = nil; }); }); wobbleBuffer.zero; glitchBuffer.zero; }; }

saveLiveBufferToTape { arg voice, filename; var path = "/home/we/dust/audio/tape/" ++ filename; var bufL = liveInputBuffersL[voice]; var bufR = liveInputBuffersR[voice]; var interleaved = Buffer.alloc(context.server, bufL.numFrames, 2); bufL.loadToFloatArray(action: { |leftData| bufR.loadToFloatArray(action: { |rightData| var interleavedData = FloatArray.newClear(leftData.size * 2); leftData.size.do { |i| interleavedData[i * 2] = leftData[i]; interleavedData[i * 2 + 1] = rightData[i]; }; interleaved.loadCollection(interleavedData, action: { interleaved.write(path, "WAV", "float"); this.readBuf(voice, path); interleaved.free; }); }); }); }

alloc {
        nornsAddr = NetAddr("127.0.0.1", 10111);
        buffersL = Array.fill(2, { arg i; Buffer.alloc(context.server, context.server.sampleRate * 1); });
        buffersR = Array.fill(2, { arg i; Buffer.alloc(context.server, context.server.sampleRate * 1); });

        liveInputBuffersL = Array.fill(2, {Buffer.alloc(context.server, context.server.sampleRate * 8); });
        liveInputBuffersR = Array.fill(2, {Buffer.alloc(context.server, context.server.sampleRate * 8); });
        liveInputRecorders = Array.fill(2, { nil });
        voicesUsingLiveBuffer = Array.fill(2, { false });
        liveRecPosBuses = Array.fill(2, { Bus.control(context.server, 1) });
        liveRecPosBuses.do({ |b| b.set(-1.0); });

        bufSine = Buffer.alloc(context.server, 1024 * 16, 1); bufSine.sine2([2], [0.5], false);
        wobbleBuffer = Buffer.alloc(context.server, context.server.sampleRate * 5, 2);
        glitchBuffer = Buffer.alloc(context.server, context.server.sampleRate * 1, 2);
        silentBuffer = Buffer.alloc(context.server, context.server.sampleRate.asInteger);
        mixBus = Bus.audio(context.server, 2);
        postFxBus = Bus.audio(context.server, 2);
        shimmerBus = Bus.audio(context.server, 2);
        parallelBus = Bus.audio(context.server, 2);

        grainEnvs = [Env.new([0, 1, 1, 0], [0.15, 0.7, 0.15], [4, 0, -4]), Env.perc(0.01, 0.99, 1, -4), Env.perc(0.99, 0.01, 1, 4), Env.adsr(0.25, 0.15, 0.65, 1, 1, -4, 0)].collect { |env| Buffer.sendCollection(context.server, env.discretize) };
        
        pitchScaleBuffers = pitchScales.collect { |scale| Buffer.sendCollection(context.server, scale, 1) };
        pitchScaleLengths = pitchScales.collect(_.size);

        currentSpeed = [0.1, 0.1]; currentJitter = [0.25, 0.25]; currentSize = [0.1, 0.1]; currentDensity = [10, 10]; currentPitch = [1, 1]; currentPan = [0, 0]; currentSpread = [0, 0]; currentVolume = [1, 1]; currentGranularGain = [1, 1]; currentCutoff = [20000, 20000]; currentlpf_gain = [0.95, 0.95]; currentHpf = [20, 20]; currentSubharmonics1 = [0, 0]; currentSubharmonics2 = [0, 0]; currentSubharmonics3 = [0, 0]; currentOvertones1 = [0, 0]; currentOvertones2 = [0, 0]; currentPitchMode = [0, 0]; currentTrigMode = [0, 0]; currentDirectionMod = [0, 0]; currentSizeVariation = [0, 0]; currentSmoothbass = [1, 1]; currentDensityModAmt = [0, 0]; currentLowGain = [0, 0]; currentMidGain = [0, 0]; currentHighGain = [0, 0]; currentProbability = [100, 100]; liveBufferMix = 1.0; currentPitchRandomProb = [0, 0]; currentPitchRandomScale = [0, 0]; currentRatchetingProb = [0, 0]; currentPitchLag = [0, 0]; currentStereoTrigOffset = [0, 0]; currentStereoIndependent = [0, 0];

        eqChain = { arg sig, low_gain, mid_gain, high_gain, hpf, cutoff, lpf_gain;
            var lagcutoff = Lag.kr(cutoff, 0.6);
            sig = BLowShelf.ar(sig, 55, 6, low_gain);
            sig = BPeakEQ.ar(sig, 700, 1, mid_gain);
            sig = BHiShelf.ar(sig, 3900, 6, high_gain);
            sig = HPF.ar(sig, hpf);
            sig = MoogFF.ar(sig, lagcutoff, lpf_gain);
            sig
        };

        context.server.sync;

        SynthDef(\synth1, {
            arg out, voice, buf_l, buf_r, pos, speed, jitter, size, density, density_mod_amt, pitch_offset, pan, spread, gain, t_reset_pos, granular_gain, pitch_mode, trig_mode, subharmonics_1, subharmonics_2, subharmonics_3, overtones_1, overtones_2, cutoff, hpf, hpfq, lpf_gain, direction_mod, size_variation, low_gain, mid_gain, high_gain, smoothbass, probability, env_select = 0, pitch_random_prob=0, pitch_random_scale_buf=0, pitch_random_scale_len=1, pitch_random_direction=1, ratcheting_prob=0, pitch_lag_time, rec_pos_bus = -1, stereo_trig_offset = 0, stereo_independent = 0;
            var grain_trig, grain_trig_r, jitter_sig, pan_sig, buf_pos, sig_mix, density_mod, density_mod_r, dry_sig, granular_sig, base_pitch, grain_pitch, grain_size;
            var main_vol = 1 / (1 + subharmonics_1 + subharmonics_2 + subharmonics_3 + overtones_1 + overtones_2);
            var subharmonic_1_vol = subharmonics_1 * main_vol * 2;
            var subharmonic_2_vol = subharmonics_2 * main_vol * 2;
            var subharmonic_3_vol = subharmonics_3 * main_vol * 2;
            var overtone_1_vol = overtones_1 * main_vol * 1.5;
            var overtone_2_vol = overtones_2 * main_vol * 1.5;
            var trigger60 = Impulse.kr(60);
            var grain_direction, base_trig, base_grain_trig, rand_val, rand_val2, rand_val_r, random_interval, ratchet_gate, extra_trig, signal, stepIndex, actualStep, direction, totalStep, scaleDegree, octaveShift, semitones, grain_pan, envBuf, randomEnv, harmonics, volumes, l_harmonics, r_harmonics, vol, size_mults, density_mod_recip, jitter_range, buf_frames_l, buf_frames_r, buf_dur_recip, wrapped_grain_pos;

            speed = Lag.kr(speed, 1);
            density_mod = density * (2**(LFNoise1.kr(density).range(0, 1) * density_mod_amt));
            density_mod_r = density * (2**(LFNoise1.kr(density).range(0, 1) * density_mod_amt));
            density_mod_recip = density_mod.reciprocal;
            base_trig = Select.kr(trig_mode, [Impulse.kr(density_mod), Dust.kr(density_mod)]);
            ratchet_gate = CoinGate.kr(ratcheting_prob, base_trig);
            extra_trig = TDelay.kr(ratchet_gate, density_mod_recip * 0.5, 2.0);
            base_grain_trig = base_trig + extra_trig;
            grain_trig = CoinGate.kr(probability, base_grain_trig);
            grain_trig_r = Select.kr((stereo_trig_offset > 0) * (stereo_trig_offset < 1), [grain_trig, TDelay.kr(grain_trig, density_mod_recip * stereo_trig_offset)]);
            grain_trig_r = Select.kr(stereo_independent, [grain_trig_r, CoinGate.kr(probability, Select.kr(trig_mode, [Impulse.kr(density_mod_r, stereo_trig_offset), Dust.kr(density_mod_r)]))]);
            rand_val = TRand.kr(trig: grain_trig, lo: 0, hi: 1);
            rand_val2 = TRand.kr(trig: grain_trig, lo: 0, hi: 1);
            rand_val_r = TRand.kr(trig: grain_trig_r, lo: 0, hi: 1);
            grain_size = size * (1 + TRand.kr(trig: grain_trig, lo: size_variation.neg, hi: size_variation));
            grain_direction = Select.kr(pitch_mode, [1, Select.kr(speed.abs > 0.001, [1, speed.sign])]) * Select.kr((rand_val < direction_mod), [1, -1]);
            buf_frames_l = BufFrames.kr(buf_l);
            buf_frames_r = BufFrames.kr(buf_r);
            buf_dur_recip = SampleRate.ir / buf_frames_l;
            jitter_range = buf_dur_recip * jitter;
            jitter_sig = TRand.kr(trig: grain_trig, lo: jitter_range.neg, hi: jitter_range);
            buf_pos = Phasor.kr(trig: t_reset_pos, rate: buf_dur_recip / ControlRate.ir * speed, start: 0, end: 1, resetPos: pos);
            dry_sig = [PlayBuf.ar(1, buf_l, speed, startPos: pos * buf_frames_l, trigger: t_reset_pos, loop: 1), PlayBuf.ar(1, buf_r, speed, startPos: pos * buf_frames_r, trigger: t_reset_pos, loop: 1)];

            {
                var recPos = In.kr(rec_pos_bus);
                var diff = (buf_pos - recPos.max(0)).abs;
                var wrappedDist = diff.min(1.0 - diff);
                var fadeZoneNorm = (0.03 * SampleRate.ir) / buf_frames_l;
                var liveDryFade = (wrappedDist / fadeZoneNorm).clip(0, 1);
                var dryFade = Select.kr((recPos >= 0), [1.0, liveDryFade]);
                dry_sig = dry_sig * dryFade;
            }.value;

            base_pitch = Select.kr(pitch_mode, [speed * pitch_offset, pitch_offset]);
            grain_pitch = Lag.kr(base_pitch, pitch_lag_time);
            random_interval = BufRd.kr(1, pitch_random_scale_buf, TIRand.kr(0, pitch_random_scale_len - 1, grain_trig));
            grain_pitch = grain_pitch * (((rand_val2 < pitch_random_prob) * random_interval * pitch_random_direction).midiratio);
            grain_pan = (pan + TRand.kr(trig: grain_trig, lo: spread.neg, hi: spread));
            randomEnv = TIRand.kr(0, 3, grain_trig);
            envBuf = Select.kr(env_select, [-1] ++ grainEnvs ++ [Select.kr(randomEnv, grainEnvs)]);
            harmonics = [1, 1/2, 1/4, 1/8, 2, 4];
            volumes = [main_vol, subharmonic_1_vol, subharmonic_2_vol, subharmonic_3_vol, overtone_1_vol, overtone_2_vol];
            size_mults = [1, smoothbass, smoothbass, smoothbass, 1, 1];
            l_harmonics = harmonics.collect { |harmonic, i| var active_trig = grain_trig * (volumes[i] > 0); GrainBuf.ar(numChannels: 2, trigger: active_trig, dur: grain_size * size_mults[i], sndbuf: buf_l, rate: grain_pitch * harmonic * grain_direction, pos: buf_pos + jitter_sig, interp: 4, pan: grain_pan, envbufnum: envBuf, mul: volumes[i]); };
            r_harmonics = harmonics.collect { |harmonic, i| var active_trig = grain_trig_r * (volumes[i] > 0); GrainBuf.ar(numChannels: 2, trigger: active_trig, dur: grain_size * size_mults[i], sndbuf: buf_r, rate: grain_pitch * harmonic * grain_direction, pos: buf_pos + jitter_sig, interp: 4, pan: grain_pan, envbufnum: envBuf, mul: volumes[i]); };
            granular_sig = Mix.ar(l_harmonics) + Mix.ar(r_harmonics);
            sig_mix = dry_sig * (1 - granular_gain) + (granular_sig * granular_gain);
            sig_mix = eqChain.(sig_mix, low_gain, mid_gain, high_gain, hpf, cutoff, lpf_gain);
            sig_mix = Balance2.ar(sig_mix[0], sig_mix[1], pan);
            signal = sig_mix * Lag.kr(gain);

            wrapped_grain_pos = Wrap.kr(buf_pos + jitter_sig);
            SendReply.kr(trigger60, '/buf_pos', [voice, buf_pos]);
            SendReply.kr(grain_trig, '/grain_pos', [voice, wrapped_grain_pos, grain_size, rand_val]);
            SendReply.kr(grain_trig_r, '/grain_pos_r', [voice, wrapped_grain_pos, grain_size, rand_val_r]);
            SendReply.kr(trigger60, '/voice_peak', [voice, Peak.kr(signal[0], trigger60), Peak.kr(signal[1], trigger60)]);
            Out.ar(out, signal * 1.2);
        }).add;

        context.server.sync;

        pg = ParGroup.head(context.xg);
        voices = Array.fill(2, { arg i;
            Synth(\synth1, [
                \out, mixBus.index, 
                \buf_l, buffersL[i],
                \buf_r, buffersR[i],
                \voice, i,
            ], target: pg);
        });
        
        context.server.sync;

        SynthDef(\liveDirect, {
            arg out, pan, gain, cutoff, hpf, low_gain, mid_gain, high_gain, isMono, lpf_gain, voice;
            var sig = SoundIn.ar([0, 1]);
            var trigger60 = Impulse.kr(60);
            var lagcutoff = Lag.kr(cutoff, 0.6);
            sig = Select.ar(isMono, [sig, [sig[0], sig[0]] ]);
            sig = eqChain.(sig, low_gain, mid_gain, high_gain, hpf, cutoff, lpf_gain);
            sig = Balance2.ar(sig[0], sig[1], pan);
            sig = sig * Lag.kr(gain);
            SendReply.kr(trigger60, '/voice_peak', [voice, Peak.kr(sig[0], trigger60), Peak.kr(sig[1], trigger60)]);
            Out.ar(out, sig * 1.2);
        }).add;
        
        SynthDef(\liveInputRecorder, {
            arg bufL, bufR, isMono=0, mix, voice, recPosBus;
            var in = SoundIn.ar([0, 1]);
            var phasor = Phasor.ar(0, 1, 0, BufFrames.kr(bufL));
            var oldL = BufRd.ar(1, bufL, phasor);
            var oldR = BufRd.ar(1, bufR, phasor);
            var mixedL, mixedR, normPos;
            in = Select.ar(isMono, [in, [Mix.ar(in), Mix.ar(in)]]);
            mixedL = XFade2.ar(oldL, in[0], mix * 2 - 1);
            mixedR = XFade2.ar(oldR, in[1], mix * 2 - 1);
            BufWr.ar(mixedL, bufL, phasor);
            BufWr.ar(mixedR, bufR, phasor);
            normPos = phasor / BufFrames.kr(bufL);
            Out.kr(recPosBus, A2K.kr(normPos));
            SendReply.kr(Impulse.kr(30), '/rec_pos', [voice, normPos]);
        }).add;

        SynthDef(\delay, {
            arg inBus, outBus, mix=0.0, delay=0.5, fb_amt=0.3, dhpf=20, lpf=20000, w_rate=0.0, w_depth=0.0, stereo=0.2;
            var input, local, fb, delayed, wet, combinedMod, lfo2Rate, lfo3Rate;
            var baseLFO, drift, wobble, steps;
            lfo2Rate = w_rate * (1 + LFNoise1.kr(0.13, 0.18));
            lfo3Rate = w_rate * 0.71;
            baseLFO = SinOsc.kr(w_rate * [0.6, 0.63]).sum * 0.5;
            drift = LFNoise2.kr(w_rate * 0.15) * 0.35;
            wobble = SinOsc.kr(lfo2Rate + (drift * 0.6)) * LFNoise2.kr(lfo3Rate * 0.25).range(0.5, 1.2) * 0.25;
            steps = Latch.kr(LFNoise0.kr(w_rate * 6.3), Dust.kr(w_rate * 4.7)) * 0.08;
            combinedMod = w_depth * Mix([baseLFO * 0.4, drift, wobble, steps]);
            input = In.ar(inBus, 2);
            local = LocalIn.ar(2);
            fb = LPF.ar(HPF.ar(local, dhpf), lpf);
            fb = (1.35 * (1 - (stereo * 0.35)) * fb_amt * [fb[1], fb[0]]).softclip;
            delayed = DelayC.ar(input + fb, 2, Lag.kr(delay, 0.7) + combinedMod);
            wet = Balance2.ar(delayed[0], delayed[1], (SinOsc.kr(delay.max(0.1).reciprocal * 0.5) + (LFNoise2.kr(0.4) * 0.3)) * (stereo / 1.3));
            LocalOut.ar(wet);
            Out.ar(outBus, wet * mix * 1.6);
        }).add;
        
        SynthDef(\reverb, {
            arg inBus1, inBus2, outBus, mix=0.0, t60, damp, rsize, earlyDiff, modDepth, modFreq, low, mid, high, lowcut, highcut, shimmer_mix=0.0, shimmer_lowpass=8000, shimmer_fb=0.38, shimmer_hipass=600, shimmer_oct=2;
            var combined, reverb_input, reverb_output, pitch_shifted, pitch_feedback, reverb_feedback, limited_feedback;
            combined = In.ar(inBus1, 2) + In.ar(inBus2, 2);
            reverb_feedback = LocalIn.ar(2);
            limited_feedback = Limiter.ar(reverb_feedback, 0.9, 0.01);
            pitch_shifted = PitchShift.ar(limited_feedback, 0.1, shimmer_oct, 0.01, 0.005, mul:5);
            pitch_shifted = LPF.ar(pitch_shifted, shimmer_lowpass);
            pitch_shifted = HPF.ar(pitch_shifted, shimmer_hipass);
            pitch_feedback = pitch_shifted * shimmer_fb.clip(0, 0.95);
            reverb_input = combined + (pitch_feedback * shimmer_mix);
            reverb_output = JPverb.ar(reverb_input, t60, damp, rsize, earlyDiff, modDepth, modFreq, low, mid, high, lowcut, highcut);
            LocalOut.ar(reverb_output);
            Out.ar(outBus, reverb_output * mix * 1.2);
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
            sig = BHiPass.ar(sig, 190)+Pan2.ar(BLowPass.ar(sig[0] + sig[1], 190));
            ReplaceOut.ar(bus, sig);
        }).add;  
        
        SynthDef(\bitcrush, {
            arg bus, mix=0.0, rate, bits;
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
            var wet, depth = 0.2, rate = 0.6, predelay = 0.025, voice1, voice2, voice3, voice4, mid, side, wide;
            var chorus = { |input, delayTime, rate, depth| var mod = SinOsc.kr(rate, [0, pi/2, pi, 3*pi/2]).range(-1, 1) * depth; var delays = delayTime + (mod * 0.02); DelayC.ar(input, 0.05, delays); };
            voice1 = chorus.(sig, predelay * 0.5, rate * 0.99, depth * 0.8);
            voice2 = chorus.(sig, predelay * 0.65, rate * 1.01, depth * 0.9);
            voice3 = chorus.(sig, predelay * 0.85, rate * 0.98, depth * 1.0);
            voice4 = chorus.(sig, predelay * 1.05, rate * 1.02, depth * 0.7);
            wet = [voice1[0] * 0.25 + voice2[0] * 0.25 + voice3[1] * 0.25 + voice4[1] * 0.25, voice1[1] * 0.25 + voice2[1] * 0.25 + voice3[0] * 0.25 + voice4[0] * 0.25];
            mid = (wet[0] + wet[1]);
            side = (wet[0] - wet[1]);
            wide = [mid + side, mid - side] * 4;
            ReplaceOut.ar(bus, XFade2.ar(sig, wide, mix * 2 - 1));
        }).add;
        
        SynthDef(\tape, {
            arg bus, mix=0.0;
            var orig = In.ar(bus, 2);
            var wet = AnalogTape.ar(orig, 1, 1, 1, 0, 0) * 0.89;
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

        SynthDef(\glitch, {
            arg bus, probability, glitch_ratio = 0.0, mix, minLength, maxLength, reverse, pitch, maxStutters;
            var sig, bufFrames, writePos, rawTrigOn, trigOn, earlyOff, trigOff, isGlitching, isGlitching_fb, capturePos, chunkLength, chunkStart, stutterCount, autoOff, pitchShift, isReverse, relPos, bufReadPos, wet_raw, wet, fadeSamples, startRamp, endRamp, loopEnv, sr;
            sig = In.ar(bus, 2);
            sr = SampleRate.ir;
            bufFrames = BufFrames.ir(glitchBuffer);
            fadeSamples = sr * 0.06;
            writePos = Phasor.ar(0, 1, 0, bufFrames);
            BufWr.ar(sig, glitchBuffer, writePos);
            isGlitching_fb = LocalIn.kr(1);
            rawTrigOn = Dust.kr(probability * glitch_ratio);
            trigOn = rawTrigOn * (1 - isGlitching_fb);
            capturePos = Latch.kr(writePos, trigOn);
            chunkLength = Demand.kr(trigOn, 0, Dwhite(minLength * sr, maxLength * sr));
            stutterCount = Demand.kr(trigOn, 0, Diwhite(2, maxStutters));
            isReverse = Demand.kr(trigOn, 0, Dwhite(0, 1)) < reverse;
            pitchShift = 1.0 + ((Demand.kr(trigOn, 0, Dwhite(0, 1)) < pitch) * (Select.kr(Demand.kr(trigOn, 0, Diwhite(0, 3)), [0.707, 0.841, 1.189, 1.414]) - 1.0));
            chunkStart = (capturePos - chunkLength).wrap(0, bufFrames - 1);
            autoOff = TDelay.kr(trigOn, stutterCount * (chunkLength / sr) / pitchShift);
            earlyOff = Dust.kr(probability * (1.0 - glitch_ratio).max(0.001)) * isGlitching_fb;
            trigOff = earlyOff + autoOff;
            isGlitching = SetResetFF.kr(trigOn, trigOff);
            LocalOut.kr(isGlitching);
            relPos = Phasor.ar(trigOn, pitchShift, 0, chunkLength, 0);
            bufReadPos = chunkStart + Select.ar(isReverse, [relPos, chunkLength - relPos]);
            wet_raw = BufRd.ar(2, glitchBuffer, bufReadPos, loop: 1, interpolation: 2);
            startRamp = (relPos / fadeSamples).clip(0, 1);
            endRamp = ((chunkLength - relPos) / fadeSamples).clip(0, 1);
            loopEnv = startRamp.min(endRamp);
            wet = wet_raw * 2 * loopEnv;
            ReplaceOut.ar(bus, LinXFade2.ar(sig, wet, (isGlitching * mix * 2) - 1));
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
            var loss = AnalogLoss.ar(sig, 0.5, 1, 0.5, 0.5);
            var depth=LFPar.kr(1/5,Rand(0, 2), 0.4, 0.5);
	          var amount=LFPar.kr(1/2,Rand(0, 2), 0.4, 0.5);
	          var variance=LFPar.kr(1/3,Rand(0, 2), 0.4, 0.5);
	          var envelope=LFPar.kr(1/4,Rand(0, 2), 0.4, 0.5);
            var degrade = AnalogDegrade.ar(loss, depth, amount, variance, envelope);
            ReplaceOut.ar(bus, XFade2.ar(sig, degrade, mix * 2 - 1));
        }).add;
        
        SynthDef(\saturation, {
            arg bus, drive=0.0;
            var dry = In.ar(bus, 2);
            var stage1 = ((1 + (drive * 0.4)) * dry).softclip;
            var stage2 = ((1 + (drive * 0.5)) * stage1).tanh;
            ReplaceOut.ar(bus, XFade2.ar(dry, stage2, drive * 2 - 1));
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
        glitchEffect = Synth.new(\glitch, [\bus, mixBus.index, \glitch_ratio, 0.0], context.xg, 'addToTail');
        tapeEffect = Synth.new(\tape, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');  
        wobbleEffect = Synth.new(\wobble, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');
        chewEffect = Synth.new(\chew, [\bus, mixBus.index, \chew_depth, 0.0], context.xg, 'addToTail');
        lossdegradeEffect = Synth.new(\lossdegrade, [\bus, mixBus.index, \mix, 0.0], context.xg, 'addToTail');
        saturationEffect = Synth.new(\saturation, [\bus, mixBus.index, \drive, 0.0], context.xg, 'addToTail');
        delayEffect = Synth.new(\delay, [\inBus, mixBus.index, \outBus, parallelBus.index, \mix, 0.0], context.xg, 'addToTail');
        shimmerEffect = Synth.new(\shimmer, [\inBus, mixBus.index, \outBus, parallelBus.index, \reverbBus, shimmerBus.index, \mix, 0.0], context.xg, 'addToTail');
        reverbEffect = Synth.new(\reverb, [\inBus1, mixBus.index, \inBus2, shimmerBus.index, \outBus, parallelBus.index, \mix, 0.0], context.xg, 'addToTail');
        mixToParallelRouter = Synth.new(\output, [\in, mixBus.index, \out, parallelBus.index], context.xg, 'addToTail');
        parallelToPostFxRouter = Synth.new(\output, [\in, parallelBus.index, \out, postFxBus.index], context.xg, 'addToTail');
        rotateEffect = Synth.new(\rotate, [\bus, postFxBus.index], context.xg, 'addToTail');
        dimensionEffect = Synth.new(\dimension, [\bus, postFxBus.index], context.xg, 'addToTail');
        haasEffect = Synth.new(\haas, [\bus, postFxBus.index, \haas, 0.0], context.xg, 'addToTail');
        widthEffect = Synth.new(\width, [\bus, postFxBus.index, \width, 1.0], context.xg, 'addToTail');
        monobassEffect = Synth.new(\monobass, [\bus, postFxBus.index, \mix, 0.0], context.xg, 'addToTail');
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
        this.addCommand("lpf_gain", "if", { arg msg; var voice = msg[1] - 1; currentlpf_gain[voice] = msg[2]; voices[voice].set(\lpf_gain, msg[2]); });
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
        this.addCommand("ratcheting_prob", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\ratcheting_prob, msg[2] * 0.01); });

        this.addCommand("bitcrush_mix", "f", { arg msg; bitcrushEffect.set(\mix, msg[1]); bitcrushEffect.run(msg[1] > 0); });
        this.addCommand("bitcrush_rate", "f", { arg msg; bitcrushEffect.set(\rate, msg[1]); });
        this.addCommand("bitcrush_bits", "f", { arg msg; bitcrushEffect.set(\bits, msg[1]); });
        
        this.addCommand("read", "is", { arg msg; var voice = msg[1] - 1; this.readBuf(voice, msg[2]); });
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

        this.addCommand("glitch_ratio", "f", { arg msg; currentGlitchRatio = msg[1]; glitchEffect.set(\glitch_ratio, currentGlitchRatio); glitchEffect.run((currentGlitchRatio > 0) && (currentGlitchMix > 0)); });
        this.addCommand("glitch_mix", "f", { arg msg; currentGlitchMix = msg[1]; glitchEffect.set(\mix, currentGlitchMix); glitchEffect.run((currentGlitchRatio > 0) && (currentGlitchMix > 0)); });
        this.addCommand("glitch_probability", "f", { arg msg; glitchEffect.set(\probability, msg[1]); });
        this.addCommand("glitch_maxstutters", "i", { arg msg; glitchEffect.set(\maxStutters, msg[1]); });
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
        this.addCommand("stereo_trig_offset", "if", { arg msg; var voice = msg[1] - 1; currentStereoTrigOffset[voice] = msg[2]; voices[voice].set(\stereo_trig_offset, msg[2]); });
        this.addCommand("stereo_independent", "ii", { arg msg; var voice = msg[1] - 1; currentStereoIndependent[voice] = msg[2]; voices[voice].set(\stereo_independent, msg[2]); });

        this.addCommand("voice_run", "ii", { arg msg; var voice = msg[1] - 1; var state = msg[2]; voices[voice].run(state > 0); });
        this.addCommand("set_live_input", "ii", { arg msg; var voice = msg[1] - 1; var enable = msg[2]; if (enable == 1, { if (liveInputRecorders[voice].notNil, { liveInputRecorders[voice].free; }); liveRecPosBuses[voice].set(-1.0); liveInputRecorders[voice] = Synth.new(\liveInputRecorder, [ \bufL, liveInputBuffersL[voice], \bufR, liveInputBuffersR[voice], \mix, liveBufferMix, \voice, voice, \recPosBus, liveRecPosBuses[voice].index ], context.xg, 'addToHead'); voicesUsingLiveBuffer[voice] = true; voices[voice].set( \buf_l, liveInputBuffersL[voice], \buf_r, liveInputBuffersR[voice], \rec_pos_bus, liveRecPosBuses[voice].index, \t_reset_pos, 1); voices[voice].run(true); }, { if (liveInputRecorders[voice].notNil, { liveInputRecorders[voice].free; }); liveInputRecorders[voice] = nil; liveRecPosBuses[voice].set(-1.0); voices[voice].set(\rec_pos_bus, -1); }); });
        this.addCommand("live_buffer_mix", "f", { arg msg; liveBufferMix = msg[1]; liveInputRecorders.do({ arg recorder; if (recorder.notNil, {recorder.set(\mix, liveBufferMix);}); }); });
        this.addCommand("live_direct", "ii", { arg msg; var voice = msg[1] - 1; var enable = msg[2]; var currentParams, scaleType; if (enable == 1, { if (voices[voice].notNil, { voices[voice].free; }); if (liveInputRecorders[voice].notNil, { liveInputRecorders[voice].free; }); voices[voice] = Synth.new(\liveDirect, [ \out, mixBus.index,\pan, currentPan[voice] ? 0,\spread, currentSpread[voice] ? 0,\gain, currentVolume[voice] ? 1,\cutoff, currentCutoff[voice] ? 20000,\lpf_gain, currentlpf_gain[voice] ? 0.95,\hpf, currentHpf[voice] ? 20,\low_gain, currentLowGain[voice] ? 0,\mid_gain, currentMidGain[voice] ? 0,\high_gain, currentHighGain[voice] ? 0, \voice, voice ], target: pg); voices[voice].run(true); }, { if (voices[voice].notNil, { voices[voice].free; }); scaleType = currentPitchRandomScale[voice] ? 0; currentParams = Dictionary.newFrom([\speed, currentSpeed[voice] ? 0.1,\jitter, currentJitter[voice] ? 0.25,\size, currentSize[voice] ? 0.1,\density, currentDensity[voice] ? 10,\pitch_offset, currentPitch[voice] ? 1,\pan, currentPan[voice] ? 0,\spread, currentSpread[voice] ? 0,\gain, currentVolume[voice] ? 1,\granular_gain, currentGranularGain[voice] ? 1,\cutoff, currentCutoff[voice] ? 20000,\lpf_gain, currentlpf_gain[voice] ? 0.95,\hpf, currentHpf[voice] ? 20,\subharmonics_1, currentSubharmonics1[voice] ? 0,\subharmonics_2, currentSubharmonics2[voice] ? 0,\subharmonics_3, currentSubharmonics3[voice] ? 0,\overtones_1, currentOvertones1[voice] ? 0,\overtones_2, currentOvertones2[voice] ? 0,\pitch_mode, currentPitchMode[voice] ? 0,\trig_mode, currentTrigMode[voice] ? 0,\direction_mod, currentDirectionMod[voice] ? 0,\size_variation, currentSizeVariation[voice] ? 0,\smoothbass, currentSmoothbass[voice] ? 1,\low_gain, currentLowGain[voice] ? 0,\mid_gain, currentMidGain[voice] ? 0,\high_gain, currentHighGain[voice] ? 0,\probability, currentProbability[voice] ? 100, \pitch_lag, currentPitchLag[voice] ? 0,\density_mod_amt, currentDensityModAmt[voice] ? 0,\pitch_random_prob, currentPitchRandomProb[voice] ? 0,\pitch_random_scale_buf, pitchScaleBuffers[scaleType].bufnum,\pitch_random_scale_len, pitchScaleLengths[scaleType],\ratcheting_prob, currentRatchetingProb[voice] ? 0]); voices[voice] = Synth.new(\synth1, [ \out, mixBus.index, \buf_l, buffersL[voice], \buf_r, buffersR[voice], \voice, voice ] ++ currentParams.getPairs, target: pg); voices[voice].set(\t_reset_pos, 1); }); });
        this.addCommand("isMono", "ii", { arg msg; var voice = msg[1] - 1; voices[voice].set(\isMono, msg[2]); });
        this.addCommand("live_mono", "ii", { arg msg; var voice = msg[1] - 1; var mono = msg[2]; if(liveInputRecorders[voice].notNil, {liveInputRecorders[voice].set(\isMono, mono); }); });
        this.addCommand("unload_all", "", {this.unloadAll(); });
        this.addCommand("pause_voice", "i", { arg msg; var voice = msg[1] - 1; if(voices[voice].notNil, {voices[voice].set(\buf_l, silentBuffer, \buf_r, silentBuffer, \t_reset_pos, 1); voices[voice].run(false); }); });
        this.addCommand("save_live_buffer", "is", { arg msg; var voice = msg[1] - 1; var filename = msg[2]; this.saveLiveBufferToTape(voice, filename); });
        this.addCommand("live_buffer_length","f",{ arg msg; var length=msg[1],myGeneration; liveBufferAllocGeneration=liveBufferAllocGeneration+1; myGeneration=liveBufferAllocGeneration; fork{ var newBufsL=Array.fill(2,{Buffer.alloc(context.server,(context.server.sampleRate*length).round.asInteger)}),newBufsR=Array.fill(2,{Buffer.alloc(context.server,(context.server.sampleRate*length).round.asInteger)}); context.server.sync; if(myGeneration==liveBufferAllocGeneration,{ var oldBufsL=liveInputBuffersL,oldBufsR=liveInputBuffersR; liveInputBuffersL=newBufsL; liveInputBuffersR=newBufsR; liveInputRecorders.do({ arg recorder,i; if(recorder.notNil,{ recorder.free; liveRecPosBuses[i].set(-1.0); liveInputRecorders[i]=Synth.new(\liveInputRecorder,[\bufL,liveInputBuffersL[i],\bufR,liveInputBuffersR[i],\mix,liveBufferMix,\voice,i,\recPosBus,liveRecPosBuses[i].index],context.xg,'addToHead'); voices[i].set(\buf_l,liveInputBuffersL[i],\buf_r,liveInputBuffersR[i],\rec_pos_bus,liveRecPosBuses[i].index,\t_reset_pos,1);},{ if(voicesUsingLiveBuffer[i] && voices[i].notNil,{ voices[i].set(\buf_l,liveInputBuffersL[i],\buf_r,liveInputBuffersR[i],\t_reset_pos,1); }); }); });oldBufsL.do({ arg buf; if(buf.notNil,{buf.free})}); oldBufsR.do({ arg buf; if(buf.notNil,{buf.free})});},{ newBufsL.do({ arg buf; if(buf.notNil,{buf.free})}); newBufsR.do({ arg buf; if(buf.notNil,{buf.free})});});};});

        o = OSCFunc({ |msg| var voice, pos; voice = msg[3].asInteger; pos = msg[4]; nornsAddr.sendMsg("/twins/buf_pos", voice, pos); }, '/buf_pos', context.server.addr);
        o_rec = OSCFunc({ |msg| var voice, pos; voice = msg[3].asInteger; pos = msg[4]; nornsAddr.sendMsg("/twins/rec_pos", voice, pos); }, '/rec_pos', context.server.addr);
        o_grain = OSCFunc({ |msg| var voice, pos, size, rv; voice = msg[3].asInteger; pos = msg[4]; size = msg[5]; rv = msg[6]; nornsAddr.sendMsg("/twins/grain_pos", voice, pos, size, rv);}, '/grain_pos', context.server.addr);
        o_grain_r = OSCFunc({ |msg| var voice, pos, size, rv; voice = msg[3].asInteger; pos = msg[4]; size = msg[5]; rv = msg[6]; nornsAddr.sendMsg("/twins/grain_pos_r", voice, pos, size, rv);}, '/grain_pos_r', context.server.addr);
        o_voice_peak = OSCFunc({ |msg| var voice, peakL, peakR; voice = msg[3].asInteger; peakL = msg[4]; peakR = msg[5]; nornsAddr.sendMsg("/twins/voice_peak", voice, peakL, peakR); }, '/voice_peak', context.server.addr);
    }

free {
        voices.do({ arg voice; if (voice.notNil) { voice.free; }; });
        buffersL.do({ arg b; if (b.notNil) { b.free; }; });
        buffersR.do({ arg b, i; if(b.notNil && (b !== buffersL[i])) { b.free }; });
        liveInputBuffersL.do({ arg b; if (b.notNil) { b.free; }; });
        liveInputBuffersR.do({ arg b; if (b.notNil) { b.free; }; });
        liveInputRecorders.do({ arg s; if (s.notNil) { s.free; }; });
        if (liveRecPosBuses.notNil) { liveRecPosBuses.do({ arg b; if (b.notNil) { b.free; }; }); };
        pitchScaleBuffers.do({ arg b; if (b.notNil) { b.free; }; });
        if (grainEnvs.notNil) { grainEnvs.do({ arg buf; if (buf.notNil) { buf.free; }; }); };
        if (o.notNil) { o.free; o = nil; };
        if (o_rec.notNil) { o_rec.free; o_rec = nil; };
        if (o_grain.notNil) { o_grain.free; o_grain = nil; };
        if (o_grain_r.notNil) { o_grain_r.free; o_grain_r = nil; };
        if (o_voice_peak.notNil) { o_voice_peak.free; o_voice_peak = nil; };
        if (wobbleBuffer.notNil) { wobbleBuffer.free; wobbleBuffer = nil; };
        if (glitchBuffer.notNil) { glitchBuffer.free; glitchBuffer = nil; };
        if (silentBuffer.notNil) { silentBuffer.free; silentBuffer = nil; };
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