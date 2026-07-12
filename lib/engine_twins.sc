Engine_twins : CroneEngine {

var analogDriveEffect, dimensionEffect, haasEffect, bitcrushEffect, resonatorEffect, wavefoldEffect, ringmodEffect, delayEffect, shimmerEffect, tapeEffect, chewEffect, widthEffect, monobassEffect, sineEffect, wobbleEffect, lossdegradeEffect, rotateEffect, glitchEffect, <silentBuffer, <buffersL, <buffersR, wobbleBuffer, glitchBuffer, <voices, bufSine, pg, <liveInputBuffersL, <liveInputBuffersR, <liveInputRecorders, <liveRecPosBuses, o, o_rec, o_grain, o_voice_peak, o_delayduck, liveBufferAllocGeneration = 0, grainEnvs, pitchScaleBuffers, pitchScaleLengths, nornsAddr, voicesUsingLiveBuffer, currentSpeed, currentJitter, currentSize, currentDensity, currentDensityModAmt, currentPitch, currentPan, currentSpread, currentVolume, currentGranularGain, currentCutoff, currentHpf, currentlpf_gain, currentSubharmonics1, currentSubharmonics2, currentSubharmonics3, currentOvertones1, currentOvertones2, currentPitchMode, currentDirectionMod, currentSizeVariation, currentSmoothbass, currentLowGain, currentMidGain, currentHighGain, currentProbability, liveBufferMix = 1.0, currentPitchRandomProb, currentPitchRandomScale, currentRatchetingProb, currentPitchLag, currentGlitchRatio = 0.0, currentGlitchMix = 0.0, currentKeyHold, currentKeyGate, currentAdA, currentAdD, currentVelAmp, currentAmpRandomize, voiceBuses, filterSynths, filterRouters, eqSynths, dryGroup, drySynths, voiceAmpBuses, voiceRunning, voiceIsStereo, bounceTracks, normOnLoad = 0;

classvar pitchScales;
*initClass {pitchScales = [[7, 12], [7, 12, 19, 24], [12], [12, 24], [1,2,3,4,5,6,7,8,9,10,11], [2,4,5,7,9,11], [2,3,5,7,8,10], [2,4,7,9], [2,4,6,8,10]];}
*new { arg context, doneCallback; ^super.new(context, doneCallback); }

readBuf { arg i, path; if(buffersL[i].notNil && buffersR[i].notNil, { if(File.exists(path), { if(normOnLoad == 1, { fork { var shm = "/dev/shm/twins_norm" ++ i ++ ".wav"; var tmp = Buffer.read(context.server, path); context.server.sync; tmp.normalize(-6.dbamp); context.server.sync; tmp.write(shm, "WAV", "float"); context.server.sync; tmp.free; this.loadSplit(i, shm); }; }, { this.loadSplit(i, path); }); }); }); }
loadSplit { arg i, path; var numChannels = SoundFile.use(path.asString(), { |f| f.numChannels }); Buffer.readChannel(context.server, path, 0, -1, [0], { |b| var oldL = buffersL[i]; voices[i].set(\buf_l, b); drySynths[i].set(\buf_l, b); buffersL[i] = b; oldL.free; if(numChannels <= 1, { var oldR = buffersR[i]; voices[i].set(\buf_r, b, \is_stereo, 0); voiceIsStereo[i] = 0; buffersR[i] = b; if(oldR !== oldL) { oldR.free }; voices[i].set(\t_reset_pos, 1); voices[i].run(true); drySynths[i].set(\buf_r, b, \t_reset_pos, 1); voiceRunning[i] = true; this.updateDryRun(i); }, { Buffer.readChannel(context.server, path, 0, -1, [1], { |b2| var oldR = buffersR[i]; voices[i].set(\buf_r, b2, \is_stereo, 1); voiceIsStereo[i] = 1; buffersR[i] = b2; if(oldR !== oldL) { oldR.free }; voices[i].set(\t_reset_pos, 1); voices[i].run(true); drySynths[i].set(\buf_r, b2, \t_reset_pos, 1); voiceRunning[i] = true; this.updateDryRun(i); }); }); }); }

unloadAll { fork { 2.do({ arg i; if(voices[i].notNil, { voices[i].set(\buf_l, silentBuffer, \buf_r, silentBuffer, \is_stereo, 0, \t_reset_pos, 1); voices[i].run(false); }); voiceIsStereo[i] = 0; drySynths[i].set(\buf_l, silentBuffer, \buf_r, silentBuffer, \t_reset_pos, 1); voiceRunning[i] = false; this.updateDryRun(i); voicesUsingLiveBuffer[i] = false; liveInputBuffersL[i].zero; liveInputBuffersR[i].zero; if(liveInputRecorders[i].notNil, { liveInputRecorders[i].free; liveInputRecorders[i] = nil; }); }); wobbleBuffer.zero; glitchBuffer.zero; }; }

saveLiveBufferToTape { arg voice, filename; var dir = "/home/we/dust/audio/tape/twins/", path = dir ++ filename, bufL = liveInputBuffersL[voice], bufR = liveInputBuffersR[voice]; fork { var interleaved = Buffer.alloc(context.server, bufL.numFrames, 2); File.mkdir(dir); context.server.sync; Synth.new(\bufInterleave, [\bufL, bufL, \bufR, bufR, \outBuf, interleaved], context.xg, 'addToTail'); ((bufL.numFrames / context.server.sampleRate) + 0.2).wait; interleaved.write(path, "WAV", "float"); context.server.sync; this.readBuf(voice, path); interleaved.free; }; }

bounce { arg mode, dur, name, pre = 0, xf = 0; fork { var dir = "/home/we/dust/audio/tape/twins/"; var comp = { arg v; if(pre == 1, { (currentVolume[v] ? 1).max(1e-4).reciprocal }, { 1 }) }; var recs = case { mode == 2 } { [[voiceBuses[0].index, voiceBuses[0].index, comp.(0), 0], [voiceBuses[1].index, voiceBuses[1].index, comp.(1), 0]] } { mode == 1 } { [[context.out_b.index, context.out_b.index, 1, 0]] } { [[voiceBuses[0].index, voiceBuses[1].index, comp.(0), comp.(1)]] }; var n = recs.size; var frames = (context.server.sampleRate * dur).round.asInteger; var bufs = Array.fill(n, { Buffer.alloc(context.server, frames, 2) }); var suffix = if(n == 2, { ["_1", "_2"] }, { [""] }); var paths = Array.fill(n, { arg i; dir ++ name ++ suffix[i] ++ ".wav" }); var synths; File.mkdir(dir); context.server.sync; synths = Array.fill(n, { arg i; var r = recs[i]; Synth.new(\bounceRec, [\buf, bufs[i], \bus1, r[0], \bus2, r[1], \c1, r[2], \c2, r[3], \xf, xf], context.xg, 'addToTail'); }); if(pre == 1, { bounceTracks = if(mode == 2, { [[synths[0], \c1], [synths[1], \c1]] }, { [[synths[0], \c1], [synths[0], \c2]] }); }); (dur + xf.clip(0.005, dur) + 0.2).wait; bounceTracks = nil; n.do({ arg i; bufs[i].write(paths[i], "WAV", "float"); }); context.server.sync; synths.do(_.free); bufs.do(_.free); nornsAddr.sendMsg("/twins/bounce_done", mode); }; }

alloc {
        nornsAddr = NetAddr("127.0.0.1", 10111);
        buffersL = Array.fill(2, { Buffer.alloc(context.server, context.server.sampleRate * 1); });
        buffersR = Array.fill(2, { Buffer.alloc(context.server, context.server.sampleRate * 1); });

        liveInputBuffersL = Array.fill(2, { Buffer.alloc(context.server, context.server.sampleRate * 8); });
        liveInputBuffersR = Array.fill(2, { Buffer.alloc(context.server, context.server.sampleRate * 8); });
        liveInputRecorders = Array.fill(2, { nil });
        voicesUsingLiveBuffer = Array.fill(2, { false });
        voiceIsStereo = Array.fill(2, { 0 });
        liveRecPosBuses = Array.fill(2, { Bus.control(context.server, 1) });
        liveRecPosBuses.do({ |b| b.set(-1.0); });

        bufSine = Buffer.alloc(context.server, 1024 * 16, 1);
        bufSine.sine2([2], [0.5], false);
        wobbleBuffer = Buffer.alloc(context.server, context.server.sampleRate * 5, 2);
        glitchBuffer = Buffer.alloc(context.server, context.server.sampleRate * 1, 2);
        silentBuffer = Buffer.alloc(context.server, context.server.sampleRate.asInteger);
        voiceBuses = Array.fill(2, { Bus.audio(context.server, 2); });
        voiceAmpBuses = Array.fill(2, { Bus.control(context.server, 1); });
        voiceRunning = Array.fill(2, { false });

        grainEnvs = [
            Env.new([0, 1, 1, 0], [0.15, 0.7, 0.15], [4, 0, -4]),
            Env.perc(0.01, 0.99, 1, -4),
            Env.adsr(0.25, 0.15, 0.65, 1, 1, -4, 0)
        ].collect { |env| Buffer.sendCollection(context.server, env.discretize) };

        pitchScaleBuffers = pitchScales.collect { |scale| Buffer.sendCollection(context.server, scale, 1) };
        pitchScaleLengths = pitchScales.collect(_.size);

        currentSpeed = [0.1, 0.1]; currentJitter = [0.25, 0.25]; currentSize = [0.1, 0.1]; currentDensity = [10, 10]; currentPitch = [1, 1]; currentPan = [0, 0]; currentSpread = [0, 0]; currentVolume = [1, 1]; currentGranularGain = [1, 1]; currentCutoff = [20000, 20000]; currentlpf_gain = [0.95, 0.95]; currentHpf = [20, 20]; currentSubharmonics1 = [0, 0]; currentSubharmonics2 = [0, 0]; currentSubharmonics3 = [0, 0]; currentOvertones1 = [0, 0]; currentOvertones2 = [0, 0]; currentPitchMode = [0, 0]; currentDirectionMod = [0, 0]; currentSizeVariation = [0, 0]; currentSmoothbass = [1, 1]; currentDensityModAmt = [0, 0]; currentLowGain = [0, 0]; currentMidGain = [0, 0]; currentHighGain = [0, 0]; currentProbability = [100, 100]; liveBufferMix = 1.0; currentPitchRandomProb = [0, 0]; currentPitchRandomScale = [0, 0]; currentRatchetingProb = [0, 0]; currentPitchLag = [0, 0];
        currentKeyHold = [1, 1]; currentKeyGate = [0, 0]; currentAdA = [0.005, 0.005]; currentAdD = [0.3, 0.3]; currentVelAmp = [1, 1]; currentAmpRandomize = [0, 0];

        context.server.sync;

        SynthDef(\synth1, {
            arg out, voice, buf_l, buf_r, pos, speed, jitter, size, density, density_mod_amt, pitch_offset, pan, spread, gain, t_reset_pos, granular_gain, pitch_mode, subharmonics_1, subharmonics_2, subharmonics_3, overtones_1, overtones_2, cutoff, hpf, lpf_gain, direction_mod, size_variation, low_gain, mid_gain, high_gain, smoothbass, probability, env_select = 0, pitch_random_prob=0, pitch_random_scale_buf=0, pitch_random_scale_len=1, pitch_random_direction=1, ratcheting_prob=0, pitch_lag_time, rec_pos_bus = -1, key_hold = 1, key_gate = 0, t_retrig = 0, ad_a = 0.005, ad_d = 0.3, vel_amp = 1, t_key_trig = 0, base_trig, amp_bus, amp_randomize = 0, is_stereo = 0;
            var grain_trig, jitter_sig, buf_pos, sig_mix, density_mod, granular_sig, base_pitch, grain_pitch, grain_size, key_env, amp_scale, dmod_half, grain_amp_rand, meter_sig;
            var main_vol = 1 / (1 + subharmonics_1 + subharmonics_2 + subharmonics_3 + overtones_1 + overtones_2);
            var subharmonic_1_vol = subharmonics_1 * main_vol * 2;
            var subharmonic_2_vol = subharmonics_2 * main_vol * 2;
            var subharmonic_3_vol = subharmonics_3 * main_vol * 2;
            var overtone_1_vol = overtones_1 * main_vol * 1.5;
            var overtone_2_vol = overtones_2 * main_vol * 1.5;
            var trigger60 = Impulse.kr(60);
            var grain_direction, speed_dir, base_grain_trig, rand_val, rand_val2, random_interval, ratchet_gate, extra_trig, signal, envBuf, randomEnv, harmonics, volumes, l_harmonics, r_harmonics, size_mults, jitter_range, buf_frames_l, buf_dur_recip, wrapped_grain_pos;
            var spreadMults, stereoSpreadMults, haasOffsets, detuneCents, density_phase;
            speed = Lag.kr(speed, 1);
            dmod_half = density_mod_amt * 0.5;
            density_mod = density * (2 ** LFNoise1.kr(density, dmod_half, dmod_half));
            density_phase = Phasor.kr(trig: t_key_trig, rate: density_mod / ControlRate.ir, start: 0, end: 1, resetPos: 0);
            base_trig = HPZ1.kr(density_phase) < 0;
            ratchet_gate = CoinGate.kr(ratcheting_prob, base_trig);
            extra_trig = TDelay.kr(ratchet_gate, density_mod.reciprocal * 0.5, 2.0);
            base_grain_trig = base_trig + extra_trig;
            key_env = EnvGen.kr(Env.asr(ad_a, 1, ad_d, \sin), gate: key_gate.max(key_hold) * (1 - t_retrig));
            grain_trig = (CoinGate.kr(probability, base_grain_trig) * (key_env > 0.0001)) + t_key_trig;
            rand_val = TRand.kr(trig: grain_trig, lo: 0, hi: 1);
            rand_val2 = TRand.kr(trig: grain_trig, lo: 0, hi: 1);
            grain_amp_rand = 1 - (amp_randomize * TRand.kr(trig: grain_trig, lo: 0, hi: 1));
            grain_size = size * (1 + TRand.kr(trig: grain_trig, lo: size_variation.neg, hi: size_variation));
            speed_dir = Select.kr(pitch_mode, [1, Select.kr(speed.abs > 0.001, [1, speed.sign])]);
            grain_direction = speed_dir * Select.kr((rand_val < direction_mod), [1, -1]);
            buf_frames_l = BufFrames.kr(buf_l);
            buf_dur_recip = SampleRate.ir / buf_frames_l;
            jitter_range = buf_dur_recip * jitter;
            jitter_sig = TRand.kr(trig: grain_trig, lo: jitter_range.neg, hi: jitter_range);
            buf_pos = Phasor.kr(trig: t_reset_pos, rate: buf_dur_recip / ControlRate.ir * speed, start: 0, end: 1, resetPos: pos);

            base_pitch = Select.kr(pitch_mode, [speed * pitch_offset, pitch_offset]);
            grain_pitch = Lag.kr(base_pitch, pitch_lag_time);
            random_interval = BufRd.kr(1, pitch_random_scale_buf, TIRand.kr(0, pitch_random_scale_len - 1, grain_trig));
            grain_pitch = grain_pitch * (((rand_val2 < pitch_random_prob) * random_interval * pitch_random_direction).midiratio);
            randomEnv = TIRand.kr(0, 2, grain_trig);
            envBuf = Select.kr(env_select, [-1] ++ grainEnvs ++ [Select.kr(randomEnv, grainEnvs)]);
            harmonics   = [1, 1/2, 1/4, 1/8, 2, 4];
            volumes     = [main_vol, subharmonic_1_vol, subharmonic_2_vol, subharmonic_3_vol, overtone_1_vol, overtone_2_vol];
            size_mults  = [1, smoothbass, smoothbass, smoothbass, 1, 1];
            spreadMults = [0.75, 0.5, 0.25, 0.0, 1.0, 1.0];
            stereoSpreadMults = [1.0, 0.6, 0.3, 0.0, 1.0, 1.0];
            haasOffsets = [0.0015, 0.006, 0.0005, 0.0, 0.003, 0.005];
            detuneCents = [0.0, 0.0, 0.0, 0.0, 2.0, 3.0];
            l_harmonics = harmonics.collect { |harmonic, i|
                var harmonic_spread = spread * spreadMults[i];
                var sm = stereoSpreadMults[i];
                var pan_lo = Select.kr(is_stereo, [harmonic_spread.neg, sm.neg]);
                var pan_hi = Select.kr(is_stereo, [harmonic_spread, sm * ((2 * spread) - 1)]);
                var trig_l = TDelay.kr(grain_trig * (volumes[i] > 0), haasOffsets[i] * spread);
                var harmonic_pan = (pan + TRand.kr(trig: grain_trig, lo: pan_lo, hi: pan_hi)).clip(-1.0, 1.0);
                GrainBuf.ar(numChannels: 2, trigger: trig_l, dur: grain_size * size_mults[i], sndbuf: buf_l, rate: grain_pitch * harmonic * grain_direction, pos: buf_pos + jitter_sig, interp: 4, pan: harmonic_pan, envbufnum: envBuf, mul: volumes[i] * grain_amp_rand);
            };
            r_harmonics = harmonics.collect { |harmonic, i|
                var detuneRatio = ((detuneCents[i] * spread) / 1200).midiratio;
                var harmonic_spread = spread * spreadMults[i];
                var sm = stereoSpreadMults[i];
                var active_trig = grain_trig * (volumes[i] > 0);
                var pan_lo = Select.kr(is_stereo, [harmonic_spread.neg, sm * (1 - (2 * spread))]);
                var pan_hi = Select.kr(is_stereo, [harmonic_spread, sm]);
                var harmonic_pan = (pan + TRand.kr(trig: grain_trig, lo: pan_lo, hi: pan_hi)).clip(-1.0, 1.0);
                GrainBuf.ar(numChannels: 2, trigger: active_trig, dur: grain_size * size_mults[i], sndbuf: buf_r, rate: grain_pitch * harmonic * grain_direction * detuneRatio, pos: buf_pos + jitter_sig, interp: 4, pan: harmonic_pan, envbufnum: envBuf, mul: volumes[i] * grain_amp_rand);
            };
            granular_sig = Mix.ar(l_harmonics) + Mix.ar(r_harmonics);
            sig_mix = (granular_sig * granular_gain).tanh;
            amp_scale = Lag.kr(gain) * key_env * vel_amp;
            signal = sig_mix * amp_scale;
            meter_sig = granular_sig * amp_scale;
            Out.kr(amp_bus, amp_scale);
            wrapped_grain_pos = Wrap.kr(buf_pos + jitter_sig);
            SendReply.kr(trigger60, '/voice_state', [voice, buf_pos, Peak.kr(meter_sig[0], trigger60), Peak.kr(meter_sig[1], trigger60)]);
            {
                var throttled_grain_trig = Trig1.kr(grain_trig, 1/30);
                SendReply.kr(throttled_grain_trig, '/grain_pos', [voice, Latch.kr(wrapped_grain_pos, grain_trig), Latch.kr(grain_size, grain_trig), Latch.kr(rand_val, grain_trig)]);
            }.value;
            Out.ar(out, signal);
        }).add;

        SynthDef(\voiceeq, {
            arg bus, low_gain = 0, mid_gain = 0, high_gain = 0;
            var sig = In.ar(bus, 2);
            sig = BLowShelf.ar(sig, 55, 6, low_gain);
            sig = BPeakEQ.ar(sig, 700, 1, mid_gain);
            sig = BHiShelf.ar(sig, 3900, 6, high_gain);
            ReplaceOut.ar(bus, sig);
        }).add;

        SynthDef(\voicefilter, {
            arg bus, cutoff = 20000, hpf = 20, lpf_gain = 0.95;
            var sig = In.ar(bus, 2);
            var lagcutoff = Lag.kr(cutoff, 0.6);
            sig = HPF.ar(sig, hpf);
            sig = MoogFF.ar(sig, lagcutoff, lpf_gain);
            ReplaceOut.ar(bus, sig);
        }).add;

        SynthDef(\voicerouter, {
            arg in, out;
            Out.ar(out, In.ar(in, 2));
        }).add;

        SynthDef(\drysynth, {
            arg out, buf_l, buf_r, pos = 0, speed = 1, pan = 0, granular_gain = 1, t_reset_pos = 0, rec_pos_bus = -1, amp_bus;
            var buf_frames_l = BufFrames.kr(buf_l);
            var lagged_speed = Lag.kr(speed, 1);
            var buf_dur_recip = SampleRate.ir / buf_frames_l;
            var buf_pos = Phasor.kr(trig: t_reset_pos, rate: buf_dur_recip / ControlRate.ir * lagged_speed, start: 0, end: 1, resetPos: pos);
            var dry_seek_trig     = K2A.ar(t_reset_pos);
            var dry_mute_env      = EnvGen.ar(Env([0, 1, 1, 0], [0.015, 0.005, 0.020], \sin), gate: dry_seek_trig);
            var dry_seek_fade     = 1.0 - dry_mute_env;
            var delayed_dry_reset = TDelay.ar(dry_seek_trig, 0.017);
            var dry_rate          = lagged_speed * BufRateScale.kr(buf_l);
            var dry_phase         = Phasor.ar(delayed_dry_reset, dry_rate, 0, buf_frames_l, pos * buf_frames_l);
            var dry_sig = [BufRd.ar(1, buf_l, dry_phase, loop: 1, interpolation: 4) * dry_seek_fade, BufRd.ar(1, buf_r, dry_phase, loop: 1, interpolation: 4) * dry_seek_fade];
            var recPos = In.kr(rec_pos_bus.max(0));
            var diff = (buf_pos - recPos.max(0)).abs;
            var wrappedDist = diff.min(1.0 - diff);
            var fadeZoneNorm = (0.03 * SampleRate.ir) / buf_frames_l;
            var liveDryFade = (wrappedDist / fadeZoneNorm).clip(0, 1);
            var dryFade = Select.kr((rec_pos_bus >= 0), [1.0, liveDryFade]);
            var amp = In.kr(amp_bus);
            dry_sig = (dry_sig * dryFade).tanh;
            Out.ar(out, Balance2.ar(dry_sig[0], dry_sig[1], pan) * (1 - granular_gain) * amp);
        }).add;

        context.server.sync;

        pg = ParGroup.head(context.xg);
        dryGroup = Group.after(pg);
        voices = Array.fill(2, { arg i;
            Synth.newPaused(\synth1, [
                \out, voiceBuses[i].index,
                \buf_l, buffersL[i],
                \buf_r, buffersR[i],
                \voice, i,
                \amp_bus, voiceAmpBuses[i].index,
                \pitch_random_scale_buf, pitchScaleBuffers[0].bufnum,
                \pitch_random_scale_len, pitchScaleLengths[0],
                \key_hold, currentKeyHold[i],
                \key_gate, currentKeyGate[i],
                \ad_a, currentAdA[i],
                \ad_d, currentAdD[i],
                \vel_amp, currentVelAmp[i],
            ], pg);
        });

        drySynths = Array.fill(2, { arg i;
            Synth.newPaused(\drysynth, [
                \out, voiceBuses[i].index,
                \buf_l, buffersL[i],
                \buf_r, buffersR[i],
                \pos, 0,
                \speed, currentSpeed[i],
                \pan, currentPan[i],
                \granular_gain, currentGranularGain[i],
                \rec_pos_bus, -1,
                \amp_bus, voiceAmpBuses[i].index,
            ], dryGroup);
        });

        eqSynths = Array.fill(2, { arg i;
            Synth.newPaused(\voiceeq, [
                \bus, voiceBuses[i].index,
                \low_gain, currentLowGain[i],
                \mid_gain, currentMidGain[i],
                \high_gain, currentHighGain[i],
            ], context.xg, 'addToTail');
        });

        filterSynths = Array.fill(2, { arg i;
            Synth.newPaused(\voicefilter, [
                \bus, voiceBuses[i].index,
                \cutoff, currentCutoff[i],
                \hpf, currentHpf[i],
                \lpf_gain, currentlpf_gain[i],
            ], context.xg, 'addToTail');
        });
        
        filterRouters = Array.fill(2, { arg i;
            Synth.new(\voicerouter, [
                \in, voiceBuses[i].index,
                \out, context.out_b.index,
            ], context.xg, 'addToTail');
        });

        context.server.sync;

        SynthDef(\liveDirect, {
            arg out, pan, gain, cutoff, hpf, low_gain, mid_gain, high_gain, isMono, lpf_gain, voice, key_hold = 1, key_gate = 0, t_retrig = 0, ad_a = 0.005, ad_d = 0.3, vel_amp = 1;
            var sig = SoundIn.ar([0, 1]);
            var trigger60 = Impulse.kr(60);
            var key_env = EnvGen.kr(Env.asr(ad_a, 1, ad_d, \sin), gate: key_gate.max(key_hold) * (1 - t_retrig));
            sig = Select.ar(isMono, [sig, [sig[0], sig[0]] ]);
            sig = Balance2.ar(sig[0], sig[1], pan);
            sig = (sig * Lag.kr(gain) * key_env * vel_amp).tanh;
            SendReply.kr(trigger60, '/voice_peak', [voice, Peak.kr(sig[0], trigger60), Peak.kr(sig[1], trigger60)]);
            Out.ar(out, sig);
        }).add;

        SynthDef(\liveInputRecorder, {
            arg bufL, bufR, isMono=0, mix, voice, recPosBus;
            var in = SoundIn.ar([0, 1]);
            var bufFrames = BufFrames.kr(bufL);
            var phasor = Phasor.ar(0, 1, 0, bufFrames);
            var oldL = BufRd.ar(1, bufL, phasor);
            var oldR = BufRd.ar(1, bufR, phasor);
            var mixedL, mixedR, normPos;
            in = Select.ar(isMono, [in, [Mix.ar(in), Mix.ar(in)]]);
            mixedL = XFade2.ar(oldL, in[0], mix * 2 - 1);
            mixedR = XFade2.ar(oldR, in[1], mix * 2 - 1);
            BufWr.ar(mixedL, bufL, phasor);
            BufWr.ar(mixedR, bufR, phasor);
            normPos = phasor / bufFrames;
            Out.kr(recPosBus, A2K.kr(normPos));
            SendReply.kr(Impulse.kr(30), '/rec_pos', [voice, normPos]);
        }).add;

        SynthDef(\bufInterleave, {
            arg bufL, bufR, outBuf;
            var idx = Line.ar(0, BufFrames.ir(bufL), BufDur.ir(bufL), doneAction: 2);
            BufWr.ar([
                BufRd.ar(1, bufL, idx, loop: 0, interpolation: 1),
                BufRd.ar(1, bufR, idx, loop: 0, interpolation: 1)
            ], outBuf, idx, loop: 0);
        }).add;

        SynthDef(\bounceRec, {
            arg buf, bus1, bus2, xf = 0.005, c1 = 1, c2 = 0;
            var sig = (In.ar(bus1, 2) * Lag.kr(c1, 0.1)) + (In.ar(bus2, 2) * Lag.kr(c2, 0.1));
            var frames = BufFrames.ir(buf);
            var xframes = (xf.clip(0.005, BufDur.ir(buf)) * SampleRate.ir).round;
            var idx = Phasor.ar(0, 1, 0, frames * 4);
            var wpos = Select.ar(idx >= frames, [idx, (idx - frames).min(xframes)]);
            var w = ((idx - frames) / xframes).clip(0, 1);
            var existing = BufRd.ar(2, buf, wpos, loop: 0, interpolation: 1);
            PauseSelf.kr(A2K.kr(idx >= (frames + xframes)));
            BufWr.ar((sig * (w * 0.5pi).cos) + (existing * (w * 0.5pi).sin), buf, wpos, loop: 0);
        }).add;

        SynthDef(\delay, {
            arg bus, mix=0.0, delay=0.5, fb_amt=0.3, dhpf=20, lpf=20000, w_rate=0.0, w_depth=0.0, stereo=0.2, duck_amt=0.0;
            var input, local, fb, delayed, wet, combinedMod, lfo2Rate, lfo3Rate;
            var baseLFO, drift, wobble, steps, dryAmp, duck;
            lfo2Rate = w_rate * (1 + LFNoise1.kr(0.13, 0.18));
            lfo3Rate = w_rate * 0.71;
            baseLFO = SinOsc.kr(w_rate * [0.6, 0.63]).sum * 0.5;
            drift = LFNoise2.kr(w_rate * 0.15) * 0.35;
            wobble = SinOsc.kr(lfo2Rate + (drift * 0.6)) * LFNoise2.kr(lfo3Rate * 0.25).range(0.5, 1.2) * 0.25;
            steps = Latch.kr(LFNoise0.kr(w_rate * 6.3), Dust.kr(w_rate * 4.7)) * 0.08;
            combinedMod = w_depth * Mix([baseLFO * 0.4, drift, wobble, steps]);
            input = In.ar(bus, 2);
            local = LocalIn.ar(2);
            fb = LPF.ar(HPF.ar(local, dhpf), lpf);
            fb = (1.35 * (1 - (stereo * 0.35)) * fb_amt * [fb[1], fb[0]]).softclip;
            delayed = DelayC.ar(input + fb, 5, Lag.kr(delay, 0.7) + combinedMod);
            wet = Balance2.ar(delayed[0], delayed[1], (SinOsc.kr(delay.max(0.1).reciprocal * 0.5) + (LFNoise2.kr(0.4) * 0.3)) * (stereo * 0.77));
            LocalOut.ar(wet);
            dryAmp = Amplitude.kr(input.sum, 0.005, 0.05);
            duck = LagUD.kr((1 - (dryAmp.sqrt * duck_amt * 6).clip(0, 1)), 0.15, 0.02);
            SendReply.kr(Impulse.kr(20), '/delay_duck', [duck]);
            ReplaceOut.ar(bus, input + (wet * mix * 1.6 * duck));
        }).add;

        SynthDef(\shimmer, {
            arg bus, mix=0.0, lowpass1=13000, hipass1=1400, pitchv1=0.02, fb1=0.0, fbDelay1=0.15, shimmer_oct1=2, mod_mix=0;
            var input = In.ar(bus, 2);
            var hpf = HPF.ar(input, hipass1);
            var pit = PitchShift.ar(hpf, 0.5, shimmer_oct1, pitchv1, 1, mul: 8);
            var fbSig = LocalIn.ar(2);
            var fbClean = fbSig * fb1;
            var actualMix = mix * Select.kr(mod_mix, [1.0, LFNoise1.kr(0.25).range(0.0, 1.0)]);
            var modTime;
            pit = LPF.ar((pit + fbClean), lowpass1);
            modTime = fbDelay1 + SinOsc.ar([0.07, 0.09], [0, 0.5pi], 0.5 * 0.004);
            LocalOut.ar(DelayC.ar(pit, 1.0, modTime.clip(0.001, 1.0)));
            ReplaceOut.ar(bus, input + (pit * actualMix));
        }).add;

        SynthDef(\monobass, {
            arg bus, mix=0.0;
            var sig = In.ar(bus, 2);
            sig = BHiPass.ar(sig, 200) + Pan2.ar(BLowPass.ar(sig[0] + sig[1], 200));
            ReplaceOut.ar(bus, sig);
        }).add;

        SynthDef(\bitcrush, {
            arg bus, mix=0.0, rate, bits, mod_mix=0;
            var sig = In.ar(bus, 2);
            var mod = LFNoise1.kr(0.25).range(0.4, 1);
            var actualMix = mix * Select.kr(mod_mix, [1.0, LFNoise1.kr(0.25).range(0.0, 1.0)]);
            var bit = LPF.ar(Decimator.ar(sig, Lag.kr(rate, 0.6) * mod, bits), 10000);
            ReplaceOut.ar(bus, XFade2.ar(sig, bit, actualMix * 2 - 1));
        }).add;

        SynthDef(\sine, {
            arg bus, sine_drive_wet=0;
            var orig = In.ar(bus, 2);
            var shaped = Shaper.ar(bufSine, orig * 1.5);
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
            var wet = AnalogTape.ar(orig, 0.9, 0.9, 0.9, 0, 0);
            ReplaceOut.ar(bus, XFade2.ar(orig, wet, mix * 2 - 1));
        }).add;

        SynthDef(\wobble, {
            arg bus, mix=0.0, wobble_amp=0.05, wobble_rpm=33, flutter_amp=0.03, flutter_freq=6, flutter_var=2;
            var pr, pw, rate, wet, flutter, wow, dry;
            dry = In.ar(bus, 2);
            wow = wobble_amp * SinOsc.kr(wobble_rpm/60, mul: 0.2);
            flutter = flutter_amp * SinOsc.kr(flutter_freq + LFNoise2.kr(flutter_var), mul: 0.1);
            rate = 1 + (wow + flutter);
            pw = Phasor.ar(0, BufRateScale.kr(wobbleBuffer), 0, BufFrames.kr(wobbleBuffer));
            BufWr.ar(dry, wobbleBuffer, pw);
            pr = DelayL.ar(Phasor.ar(0, BufRateScale.kr(wobbleBuffer)*rate, 0, BufFrames.kr(wobbleBuffer)), 0.2, 0.2);
            wet = BufRd.ar(2, wobbleBuffer, pr, interpolation: 4);
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
            var depth    = LFPar.kr(1/5, Rand(0, 2), 0.4, 0.5);
            var amount   = LFPar.kr(1/2, Rand(0, 2), 0.4, 0.5);
            var variance = LFPar.kr(1/3, Rand(0, 2), 0.4, 0.5);
            var envelope = LFPar.kr(1/4, Rand(0, 2), 0.4, 0.5);
            var degrade = AnalogDegrade.ar(loss, depth, amount, variance, envelope);
            ReplaceOut.ar(bus, XFade2.ar(sig, degrade, mix * 2 - 1));
        }).add;

        SynthDef(\analogdrive, {
            arg bus, mix = 0.0, drive = 0.6, tone = 0.6, mode = 0.75, mod_mix = 0;
            var dry = In.ar(bus, 2);
            var actualMix = mix * Select.kr(mod_mix, [1.0, LFNoise1.kr(0.25).range(0.0, 1.0)]);
            var pregain = dry * drive.linexp(0, 1, 1, 100);
            var clipR = pregain.clip2(0.7); 
            var outR = LPF.ar(clipR, tone.linexp(0, 1, 400, 15000));
            var clipM = LeakDC.ar((pregain + 0.1).tanh);
            var outM = LPF.ar(BPF.ar(clipM, tone.linexp(0, 1, 800, 7500), 1.5), 6000);
            var wet = SelectX.ar(mode, [outM, outR]);
            var comp = drive.linexp(0, 1, 1.0, 0.12);
            ReplaceOut.ar(bus, XFade2.ar(dry, wet * comp, actualMix * 2 - 1));
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

        SynthDef(\resonator, {
            arg bus, mix = 0.0, decay = 2.0, cutoff = 8000, f1 = 220, f2 = 277, f3 = 330, f4 = 440, f5 = 554;
            var sig, exc, freqs, amps, wet, cf, detune;
            sig = In.ar(bus, 2);
            exc = tanh(sig.sum * 0.15);
            freqs = [f1, f2, f3, f4, f5];
            amps  = [1.0, 0.9, 0.8, 0.7, 0.6];
            wet = DynKlank.ar(`[freqs, amps, Array.fill(5, decay)], exc);
            wet = tanh(0.05 * wet * decay.pow(-0.75));
            cf = Lag.kr(cutoff, 0.1).clip(20, 20000);
            wet = LeakDC.ar(RLPF.ar(wet, cf, 0.5));
            detune = DelayC.ar(wet, 0.02, [0.006, 0.011]);
            wet = wet + detune;
            ReplaceOut.ar(bus, XFade2.ar(sig, wet, mix * 2 - 1));
        }).add;

        SynthDef(\wavefold, {
            arg bus, mix=0, drive=0.75, sym=0;
            var sig = In.ar(bus, 2);
            var pregain = drive.linexp(0, 1, 1, 64);
            var makeup = pregain.pow(-0.8);
            var pre = sig * pregain + sym;
            var folded = LeakDC.ar(sin(pre * (pi/2))) * makeup;
            ReplaceOut.ar(bus,XFade2.ar(sig, folded, mix * 2 - 1));
        }).add;

        SynthDef(\ringmod, {
            arg bus, mix=0.0, rate=200, freqmod=0;
            var sig = In.ar(bus, 2);
            var modrate = rate * (1 + (LFNoise2.kr(2) * 0.1 * freqmod));
            var wet = sig * SinOsc.ar(Lag.kr(modrate, 0.05));
            ReplaceOut.ar(bus, XFade2.ar(sig, wet, mix * 2 - 1));
        }).add;

        context.server.sync;

        bitcrushEffect = Synth.newPaused(\bitcrush, [\bus, context.out_b.index, \mix, 0.0, \mod_mix, 0], context.xg, 'addToTail');
        resonatorEffect = Synth.newPaused(\resonator, [\bus, context.out_b.index, \mix, 0.0], context.xg, 'addToTail');
        wavefoldEffect = Synth.newPaused(\wavefold, [\bus, context.out_b.index, \mix, 0.0], context.xg, 'addToTail');
        ringmodEffect = Synth.newPaused(\ringmod, [\bus, context.out_b.index, \mix, 0.0], context.xg, 'addToTail');
        sineEffect = Synth.newPaused(\sine, [\bus, context.out_b.index, \sine_drive_wet, 0.0], context.xg, 'addToTail');
        analogDriveEffect = Synth.newPaused(\analogdrive, [\bus, context.out_b.index], context.xg, 'addToTail');
        glitchEffect = Synth.newPaused(\glitch, [\bus, context.out_b.index, \glitch_ratio, 0.0], context.xg, 'addToTail');
        tapeEffect = Synth.newPaused(\tape, [\bus, context.out_b.index, \mix, 0.0], context.xg, 'addToTail');
        wobbleEffect = Synth.newPaused(\wobble, [\bus, context.out_b.index, \mix, 0.0], context.xg, 'addToTail');
        chewEffect = Synth.newPaused(\chew, [\bus, context.out_b.index, \chew_depth, 0.0], context.xg, 'addToTail');
        lossdegradeEffect = Synth.newPaused(\lossdegrade, [\bus, context.out_b.index, \mix, 0.0], context.xg, 'addToTail');
        shimmerEffect = Synth.newPaused(\shimmer, [\bus, context.out_b.index, \mix, 0.0, \mod_mix, 0], context.xg, 'addToTail');
        delayEffect = Synth.newPaused(\delay, [\bus, context.out_b.index, \mix, 0.0], context.xg, 'addToTail');
        rotateEffect = Synth.newPaused(\rotate, [\bus, context.out_b.index], context.xg, 'addToTail');
        dimensionEffect = Synth.newPaused(\dimension, [\bus, context.out_b.index], context.xg, 'addToTail');
        haasEffect = Synth.newPaused(\haas, [\bus, context.out_b.index, \haas, 0.0], context.xg, 'addToTail');
        widthEffect = Synth.newPaused(\width, [\bus, context.out_b.index, \width, 1.0], context.xg, 'addToTail');
        monobassEffect = Synth.newPaused(\monobass, [\bus, context.out_b.index, \mix, 0.0], context.xg, 'addToTail');

        this.addCommand(\mix, "f", { arg msg; delayEffect.set(\mix, msg[1]); delayEffect.run(msg[1] > 0); });
        this.addCommand(\delay, "f", { arg msg; delayEffect.set(\delay, msg[1]); });
        this.addCommand(\fb_amt, "f", { arg msg; delayEffect.set(\fb_amt, msg[1]); });
        this.addCommand(\dhpf, "f", { arg msg; delayEffect.set(\dhpf, msg[1]); });
        this.addCommand(\lpf, "f", { arg msg; delayEffect.set(\lpf, msg[1]); });
        this.addCommand(\w_rate, "f", { arg msg; delayEffect.set(\w_rate, msg[1]); });
        this.addCommand(\w_depth, "f", { arg msg; delayEffect.set(\w_depth, msg[1]/100); });
        this.addCommand("stereo", "f", { arg msg; delayEffect.set(\stereo, msg[1]); });
        this.addCommand("delay_duck", "f", { arg msg; delayEffect.set(\duck_amt, msg[1]); });

        this.addCommand("shimmer_mix1", "f", { arg msg; shimmerEffect.set(\mix, msg[1]); shimmerEffect.run(msg[1] > 0); });
        this.addCommand("shimmer_mod1", "i", { arg msg; shimmerEffect.set(\mod_mix, msg[1]); });
        this.addCommand("shimmer_oct1", "f", { arg msg; shimmerEffect.set(\shimmer_oct1, msg[1]); });
        this.addCommand("lowpass1", "f", { arg msg; shimmerEffect.set(\lowpass1, msg[1]); });
        this.addCommand("hipass1", "f", { arg msg; shimmerEffect.set(\hipass1, msg[1]); });
        this.addCommand("pitchv1", "f", { arg msg; shimmerEffect.set(\pitchv1, msg[1]); });
        this.addCommand("fb1", "f", { arg msg; shimmerEffect.set(\fb1, msg[1]); });
        this.addCommand("fbDelay1", "f", { arg msg; shimmerEffect.set(\fbDelay1, msg[1]); });
        
        this.addCommand("analogdrive_mix", "f", { arg msg; analogDriveEffect.set(\mix, msg[1]); analogDriveEffect.run(msg[1] > 0); }); 
        this.addCommand("analogdrive_drive", "f", { arg msg; analogDriveEffect.set(\drive, msg[1]); });
        this.addCommand("analogdrive_tone", "f", { arg msg; analogDriveEffect.set(\tone, msg[1]); });
        this.addCommand("analogdrive_mode", "f", { arg msg; analogDriveEffect.set(\mode, msg[1]); });
        this.addCommand("analogdrive_mod", "i", { arg msg; analogDriveEffect.set(\mod_mix, msg[1]); });

        this.addCommand("cutoff", "if", { arg msg; var voice = msg[1] - 1; currentCutoff[voice] = msg[2]; filterSynths[voice].set(\cutoff, msg[2]); this.updateFilterRun(voice); });
        this.addCommand("lpf_gain", "if", { arg msg; var voice = msg[1] - 1; currentlpf_gain[voice] = msg[2]; filterSynths[voice].set(\lpf_gain, msg[2]); this.updateFilterRun(voice); });
        this.addCommand("hpf", "if", { arg msg; var voice = msg[1] - 1; currentHpf[voice] = msg[2]; filterSynths[voice].set(\hpf, msg[2]); this.updateFilterRun(voice); });

        this.addCommand("granular_gain", "if", { arg msg; var voice = msg[1] - 1; currentGranularGain[voice] = msg[2]; voices[voice].set(\granular_gain, msg[2]); drySynths[voice].set(\granular_gain, msg[2]); this.updateDryRun(voice); });
        this.addCommand("env_select", "ii", { arg msg; var voice = msg[1] - 1; voices[voice].set(\env_select, msg[2]); });
        this.addCommand("density_mod_amt", "if", { arg msg; var voice = msg[1] - 1; currentDensityModAmt[voice] = msg[2]; voices[voice].set(\density_mod_amt, msg[2]); });
        this.addCommand("subharmonics_1", "if", { arg msg; var voice = msg[1] - 1; currentSubharmonics1[voice] = msg[2]; voices[voice].set(\subharmonics_1, msg[2]); });
        this.addCommand("subharmonics_2", "if", { arg msg; var voice = msg[1] - 1; currentSubharmonics2[voice] = msg[2]; voices[voice].set(\subharmonics_2, msg[2]); });
        this.addCommand("subharmonics_3", "if", { arg msg; var voice = msg[1] - 1; currentSubharmonics3[voice] = msg[2]; voices[voice].set(\subharmonics_3, msg[2]); });
        this.addCommand("overtones_1", "if", { arg msg; var voice = msg[1] - 1; currentOvertones1[voice] = msg[2]; voices[voice].set(\overtones_1, msg[2]); });
        this.addCommand("overtones_2", "if", { arg msg; var voice = msg[1] - 1; currentOvertones2[voice] = msg[2]; voices[voice].set(\overtones_2, msg[2]); });
        this.addCommand("pitch_mode", "ii", { arg msg; var voice = msg[1] - 1; currentPitchMode[voice] = msg[2]; voices[voice].set(\pitch_mode, msg[2]); });
        this.addCommand("pitch_offset", "if", { arg msg; var voice = msg[1] - 1; currentPitch[voice] = msg[2]; voices[voice].set(\pitch_offset, msg[2]); });
        this.addCommand("direction_mod", "if", { arg msg; var voice = msg[1] - 1; currentDirectionMod[voice] = msg[2]; voices[voice].set(\direction_mod, msg[2]); });
        this.addCommand("size_variation", "if", { arg msg; var voice = msg[1] - 1; currentSizeVariation[voice] = msg[2]; voices[voice].set(\size_variation, msg[2]); });
        this.addCommand("amp_randomize", "if", { arg msg; var voice = msg[1] - 1; currentAmpRandomize[voice] = msg[2]; voices[voice].set(\amp_randomize, msg[2]); });
        this.addCommand("smoothbass", "if", { arg msg; var voice = msg[1] - 1; currentSmoothbass[voice] = msg[2]; voices[voice].set(\smoothbass, msg[2]); });
        this.addCommand("probability", "if", { arg msg; var voice = msg[1] - 1; currentProbability[voice] = msg[2]; voices[voice].set(\probability, msg[2]); });
        this.addCommand("pitch_random_scale_type", "ii", { arg msg; var voice = msg[1] - 1; var scaleType = msg[2]; currentPitchRandomScale[voice] = scaleType; voices[voice].set(\pitch_random_scale_buf, pitchScaleBuffers[scaleType].bufnum, \pitch_random_scale_len, pitchScaleLengths[scaleType]); });
        this.addCommand("pitch_random_prob", "if", { arg msg; var voice = msg[1] - 1; currentPitchRandomProb[voice] = msg[2]; voices[voice].set(\pitch_random_prob, msg[2].abs * 0.01, \pitch_random_direction, msg[2].sign); });
        this.addCommand("ratcheting_prob", "if", { arg msg; var voice = msg[1] - 1; currentRatchetingProb[voice] = msg[2] * 0.01; voices[voice].set(\ratcheting_prob, msg[2] * 0.01); });

        this.addCommand("bitcrush_mix", "f", { arg msg; bitcrushEffect.set(\mix, msg[1]); bitcrushEffect.run(msg[1] > 0); });
        this.addCommand("bitcrush_rate", "f", { arg msg; bitcrushEffect.set(\rate, msg[1]); });
        this.addCommand("bitcrush_bits", "f", { arg msg; bitcrushEffect.set(\bits, msg[1]); });
        this.addCommand("bitcrush_mod", "i", { arg msg; bitcrushEffect.set(\mod_mix, msg[1]); });

        this.addCommand("read", "is", { arg msg; var voice = msg[1] - 1; this.readBuf(voice, msg[2]); });
        this.addCommand("norm_load", "i", { arg msg; normOnLoad = msg[1]; });
        this.addCommand("seek", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\pos, msg[2], \t_reset_pos, 1); drySynths[voice].set(\pos, msg[2], \t_reset_pos, 1); });
        this.addCommand("reseek", "i", { arg msg; var voice = msg[1] - 1; if(voices[voice].notNil, { voices[voice].set(\t_reset_pos, 1); }); if(drySynths[voice].notNil, { drySynths[voice].set(\t_reset_pos, 1); }); });
        this.addCommand("speed", "if", { arg msg; var voice = msg[1] - 1; currentSpeed[voice] = msg[2]; voices[voice].set(\speed, msg[2]); drySynths[voice].set(\speed, msg[2]); });
        this.addCommand("jitter", "if", { arg msg; var voice = msg[1] - 1; currentJitter[voice] = msg[2]; voices[voice].set(\jitter, msg[2] / 2); });
        this.addCommand("size", "if", { arg msg; var voice = msg[1] - 1; currentSize[voice] = msg[2]; voices[voice].set(\size, msg[2]); });
        this.addCommand("density", "if", { arg msg; var voice = msg[1] - 1; currentDensity[voice] = msg[2]; voices[voice].set(\density, msg[2]); });
        this.addCommand("pan", "if", { arg msg; var voice = msg[1] - 1; currentPan[voice] = msg[2]; voices[voice].set(\pan, msg[2]); drySynths[voice].set(\pan, msg[2]); });
        this.addCommand("spread", "if", { arg msg; var voice = msg[1] - 1; currentSpread[voice] = msg[2]; voices[voice].set(\spread, msg[2]); });
        this.addCommand("volume", "if", { arg msg; var voice = msg[1] - 1; currentVolume[voice] = msg[2]; voices[voice].set(\gain, msg[2]); if(bounceTracks.notNil, { var t = bounceTracks[voice]; t[0].set(t[1], msg[2].max(1e-4).reciprocal); }); });

        this.addCommand("tape_mix", "f", { arg msg; tapeEffect.set(\mix, msg[1]); tapeEffect.run(msg[1] > 0); });
        this.addCommand("sine_drive_wet", "f", { arg msg; sineEffect.set(\sine_drive_wet, msg[1]); sineEffect.run(msg[1] > 0); });

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

        this.addCommand("resonator_mix", "f", { arg msg; resonatorEffect.set(\mix, msg[1]); resonatorEffect.run(msg[1] > 0); });
        this.addCommand("resonator_decay", "f", { arg msg; resonatorEffect.set(\decay, msg[1]); });
        this.addCommand("resonator_tone", "f", { arg msg; resonatorEffect.set(\cutoff, msg[1]); });
        this.addCommand("resonator_freqs", "fffff", { arg msg; resonatorEffect.set(\f1, msg[1], \f2, msg[2], \f3, msg[3], \f4, msg[4], \f5, msg[5]); });
        this.addCommand("wavefold_mix", "f", { arg msg; wavefoldEffect.set(\mix, msg[1]); wavefoldEffect.run(msg[1] > 0); });
        this.addCommand("wavefold_drive", "f", { arg msg; wavefoldEffect.set(\drive, msg[1]); });
        this.addCommand("wavefold_sym", "f", { arg msg; wavefoldEffect.set(\sym, msg[1]); });
        this.addCommand("ringmod_mix", "f", { arg msg; ringmodEffect.set(\mix, msg[1]); ringmodEffect.run(msg[1] > 0); });
        this.addCommand("ringmod_rate", "f", { arg msg; ringmodEffect.set(\rate, msg[1]); });
        this.addCommand("ringmod_freqmod", "f", { arg msg; ringmodEffect.set(\freqmod, msg[1]); });

        this.addCommand("eq_low_gain", "if", { arg msg; var voice = msg[1] - 1; currentLowGain[voice] = msg[2]; eqSynths[voice].set(\low_gain, msg[2]); this.updateEqRun(voice); });
        this.addCommand("eq_mid_gain", "if", { arg msg; var voice = msg[1] - 1; currentMidGain[voice] = msg[2]; eqSynths[voice].set(\mid_gain, msg[2]); this.updateEqRun(voice); });
        this.addCommand("eq_high_gain", "if", { arg msg; var voice = msg[1] - 1; currentHighGain[voice] = msg[2]; eqSynths[voice].set(\high_gain, msg[2]); this.updateEqRun(voice); });

        this.addCommand("width", "f", { arg msg; widthEffect.set(\width, msg[1]); widthEffect.run(msg[1] != 1); });
        this.addCommand("dimension_mix", "f", { arg msg; dimensionEffect.set(\mix, msg[1]); dimensionEffect.run(msg[1] > 0); });
        this.addCommand("monobass_mix", "f", { arg msg; monobassEffect.set(\mix, msg[1]); monobassEffect.run(msg[1] > 0); });
        this.addCommand("rspeed", "f", { arg msg; rotateEffect.set(\rspeed, msg[1]); rotateEffect.run(msg[1] > 0); });
        this.addCommand("haas", "i", { arg msg; haasEffect.set(\haas, msg[1]); haasEffect.run(msg[1] > 0); });
        this.addCommand("pitch_lag", "if", { arg msg; var voice = msg[1] - 1; currentPitchLag[voice] = msg[2]; voices[voice].set(\pitch_lag_time, msg[2]); });

        this.addCommand("voice_run", "ii", { arg msg; var voice = msg[1] - 1; var state = msg[2]; if(voices[voice].notNil, { voices[voice].run(state > 0); voiceRunning[voice] = (state > 0); this.updateDryRun(voice); }); });
        this.addCommand("key_hold", "ii", { arg msg; var voice = msg[1] - 1; currentKeyHold[voice] = msg[2]; if(voices[voice].notNil, { voices[voice].set(\key_hold, msg[2]); }); });
        this.addCommand("key_gate", "ii", { arg msg; var voice = msg[1] - 1; currentKeyGate[voice] = msg[2]; if(voices[voice].notNil, { voices[voice].set(\key_gate, msg[2]); }); });
        this.addCommand("key_retrig", "i", { arg msg; var voice = msg[1] - 1; if(voices[voice].notNil, { voices[voice].set(\t_retrig, 1); }); });
        this.addCommand("key_grain", "i", { arg msg; var voice = msg[1] - 1; if(voices[voice].notNil, { voices[voice].set(\t_key_trig, 1); }); });
        this.addCommand("key_ad", "iff", { arg msg; var voice = msg[1] - 1; currentAdA[voice] = msg[2]; currentAdD[voice] = msg[3]; if(voices[voice].notNil, { voices[voice].set(\ad_a, msg[2], \ad_d, msg[3]); }); });
        this.addCommand("vel_amp", "if", { arg msg; var voice = msg[1] - 1; currentVelAmp[voice] = msg[2]; if(voices[voice].notNil, { voices[voice].set(\vel_amp, msg[2]); }); });
        this.addCommand("set_live_input", "ii", { arg msg; var voice = msg[1] - 1; var enable = msg[2]; if (enable == 1, { if (liveInputRecorders[voice].notNil, { liveInputRecorders[voice].free; }); liveRecPosBuses[voice].set(-1.0); liveInputRecorders[voice] = Synth.new(\liveInputRecorder, [ \bufL, liveInputBuffersL[voice], \bufR, liveInputBuffersR[voice], \mix, liveBufferMix, \voice, voice, \recPosBus, liveRecPosBuses[voice].index ], context.xg, 'addToHead'); voicesUsingLiveBuffer[voice] = true; voices[voice].set( \buf_l, liveInputBuffersL[voice], \buf_r, liveInputBuffersR[voice], \rec_pos_bus, liveRecPosBuses[voice].index, \is_stereo, 1, \t_reset_pos, 1); voiceIsStereo[voice] = 1; voices[voice].run(true); drySynths[voice].set( \buf_l, liveInputBuffersL[voice], \buf_r, liveInputBuffersR[voice], \rec_pos_bus, liveRecPosBuses[voice].index, \t_reset_pos, 1); voiceRunning[voice] = true; this.updateDryRun(voice); }, { if (liveInputRecorders[voice].notNil, { liveInputRecorders[voice].free; }); liveInputRecorders[voice] = nil; liveRecPosBuses[voice].set(-1.0); voices[voice].set(\rec_pos_bus, -1); drySynths[voice].set(\rec_pos_bus, -1); }); });
        this.addCommand("live_buffer_mix", "f", { arg msg; liveBufferMix = msg[1]; liveInputRecorders.do({ arg recorder; if (recorder.notNil, { recorder.set(\mix, liveBufferMix); }); }); });
        this.addCommand("live_direct", "ii", { arg msg; var voice = msg[1] - 1; var enable = msg[2]; var currentParams, scaleType; if (enable == 1, { if (voices[voice].notNil, { voices[voice].free; }); if (liveInputRecorders[voice].notNil, { liveInputRecorders[voice].free; }); voices[voice] = Synth.new(\liveDirect, [ \out, voiceBuses[voice].index,\pan, currentPan[voice] ? 0,\gain, currentVolume[voice] ? 1,\cutoff, currentCutoff[voice] ? 20000,\lpf_gain, currentlpf_gain[voice] ? 0.95,\hpf, currentHpf[voice] ? 20,\low_gain, currentLowGain[voice] ? 0,\mid_gain, currentMidGain[voice] ? 0,\high_gain, currentHighGain[voice] ? 0, \voice, voice, \key_hold, currentKeyHold[voice], \key_gate, currentKeyGate[voice], \ad_a, currentAdA[voice], \ad_d, currentAdD[voice], \vel_amp, currentVelAmp[voice] ], target: pg); voices[voice].run(true); voiceRunning[voice] = false; this.updateDryRun(voice); }, { if (voices[voice].notNil, { voices[voice].free; }); scaleType = currentPitchRandomScale[voice] ? 0; currentParams = Dictionary.newFrom([\speed, currentSpeed[voice] ? 0.1,\jitter, currentJitter[voice] ? 0.25,\size, currentSize[voice] ? 0.1,\density, currentDensity[voice] ? 10,\pitch_offset, currentPitch[voice] ? 1,\pan, currentPan[voice] ? 0,\gain, currentVolume[voice] ? 1,\granular_gain, currentGranularGain[voice] ? 1,\cutoff, currentCutoff[voice] ? 20000,\lpf_gain, currentlpf_gain[voice] ? 0.95,\hpf, currentHpf[voice] ? 20,\subharmonics_1, currentSubharmonics1[voice] ? 0,\subharmonics_2, currentSubharmonics2[voice] ? 0,\subharmonics_3, currentSubharmonics3[voice] ? 0,\overtones_1, currentOvertones1[voice] ? 0,\overtones_2, currentOvertones2[voice] ? 0,\pitch_mode, currentPitchMode[voice] ? 0,\direction_mod, currentDirectionMod[voice] ? 0,\size_variation, currentSizeVariation[voice] ? 0,\amp_randomize, currentAmpRandomize[voice] ? 0,\smoothbass, currentSmoothbass[voice] ? 1,\low_gain, currentLowGain[voice] ? 0,\mid_gain, currentMidGain[voice] ? 0,\high_gain, currentHighGain[voice] ? 0,\probability, currentProbability[voice] ? 100, \pitch_lag, currentPitchLag[voice] ? 0,\density_mod_amt, currentDensityModAmt[voice] ? 0,\pitch_random_prob, currentPitchRandomProb[voice] ? 0,\pitch_random_scale_buf, pitchScaleBuffers[scaleType].bufnum,\pitch_random_scale_len, pitchScaleLengths[scaleType],\ratcheting_prob, currentRatchetingProb[voice] ? 0, \key_hold, currentKeyHold[voice], \key_gate, currentKeyGate[voice], \ad_a, currentAdA[voice], \ad_d, currentAdD[voice], \vel_amp, currentVelAmp[voice]]); voices[voice] = Synth.new(\synth1, [ \out, voiceBuses[voice].index, \buf_l, buffersL[voice], \buf_r, buffersR[voice], \voice, voice, \is_stereo, voiceIsStereo[voice], \amp_bus, voiceAmpBuses[voice].index ] ++ currentParams.getPairs, target: pg); voices[voice].set(\t_reset_pos, 1); drySynths[voice].set(\buf_l, buffersL[voice], \buf_r, buffersR[voice], \pan, currentPan[voice] ? 0, \speed, currentSpeed[voice] ? 0.1, \granular_gain, currentGranularGain[voice] ? 1, \rec_pos_bus, -1, \t_reset_pos, 1); voiceRunning[voice] = true; this.updateDryRun(voice); }); });
        this.addCommand("isMono", "ii", { arg msg; var voice = msg[1] - 1; voices[voice].set(\isMono, msg[2]); });
        this.addCommand("live_mono", "ii", { arg msg; var voice = msg[1] - 1; var mono = msg[2]; if(liveInputRecorders[voice].notNil, { liveInputRecorders[voice].set(\isMono, mono); }); if(voicesUsingLiveBuffer[voice] && voices[voice].notNil, { voices[voice].set(\is_stereo, 1 - mono); voiceIsStereo[voice] = 1 - mono; }); });
        this.addCommand("unload_all", "", { this.unloadAll(); });
        this.addCommand("pause_voice", "i", { arg msg; var voice = msg[1] - 1; if(voices[voice].notNil, { voices[voice].set(\buf_l, silentBuffer, \buf_r, silentBuffer, \is_stereo, 0, \t_reset_pos, 1); voices[voice].run(false); drySynths[voice].set(\buf_l, silentBuffer, \buf_r, silentBuffer, \t_reset_pos, 1); voiceRunning[voice] = false; this.updateDryRun(voice); }); });
        this.addCommand("run_voice", "ii", { arg msg; var voice = msg[1] - 1; var on = msg[2]; if(voices[voice].notNil, { if(on == 1, { voices[voice].set(\t_reset_pos, 1); voices[voice].run(true); drySynths[voice].set(\t_reset_pos, 1); voiceRunning[voice] = true; }, { voices[voice].run(false); voiceRunning[voice] = false; }); this.updateDryRun(voice); }); });
        this.addCommand("save_live_buffer", "is", { arg msg; var voice = msg[1] - 1; var filename = msg[2]; this.saveLiveBufferToTape(voice, filename); });
        this.addCommand("bounce", "ifsif", { arg msg; this.bounce(msg[1], msg[2], msg[3].asString, msg[4], msg[5]); });
        this.addCommand("live_buffer_length","f",{ arg msg; var length=msg[1],myGeneration; liveBufferAllocGeneration=liveBufferAllocGeneration+1; myGeneration=liveBufferAllocGeneration; fork{ var newBufsL=Array.fill(2,{Buffer.alloc(context.server,(context.server.sampleRate*length).round.asInteger)}),newBufsR=Array.fill(2,{Buffer.alloc(context.server,(context.server.sampleRate*length).round.asInteger)}); context.server.sync; if(myGeneration==liveBufferAllocGeneration,{ var oldBufsL=liveInputBuffersL,oldBufsR=liveInputBuffersR; liveInputBuffersL=newBufsL; liveInputBuffersR=newBufsR; liveInputRecorders.do({ arg recorder,i; if(recorder.notNil,{ recorder.free; liveRecPosBuses[i].set(-1.0); liveInputRecorders[i]=Synth.new(\liveInputRecorder,[\bufL,liveInputBuffersL[i],\bufR,liveInputBuffersR[i],\mix,liveBufferMix,\voice,i,\recPosBus,liveRecPosBuses[i].index],context.xg,'addToHead'); voices[i].set(\buf_l,liveInputBuffersL[i],\buf_r,liveInputBuffersR[i],\rec_pos_bus,liveRecPosBuses[i].index,\t_reset_pos,1); drySynths[i].set(\buf_l,liveInputBuffersL[i],\buf_r,liveInputBuffersR[i],\rec_pos_bus,liveRecPosBuses[i].index,\t_reset_pos,1);},{ if(voicesUsingLiveBuffer[i] && voices[i].notNil,{ voices[i].set(\buf_l,liveInputBuffersL[i],\buf_r,liveInputBuffersR[i],\t_reset_pos,1); drySynths[i].set(\buf_l,liveInputBuffersL[i],\buf_r,liveInputBuffersR[i],\t_reset_pos,1); }); }); });oldBufsL.do({ arg buf; if(buf.notNil,{buf.free})}); oldBufsR.do({ arg buf; if(buf.notNil,{buf.free})});},{ newBufsL.do({ arg buf; if(buf.notNil,{buf.free})}); newBufsR.do({ arg buf; if(buf.notNil,{buf.free})});});};});

        o = OSCFunc({ |msg| var voice = msg[3].asInteger; nornsAddr.sendMsg("/twins/buf_pos", voice, msg[4]); nornsAddr.sendMsg("/twins/voice_peak", voice, msg[5], msg[6]);}, '/voice_state', context.server.addr);
        o_rec = OSCFunc({ |msg| nornsAddr.sendMsg("/twins/rec_pos", msg[3].asInteger, msg[4]); }, '/rec_pos', context.server.addr);
        o_grain = OSCFunc({ |msg| nornsAddr.sendMsg("/twins/grain_pos", msg[3].asInteger, msg[4], msg[5], msg[6]); }, '/grain_pos', context.server.addr);
        o_voice_peak = OSCFunc({ |msg| nornsAddr.sendMsg("/twins/voice_peak", msg[3].asInteger, msg[4], msg[5]); }, '/voice_peak', context.server.addr);
        o_delayduck = OSCFunc({ |msg| nornsAddr.sendMsg("/twins/delay_duck", msg[3]); }, '/delay_duck', context.server.addr);
    }

updateFilterRun { arg voice; filterSynths[voice].run((currentCutoff[voice] < 20000) || (currentHpf[voice] > 20)); }
updateEqRun { arg voice; eqSynths[voice].run((currentLowGain[voice] != 0) || (currentMidGain[voice] != 0) || (currentHighGain[voice] != 0)); }
updateDryRun { arg voice; drySynths[voice].run(voiceRunning[voice] && (currentGranularGain[voice] < 1)); }

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
        if (o_voice_peak.notNil) { o_voice_peak.free; o_voice_peak = nil; };
        if (o_delayduck.notNil) { o_delayduck.free; o_delayduck = nil; };
        if (wobbleBuffer.notNil) { wobbleBuffer.free; wobbleBuffer = nil; };
        if (glitchBuffer.notNil) { glitchBuffer.free; glitchBuffer = nil; };
        if (silentBuffer.notNil) { silentBuffer.free; silentBuffer = nil; };
        if (filterSynths.notNil) { filterSynths.do({ arg s; if (s.notNil) { s.free; }; }); filterSynths = nil; };
        if (eqSynths.notNil) { eqSynths.do({ arg s; if (s.notNil) { s.free; }; }); eqSynths = nil; };
        if (filterRouters.notNil) { filterRouters.do({ arg s; if (s.notNil) { s.free; }; }); filterRouters = nil; };
        if (voiceBuses.notNil) { voiceBuses.do({ arg b; if (b.notNil) { b.free; }; }); voiceBuses = nil; };
        if (bufSine.notNil) { bufSine.free; bufSine = nil; };
        if (bitcrushEffect.notNil) { bitcrushEffect.free; bitcrushEffect = nil; };
        if (shimmerEffect.notNil) { shimmerEffect.free; shimmerEffect = nil; };
        if (analogDriveEffect.notNil) { analogDriveEffect.free; analogDriveEffect = nil; };
        if (resonatorEffect.notNil) { resonatorEffect.free; resonatorEffect = nil; };
        if (wavefoldEffect.notNil) { wavefoldEffect.free; wavefoldEffect = nil; };
        if (ringmodEffect.notNil) { ringmodEffect.free; ringmodEffect = nil; };
        if (tapeEffect.notNil) { tapeEffect.free; tapeEffect = nil; };
        if (chewEffect.notNil) { chewEffect.free; chewEffect = nil; };
        if (widthEffect.notNil) { widthEffect.free; widthEffect = nil; };
        if (monobassEffect.notNil) { monobassEffect.free; monobassEffect = nil; };
        if (lossdegradeEffect.notNil) { lossdegradeEffect.free; lossdegradeEffect = nil; };
        if (sineEffect.notNil) { sineEffect.free; sineEffect = nil; };
        if (wobbleEffect.notNil) { wobbleEffect.free; wobbleEffect = nil; };
        if (glitchEffect.notNil) { glitchEffect.free; glitchEffect = nil; };
        if (delayEffect.notNil) { delayEffect.free; delayEffect = nil; };
        if (drySynths.notNil) { drySynths.do({ arg s; if (s.notNil) { s.free; }; }); drySynths = nil; };
        if (dryGroup.notNil) { dryGroup.free; dryGroup = nil; };
        if (voiceAmpBuses.notNil) { voiceAmpBuses.do({ arg b; if (b.notNil) { b.free; }; }); voiceAmpBuses = nil; };
        if (rotateEffect.notNil) { rotateEffect.free; rotateEffect = nil; };
        if (haasEffect.notNil) { haasEffect.free; haasEffect = nil; };
        if (dimensionEffect.notNil) { dimensionEffect.free; dimensionEffect = nil; };
    }
}