Engine_twins : CroneEngine {

var analogDriveEffect, dimensionEffect, haasEffect, bitcrushEffect, resonatorEffect, wavefoldEffect, ringmodEffect, delayEffect, shimmerEffect, tapeEffect, chewEffect, widthEffect, monobassEffect, sineEffect, wobbleEffect, lossdegradeEffect, rotateEffect, glitchEffect, stChorusEffect, reelEffect, ottEffect, genlossEffect, fuzzEffect, subEffect, spiralEffect, spiralBuffer, <silentBuffer, <buffersL, <buffersR, wobbleBuffer, glitchBuffer, <voices, bufSine, pg, <liveInputBuffersL, <liveInputBuffersR, <liveInputRecorders, <liveRecPosBuses, o, o_rec, o_voice_peak, o_delayduck, liveBufferAllocGeneration = 0, grainEnvs, pitchScaleBuffers, pitchScaleLengths, nornsAddr, voicesUsingLiveBuffer, currentSpeed, currentJitter, currentSize, currentDensity, currentDensityModAmt, currentPitch, currentPan, currentSpread, currentVolume, currentGranularGain, currentCutoff, currentHpf, currentlpf_gain, currentSubharmonics1, currentSubharmonics2, currentSubharmonics3, currentOvertones1, currentOvertones2, currentPitchMode, currentDirectionMod, currentSizeVariation, currentSmoothbass, currentLowGain, currentMidGain, currentHighGain, currentTiltGain, currentProbability, liveBufferMix = 1.0, currentPitchRandomProb, currentPitchRandomScale, currentRatchetingProb, currentPitchLag, currentGlitchRatio = 0.0, currentGlitchMix = 0.0, currentKeyHold, currentKeyGate, currentAdA, currentAdD, currentVelAmp, currentAmpRandomize, voiceBuses, filterSynths, filterRouters, eqSynths, tiltSynths, dryGroup, drySynths, voiceAmpBuses, voiceRunning, voiceIsStereo, bounceTracks, vibeEffect, normOnLoad = 0, loadGen, loadPath, loadBusy, filePeak, rateScale, filterOn, filterTok, meterBuses, lastPos, seekPos, dryOn, inMono, currentEnvSelect, fxTok, limiterEffect;

classvar pitchScales;
*initClass {pitchScales = [[7, 12], [7, 12, 19, 24], [12], [12, 24], [1,2,3,4,5,6,7,8,9,10,11], [2,4,5,7,9,11], [2,3,5,7,8,10], [2,4,7,9], [2,4,6,8,10]];}
*new { arg context, doneCallback; ^super.new(context, doneCallback); }

readBuf { arg i, path; path = path.asString; if(File.exists(path), { loadGen[i] = loadGen[i] + 1; loadPath[i] = path; if(loadBusy[i].not, { this.loadLoop(i) }); }); }

cancelLoad { arg i; loadGen[i] = loadGen[i] + 1; loadPath[i] = nil; }

freePair { arg l, r; if(l !== silentBuffer, { l.free }); if((r !== l) && (r !== silentBuffer), { r.free }); }

normGain { arg i; ^if(normOnLoad == 1, { 0.5012 / filePeak[i].max(0.001) }, { 1 }) }

silence { arg i; voices[i].set(\buf_l, silentBuffer, \buf_r, silentBuffer, \is_stereo, 0, \t_reset_pos, 1); voices[i].run(false); drySynths[i].set(\buf_l, silentBuffer, \buf_r, silentBuffer, \t_reset_pos, 1); voiceRunning[i] = false; this.updateDryRun(i); }

releaseVoice { arg i; this.silence(i); this.freePair(buffersL[i], buffersR[i]); buffersL[i] = silentBuffer; buffersR[i] = silentBuffer; }

loadLoop { arg i; loadBusy[i] = true; fork { while({ loadPath[i].notNil }, { { this.loadFile(i, loadPath[i], loadGen[i]) }.try({ arg e; e.reportError; loadPath[i] = nil; }); }); loadBusy[i] = false; }; }

loadFile { arg i, path, gen;
        var s = context.server, sf = SoundFile.openRead(path), cols = 30, pos = 0, ok = true, ch, n, sr, bl, br, peaks, full, next;
        loadPath[i] = nil;
        if(sf.isNil, { ^nil });
        ch = sf.numChannels.max(1); n = sf.numFrames.min(16777216); sr = sf.sampleRate;
        if((n < 1) || (gen != loadGen[i]), { sf.close; ^nil });
        if(sr <= 0, { sr = s.sampleRate });
        if((n * ch) > 8388608, { this.releaseVoice(i) });
        bl = Buffer.alloc(s, n, 1); br = if(ch > 1, { Buffer.alloc(s, n, 1) }, { bl });
        peaks = Array.fill(cols, 0); full = Signal.newClear(65536 * ch);
        while({ ok && (pos < n) }, {
            next = (pos + 1048576).min(n);
            s.sendMsg("/b_readChannel", bl.bufnum, path, pos, next - pos, pos, 0, 0);
            if(ch > 1, { s.sendMsg("/b_readChannel", br.bufnum, path, pos, next - pos, pos, 0, 1) });
            sf.seek(pos, 0);
            while({ pos < next }, { var c = pos * cols div: n, k = ((n * (c + 1) div: cols).min(next) - pos).clip(1, 65536), d = if(k == 65536, { full }, { Signal.newClear(k * ch) }); sf.readData(d); peaks[c] = peaks[c].max(d.peak); pos = pos + k; });
            s.sync; ok = gen == loadGen[i];
        });
        sf.close;
        if(ok, { this.installBuf(i, bl, br, ch, sr, n, peaks) }, { this.freePair(bl, br) });
}

installBuf { arg i, bl, br, ch, sr, n, peaks; var oldL = buffersL[i], oldR = buffersR[i], st = (ch > 1).binaryValue, g; buffersL[i] = bl; buffersR[i] = br; filePeak[i] = peaks.maxItem; rateScale[i] = sr / context.server.sampleRate; voiceIsStereo[i] = st; voicesUsingLiveBuffer[i] = false; g = this.normGain(i); voices[i].set(\buf_l, bl, \buf_r, br, \is_stereo, st, \norm, g, \rscale, rateScale[i], \t_reset_pos, 1); voices[i].run(true); drySynths[i].set(\buf_l, bl, \buf_r, br, \norm, g, \rscale, rateScale[i], \t_reset_pos, 1); voiceRunning[i] = true; lastPos[i] = seekPos[i]; this.updateDryRun(i); this.freePair(oldL, oldR); nornsAddr.sendMsg(*(["/twins/waveform", i] ++ peaks)); nornsAddr.sendMsg("/twins/duration", i, n / sr); }

unloadAll { 2.do({ arg i; this.cancelLoad(i) }); fork { 2.do({ arg i; voiceIsStereo[i] = 0; voicesUsingLiveBuffer[i] = false; this.releaseVoice(i); liveInputBuffersL[i].zero; liveInputBuffersR[i].zero; if(liveInputRecorders[i].notNil, { liveInputRecorders[i].free; liveInputRecorders[i] = nil; }); }); wobbleBuffer.zero; glitchBuffer.zero; }; }

saveLiveBufferToTape { arg voice, filename; var dir = "/home/we/dust/audio/tape/twins/", path = dir ++ filename, bufL = liveInputBuffersL[voice], bufR = liveInputBuffersR[voice]; fork { var interleaved = Buffer.alloc(context.server, bufL.numFrames, 2); File.mkdir(dir); context.server.sync; Synth.new(\bufInterleave, [\bufL, bufL, \bufR, bufR, \outBuf, interleaved], context.xg, 'addToTail'); ((bufL.numFrames / context.server.sampleRate) + 0.2).wait; interleaved.write(path, "WAV", "float"); context.server.sync; interleaved.free; nornsAddr.sendMsg("/twins/save_complete", voice); }; }

restorePos { arg syn, voice; fork { 0.05.wait; syn.set(\pos, seekPos[voice]) }; }

resumeAt { arg syn, voice; syn.set(\pos, lastPos[voice], \t_reset_pos, 1); this.restorePos(syn, voice); }

fxRun { arg syn, on, tail = 0; var t = (fxTok[syn] ? 0) + 1; fxTok[syn] = t; if(on, { syn.set(\flush, 0); syn.run(true) }, { if(tail > 0, { syn.set(\flush, 1); fork { tail.wait; if(fxTok[syn] == t, { syn.run(false) }) } }, { syn.run(false) }) }); }

directOff { arg voice;
        var live = voicesUsingLiveBuffer[voice], bl = if(live, { liveInputBuffersL[voice] }, { buffersL[voice] }), br = if(live, { liveInputBuffersR[voice] }, { buffersR[voice] }), rp = if(live && liveInputRecorders[voice].notNil, { liveRecPosBuses[voice].index }, { -1 }), g = if(live, { 1 }, { this.normGain(voice) }), rs = if(live, { 1 }, { rateScale[voice] }), sc = currentPitchRandomScale[voice] ? 0, pr = currentPitchRandomProb[voice] ? 0;
        voices[voice] = Synth.new(\synth1, [\out, voiceBuses[voice].index, \buf_l, bl, \buf_r, br, \voice, voice, \is_stereo, voiceIsStereo[voice], \amp_bus, voiceAmpBuses[voice].index, \meter_bus, meterBuses[voice].index, \norm, g, \rscale, rs, \rec_pos_bus, rp, \speed, currentSpeed[voice], \jitter, currentJitter[voice] * 0.5, \size, currentSize[voice], \density, currentDensity[voice], \pitch_offset, currentPitch[voice], \pan, currentPan[voice], \spread, currentSpread[voice], \gain, currentVolume[voice], \granular_gain, currentGranularGain[voice], \subharmonics_1, currentSubharmonics1[voice], \subharmonics_2, currentSubharmonics2[voice], \subharmonics_3, currentSubharmonics3[voice], \overtones_1, currentOvertones1[voice], \overtones_2, currentOvertones2[voice], \pitch_mode, currentPitchMode[voice], \direction_mod, currentDirectionMod[voice], \size_variation, currentSizeVariation[voice], \amp_randomize, currentAmpRandomize[voice], \smoothbass, currentSmoothbass[voice], \probability, currentProbability[voice], \pitch_lag_time, currentPitchLag[voice], \density_mod_amt, currentDensityModAmt[voice], \env_select, currentEnvSelect[voice], \pitch_random_prob, pr.abs * 0.01, \pitch_random_direction, pr.sign, \pitch_random_scale_buf, pitchScaleBuffers[sc].bufnum, \pitch_random_scale_len, pitchScaleLengths[sc], \ratcheting_prob, currentRatchetingProb[voice], \key_hold, currentKeyHold[voice], \key_gate, currentKeyGate[voice], \ad_a, currentAdA[voice], \ad_d, currentAdD[voice], \vel_amp, currentVelAmp[voice], \pos, lastPos[voice], \t_reset_pos, 1], target: pg);
        this.restorePos(voices[voice], voice);
        drySynths[voice].set(\buf_l, bl, \buf_r, br, \pan, currentPan[voice], \speed, currentSpeed[voice], \granular_gain, currentGranularGain[voice], \rec_pos_bus, rp, \norm, g, \rscale, rs);
        voiceRunning[voice] = true; this.updateDryRun(voice);
}

bounce { arg mode, dur, name, pre = 0, xf = 0; fork { var dir = "/home/we/dust/audio/tape/twins/"; var comp = { arg v; if(pre == 1, { (currentVolume[v] ? 1).max(1e-4).reciprocal }, { 1 }) }; var recs = case { mode == 2 } { [[voiceBuses[0].index, voiceBuses[0].index, comp.(0), 0], [voiceBuses[1].index, voiceBuses[1].index, comp.(1), 0]] } { mode == 1 } { [[context.out_b.index, context.out_b.index, 1, 0]] } { [[voiceBuses[0].index, voiceBuses[1].index, comp.(0), comp.(1)]] }; var n = recs.size; var frames = (context.server.sampleRate * dur).round.asInteger; var bufs = Array.fill(n, { Buffer.alloc(context.server, frames, 2) }); var suffix = if(n == 2, { ["_1", "_2"] }, { [""] }); var paths = Array.fill(n, { arg i; dir ++ name ++ suffix[i] ++ ".wav" }); var synths; File.mkdir(dir); context.server.sync; synths = Array.fill(n, { arg i; var r = recs[i]; Synth.new(\bounceRec, [\buf, bufs[i], \bus1, r[0], \bus2, r[1], \c1, r[2], \c2, r[3], \xf, xf], context.xg, 'addToTail'); }); if(pre == 1, { bounceTracks = if(mode == 2, { [[synths[0], \c1], [synths[1], \c1]] }, { [[synths[0], \c1], [synths[0], \c2]] }); }); (dur + xf.clip(0.005, dur) + 0.2).wait; bounceTracks = nil; n.do({ arg i; bufs[i].write(paths[i], "WAV", "float"); }); context.server.sync; synths.do(_.free); bufs.do(_.free); nornsAddr.sendMsg("/twins/bounce_done", mode); }; }

alloc {
        var t9dub = { arg x, f, amt, k1, k2; var d = x - OnePole.ar(x, 1 - f), h = (Delay1.ar(d) * (k2 / k1) + d).clip2(1 / k1), m = h.abs; x + (h * OnePole.ar(m / log(m * (255 * k1) + 1).max(1e-9), 1 - f) * (amt * (2.40823997 * k1 * k1))) };
        var csoft = { arg v; var c = v.clip2(1); c * (c.squared * -0.5 + 1.5) }, tri = { arg d; 1 - ((d - 2048).abs * 0.00048828125) };
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

        bufSine = Buffer.alloc(context.server, 4096, 1);
        bufSine.sine2([2], [0.5], false);
        wobbleBuffer = Buffer.alloc(context.server, context.server.sampleRate * 5, 2);
        spiralBuffer = Buffer.alloc(context.server, context.server.sampleRate * 3, 2);
        glitchBuffer = Buffer.alloc(context.server, context.server.sampleRate * 10, 2);
        silentBuffer = Buffer.alloc(context.server, context.server.sampleRate.asInteger);
        voiceBuses = Array.fill(2, { Bus.audio(context.server, 2); });
        voiceAmpBuses = Array.fill(2, { Bus.control(context.server, 1); });
        meterBuses = Array.fill(2, { Bus.control(context.server, 2); });
        voiceRunning = Array.fill(2, { false });
        lastPos = [0, 0]; seekPos = [0, 0]; dryOn = [false, false]; inMono = [0, 0]; currentEnvSelect = [0, 0]; fxTok = IdentityDictionary.new;

        grainEnvs = [
            Env.new([0, 1, 1, 0], [0.15, 0.7, 0.15], [4, 0, -4]),
            Env.perc(0.01, 0.99, 1, -4),
            Env.adsr(0.25, 0.15, 0.65, 1, 1, -4, 0)
        ].collect { |env| Buffer.sendCollection(context.server, env.discretize) };

        pitchScaleBuffers = pitchScales.collect { |scale| Buffer.sendCollection(context.server, scale, 1) };
        pitchScaleLengths = pitchScales.collect(_.size);

        currentSpeed = [0.1, 0.1]; currentJitter = [0.25, 0.25]; currentSize = [0.1, 0.1]; currentDensity = [10, 10]; currentPitch = [1, 1]; currentPan = [0, 0]; currentSpread = [0, 0]; currentVolume = [1, 1]; currentGranularGain = [1, 1]; currentCutoff = [20000, 20000]; currentlpf_gain = [0.95, 0.95]; currentHpf = [20, 20]; currentSubharmonics1 = [0, 0]; currentSubharmonics2 = [0, 0]; currentSubharmonics3 = [0, 0]; currentOvertones1 = [0, 0]; currentOvertones2 = [0, 0]; currentPitchMode = [0, 0]; currentDirectionMod = [0, 0]; currentSizeVariation = [0, 0]; currentSmoothbass = [1, 1]; currentDensityModAmt = [0, 0]; currentLowGain = [0, 0]; currentMidGain = [0, 0]; currentHighGain = [0, 0]; currentTiltGain = [0, 0]; currentProbability = [100, 100]; currentPitchRandomProb = [0, 0]; currentPitchRandomScale = [0, 0]; currentRatchetingProb = [0, 0]; currentPitchLag = [0, 0];
        loadGen = [0, 0]; loadPath = [nil, nil]; loadBusy = [false, false]; filePeak = [1, 1]; rateScale = [1, 1]; filterOn = [false, false]; filterTok = [0, 0]; currentKeyHold = [1, 1]; currentKeyGate = [0, 0]; currentAdA = [0.005, 0.005]; currentAdD = [0.3, 0.3]; currentVelAmp = [1, 1]; currentAmpRandomize = [0, 0];

        context.server.sync;

        SynthDef(\synth1, {
            arg out, voice, buf_l, buf_r, pos, speed, jitter, size, density, density_mod_amt, pitch_offset, pan, spread, gain, t_reset_pos, granular_gain, pitch_mode, subharmonics_1, subharmonics_2, subharmonics_3, overtones_1, overtones_2, direction_mod, size_variation, smoothbass, probability, env_select = 0, pitch_random_prob=0, pitch_random_scale_buf=0, pitch_random_scale_len=1, pitch_random_direction=1, ratcheting_prob=0, pitch_lag_time, rec_pos_bus = -1, key_hold = 1, key_gate = 0, ad_a = 0.005, ad_d = 0.3, vel_amp = 1, t_key_trig = 0, amp_bus, amp_randomize = 0, is_stereo = 0, norm = 1, rscale = 1, meter_bus = 0;
            var grain_trig, grain_rate, jitter_sig, buf_pos, sig_mix, density_mod, granular_sig, base_pitch, grain_pitch, grain_size, key_env, amp_scale, dmod_half, grain_amp_rand;
            var base_trig, grain_count, conc, keep_main, keep_sub, htrig, vtrig, meter;
            var main_vol = 1 / (1 + subharmonics_1 + subharmonics_2 + subharmonics_3 + overtones_1 + overtones_2);
            var subharmonic_1_vol = subharmonics_1 * main_vol * 2;
            var subharmonic_2_vol = subharmonics_2 * main_vol * 2;
            var subharmonic_3_vol = subharmonics_3 * main_vol * 2;
            var overtone_1_vol = overtones_1 * main_vol * 1.5;
            var overtone_2_vol = overtones_2 * main_vol * 1.5;
            var report_trig = Impulse.kr(30);
            var grain_direction, speed_dir, base_grain_trig, rand_val, rand_val2, random_interval, ratchet_gate, extra_trig, signal, envBuf, randomEnv, harmonics, volumes, l_harmonics, r_harmonics, size_mults, jitter_range, buf_frames_l, buf_dur_recip, wrapped_grain_pos;
            var spreadMults, stereoSpreadMults, haasOffsets, detuneCents, density_phase, pan_u_l, pan_u_r, pan_flip, pan_alt, pan_dist_l, pan_dist_r, spread_lag, g_mid, g_side, report_lo, report_hi, report_lo_r, report_hi_r, report_pan;
            speed = Lag.kr(speed, 1);
            dmod_half = density_mod_amt * 0.5;
            density_mod = density * (2 ** LFNoise1.kr(density, dmod_half, dmod_half));
            density_phase = Phasor.kr(trig: t_key_trig, rate: density_mod / ControlRate.ir, start: 0, end: 1, resetPos: 0);
            base_trig = HPZ1.kr(density_phase) < 0;
            ratchet_gate = CoinGate.kr(ratcheting_prob, base_trig);
            extra_trig = TDelay.kr(ratchet_gate, density_mod.reciprocal * 0.5, 2.0);
            base_grain_trig = base_trig + extra_trig;
            key_env = EnvGen.kr(Env.asr(ad_a, 1, ad_d, \sin), gate: key_gate.max(key_hold));
            grain_trig = (CoinGate.kr(probability, base_grain_trig) * (key_env > 0.0001)) + t_key_trig;
            rand_val = TRand.kr(trig: grain_trig, lo: 0, hi: 1);
            rand_val2 = TRand.kr(trig: grain_trig, lo: 0, hi: 1);
            grain_amp_rand = 1 - (amp_randomize * TRand.kr(trig: grain_trig, lo: 0, hi: 1));
            grain_size = size * (1 + TRand.kr(trig: grain_trig, lo: size_variation.neg, hi: size_variation));
            speed_dir = Select.kr(pitch_mode, [1, Select.kr(speed.abs > 0.001, [1, speed.sign])]);
            grain_direction = speed_dir * Select.kr((rand_val < direction_mod), [1, -1]);
            buf_frames_l = BufFrames.kr(buf_l);
            buf_dur_recip = SampleRate.ir / buf_frames_l * rscale;
            jitter_range = buf_dur_recip * jitter;
            jitter_sig = TRand.kr(trig: grain_trig, lo: jitter_range.neg, hi: jitter_range);
            buf_pos = Phasor.kr(trig: t_reset_pos, rate: buf_dur_recip / ControlRate.ir * speed, start: 0, end: 1, resetPos: pos);

            base_pitch = Select.kr(pitch_mode, [speed * pitch_offset, pitch_offset]);
            grain_pitch = Lag.kr(base_pitch, pitch_lag_time);
            random_interval = BufRd.kr(1, pitch_random_scale_buf, TIRand.kr(0, pitch_random_scale_len - 1, grain_trig));
            grain_pitch = grain_pitch * (((rand_val2 < pitch_random_prob) * random_interval * pitch_random_direction).midiratio);
            grain_rate = grain_pitch * rscale;
            randomEnv = TIRand.kr(0, 2, grain_trig);
            envBuf = Select.kr(env_select, [-1] ++ grainEnvs ++ [Select.kr(randomEnv, grainEnvs)]);
            harmonics   = [1, 1/2, 1/4, 1/8, 2, 4];
            volumes     = [main_vol, subharmonic_1_vol, subharmonic_2_vol, subharmonic_3_vol, overtone_1_vol, overtone_2_vol];
            size_mults  = [1, smoothbass, smoothbass, smoothbass, 1, 1];
            spreadMults = [1.0, 0.5, 0.25, 0.0, 1.0, 1.0];
            stereoSpreadMults = [1.0, 0.6, 0.3, 0.0, 1.0, 1.0];
            haasOffsets = [0.0015, 0.006, 0.0005, 0.0, 0.003, 0.005];
            detuneCents = [0.0, 0.0, 0.0, 0.0, 2.0, 3.0];
            pan_u_l = TRand.kr(trig: grain_trig, lo: -1, hi: 1);
            pan_u_r = TRand.kr(trig: grain_trig, lo: -1, hi: 1);
            pan_flip = (ToggleFF.kr(grain_trig) * 2) - 1;
            pan_alt = spread * spread * 0.7;
            pan_dist_l = (pan_u_l.sign * pan_u_l.abs.sqrt * (1 - pan_alt)) + (pan_flip * pan_alt);
            pan_dist_r = (pan_u_r.sign * pan_u_r.abs.sqrt * (1 - pan_alt)) + (pan_flip * pan_alt);
            report_lo = Select.kr(is_stereo, [spread.neg, -1.0]);
            report_hi = Select.kr(is_stereo, [spread, (2 * spread) - 1]);
            report_lo_r = Select.kr(is_stereo, [spread.neg, 1 - (2 * spread)]);
            report_hi_r = Select.kr(is_stereo, [spread, 1.0]);
            report_pan = (pan + (((((((report_lo + report_hi) * 0.5) + (((report_hi - report_lo) * 0.5) * pan_dist_l)) + (((report_lo_r + report_hi_r) * 0.5) + (((report_hi_r - report_lo_r) * 0.5) * pan_dist_r))) * 0.5) * (1 - pan.abs)))).clip(-1.0, 1.0);
            conc = density_mod * size * (1 + size_variation) * (1 + ratcheting_prob);
            keep_main = (56 / conc.max(1e-3)).min(1);
            keep_sub = (56 / (conc * smoothbass).max(1e-3)).min(1);
            htrig = [keep_main, keep_sub, keep_sub, keep_sub, keep_main, keep_main].collect { |k, i| CoinGate.kr(k, grain_trig * (granular_gain > 0)) * (volumes[i] > 0) };
            vtrig = htrig[0];
            l_harmonics = harmonics.collect { |harmonic, i|
                var harmonic_spread = spread * spreadMults[i];
                var sm = stereoSpreadMults[i];
                var pan_lo = Select.kr(is_stereo, [harmonic_spread.neg, sm.neg]);
                var pan_hi = Select.kr(is_stereo, [harmonic_spread, sm * ((2 * spread) - 1)]);
                var pan_c = (pan_lo + pan_hi) * 0.5;
                var pan_h = (pan_hi - pan_lo) * 0.5;
                var hd = haasOffsets[i] * spread;
                var trig_l = Select.kr(hd > (0.5 / ControlRate.ir), [htrig[i], TDelay.kr(htrig[i], hd)]);
                var harmonic_pan = (pan + ((pan_c + (pan_h * pan_dist_l)) * (1 - pan.abs))).clip(-1.0, 1.0);
                GrainBuf.ar(numChannels: 2, trigger: trig_l, dur: grain_size * size_mults[i], sndbuf: buf_l, rate: grain_rate * harmonic * grain_direction, pos: buf_pos + jitter_sig, interp: 2, pan: harmonic_pan, envbufnum: envBuf, mul: volumes[i] * grain_amp_rand, maxGrains: 80);
            };
            r_harmonics = harmonics.collect { |harmonic, i|
                var detuneRatio = ((detuneCents[i] * spread) / 1200).midiratio;
                var harmonic_spread = spread * spreadMults[i];
                var sm = stereoSpreadMults[i];
                var pan_lo = Select.kr(is_stereo, [harmonic_spread.neg, sm * (1 - (2 * spread))]);
                var pan_hi = Select.kr(is_stereo, [harmonic_spread, sm]);
                var pan_c = (pan_lo + pan_hi) * 0.5;
                var pan_h = (pan_hi - pan_lo) * 0.5;
                var harmonic_pan = (pan + ((pan_c + (pan_h * pan_dist_r)) * (1 - pan.abs))).clip(-1.0, 1.0);
                GrainBuf.ar(numChannels: 2, trigger: htrig[i], dur: grain_size * size_mults[i], sndbuf: buf_r, rate: grain_rate * harmonic * grain_direction * detuneRatio, pos: buf_pos + jitter_sig, interp: 2, pan: harmonic_pan, envbufnum: envBuf, mul: volumes[i] * grain_amp_rand, maxGrains: 80);
            };
            granular_sig = (Mix.ar(l_harmonics) + Mix.ar(r_harmonics)) * norm;
            sig_mix = (granular_sig * granular_gain).tanh;
            spread_lag = Lag.kr(spread, 0.2);
            g_mid = (sig_mix[0] + sig_mix[1]) * 0.5;
            g_side = (sig_mix[0] - sig_mix[1]) * 0.5 * (1 + (spread_lag * 0.5));
            sig_mix = [g_mid + g_side, g_mid - g_side];
            amp_scale = Lag.kr(gain) * key_env * vel_amp;
            signal = sig_mix * amp_scale;
            Out.kr(amp_bus, amp_scale);
            wrapped_grain_pos = Wrap.kr(buf_pos + jitter_sig);
            grain_count = PulseCount.kr(vtrig);
            meter = In.kr(meter_bus, 2);
            SendReply.kr(report_trig, '/voice_state', [voice, buf_pos, meter[0], meter[1], grain_count, Latch.kr(wrapped_grain_pos, vtrig), Latch.kr(grain_size, vtrig), Latch.kr(rand_val, vtrig), Latch.kr(grain_pitch.abs, vtrig), Latch.kr(report_pan, vtrig)]);
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

        SynthDef(\voicetilt, {
            arg bus, tilt = 0;
            var sig = In.ar(bus, 2);
            var g = Lag.kr(tilt, 0.05);
            sig = BLowShelf.ar(sig, 800, 1, g.neg);
            sig = BHiShelf.ar(sig, 800, 1, g);
            ReplaceOut.ar(bus, sig);
        }).add;

        SynthDef(\voicefilter, {
            arg bus, cutoff = 20000, hpf = 20, lpf_gain = 0.95, on = 0;
            var dry = In.ar(bus, 2);
            var lagcutoff = Lag.kr(cutoff.max(20).log, 0.08).exp;
            var sig = MoogFF.ar(HPF.ar(dry, hpf), lagcutoff, lpf_gain);
            ReplaceOut.ar(bus, (sig - dry) * Lag.kr(on, 0.03) + dry);
        }).add;

        SynthDef(\voicerouter, {
            arg in, out, meter;
            var sig = In.ar(in, 2);
            Out.kr(meter, Amplitude.kr(sig, 0.002, 0.12));
            Out.ar(out, sig);
        }).add;

        SynthDef(\drysynth, {
            arg out, buf_l, buf_r, pos = 0, speed = 1, pan = 0, granular_gain = 1, t_reset_pos = 0, rec_pos_bus = -1, amp_bus, norm = 1, rscale = 1;
            var buf_frames_l = BufFrames.kr(buf_l);
            var lagged_speed = Lag.kr(speed, 1);
            var buf_dur_recip = SampleRate.ir / buf_frames_l * rscale;
            var buf_pos = Phasor.kr(trig: t_reset_pos, rate: buf_dur_recip / ControlRate.ir * lagged_speed, start: 0, end: 1, resetPos: pos);
            var dry_seek_trig     = K2A.ar(t_reset_pos);
            var dry_mute_env      = EnvGen.ar(Env([0, 1, 1, 0], [0.015, 0.005, 0.020], \sin), gate: dry_seek_trig);
            var dry_seek_fade     = 1.0 - dry_mute_env;
            var delayed_dry_reset = TDelay.ar(dry_seek_trig, 0.017);
            var dry_rate          = lagged_speed * rscale;
            var dry_sig = [PlayBuf.ar(1, buf_l, dry_rate, delayed_dry_reset, pos * buf_frames_l, 1), PlayBuf.ar(1, buf_r, dry_rate, delayed_dry_reset, pos * buf_frames_l, 1)] * dry_seek_fade;
            var recPos = In.kr(rec_pos_bus.max(0));
            var diff = (buf_pos - recPos.max(0)).abs;
            var wrappedDist = diff.min(1.0 - diff);
            var fadeZoneNorm = (0.03 * SampleRate.ir) / buf_frames_l;
            var liveDryFade = (wrappedDist / fadeZoneNorm).clip(0, 1);
            var dryFade = Select.kr((rec_pos_bus >= 0), [1.0, liveDryFade]);
            var amp = In.kr(amp_bus);
            dry_sig = (dry_sig * (dryFade * norm)).tanh;
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
                \meter_bus, meterBuses[i].index,
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

        tiltSynths = Array.fill(2, { arg i;
            Synth.newPaused(\voicetilt, [
                \bus, voiceBuses[i].index,
                \tilt, currentTiltGain[i],
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
                \meter, meterBuses[i].index,
            ], context.xg, 'addToTail');
        });

        context.server.sync;

        SynthDef(\liveDirect, {
            arg out, pan, gain, isMono, voice, key_hold = 1, key_gate = 0, ad_a = 0.005, ad_d = 0.3, vel_amp = 1;
            var sig = SoundIn.ar([0, 1]);
            var report_trig = Impulse.kr(30);
            var key_env = EnvGen.kr(Env.asr(ad_a, 1, ad_d, \sin), gate: key_gate.max(key_hold));
            var peak_reset = Delay1.kr(report_trig);
            sig = Select.ar(isMono, [sig, [sig[0], sig[0]] ]);
            sig = Balance2.ar(sig[0], sig[1], pan);
            sig = (sig * Lag.kr(gain) * key_env * vel_amp).tanh;
            SendReply.kr(report_trig, '/voice_peak', [voice, Peak.kr(sig[0], peak_reset), Peak.kr(sig[1], peak_reset)]);
            Out.ar(out, sig);
        }).add;

        SynthDef(\liveInputRecorder, {
            arg bufL, bufR, isMono=0, mix, voice, recPosBus;
            var in = SoundIn.ar([0, 1]);
            var bufFrames = BufFrames.ir(bufL);
            var phasor = Phasor.ar(0, 1, 0, bufFrames);
            var oldL = BufRd.ar(1, bufL, phasor, interpolation: 1);
            var oldR = BufRd.ar(1, bufR, phasor, interpolation: 1);
            var mixedL, mixedR, normPos, tick;
            in = Select.ar(isMono, [in, [Mix.ar(in), Mix.ar(in)]]);
            mixedL = XFade2.ar(oldL, in[0], mix * 2 - 1);
            mixedR = XFade2.ar(oldR, in[1], mix * 2 - 1);
            BufWr.ar(mixedL, bufL, phasor);
            BufWr.ar(mixedR, bufR, phasor);
            normPos = phasor / bufFrames;
            Out.kr(recPosBus, A2K.kr(normPos));
            tick = Impulse.kr(30);
            SendReply.kr(tick, '/rec_pos', [voice, normPos, Peak.kr(mixedL.abs.max(mixedR.abs), Delay1.kr(tick))]);
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
            arg bus, mix=0.0, delay=0.5, fb_amt=0.3, dhpf=20, lpf=20000, w_rate=0.0, w_depth=0.0, stereo=0.2, duck_amt=0.0, flush=0;
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
            delayed = DelayC.ar((input + fb) * (1 - flush), 5, Lag.kr(delay, 0.7) + combinedMod);
            wet = Balance2.ar(delayed[0], delayed[1], (SinOsc.kr(delay.max(0.1).reciprocal * 0.5) + (LFNoise2.kr(0.4) * 0.3)) * (stereo * 0.77));
            LocalOut.ar(wet);
            dryAmp = Amplitude.kr(input.sum, 0.005, 0.05);
            duck = LagUD.kr((1 - (dryAmp.sqrt * duck_amt * 6).clip(0, 1)), 0.15, 0.02);
            SendReply.kr(Impulse.kr(20), '/delay_duck', [duck]);
            ReplaceOut.ar(bus, input + (wet * mix * 1.6 * duck));
        }).add;

        SynthDef(\shimmer, {
            arg bus, mix=0.0, lowpass1=13000, hipass1=1400, pitchv1=0.02, fb1=0.0, fbDelay1=0.15, shimmer_oct1=2, mod_mix=0, flush=0;
            var input = In.ar(bus, 2);
            var hpf = HPF.ar(input * (1 - flush), hipass1);
            var pit = PitchShift.ar(hpf, 0.5, shimmer_oct1, pitchv1, 1, mul: 8);
            var fbSig = LocalIn.ar(2);
            var fbClean = fbSig * fb1 * (1 - flush);
            var actualMix = mix * Select.kr(mod_mix, [1.0, LFNoise1.kr(0.25).range(0.0, 1.0)]);
            var modTime;
            pit = LPF.ar((pit + fbClean), lowpass1);
            modTime = fbDelay1 + SinOsc.kr([0.07, 0.09], [0, 0.5pi], 0.5 * 0.004);
            LocalOut.ar(DelayC.ar(pit, 1.0, modTime.clip(0.001, 1.0)).softclip);
            ReplaceOut.ar(bus, input + (pit * actualMix));
        }).add;

        SynthDef(\monobass, {
            arg bus;
            var sig = In.ar(bus, 2);
            sig = HPF.ar(HPF.ar(sig, 200), 200) + LPF.ar(LPF.ar((sig[0] + sig[1]) * 0.5, 200), 200);
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
            var wet, depth = 0.2, rate = 0.6, predelay = 0.025, voice1, voice2, voice3, voice4, wide;
            var chorus = { |input, delayTime, rate, depth| var mod = SinOsc.kr(rate, [0, pi/2]).range(-1, 1) * depth; var delays = delayTime + (mod * 0.02); DelayL.ar(input, 0.05, delays); };
            voice1 = chorus.(sig, predelay * 0.5, rate * 0.99, depth * 0.8);
            voice2 = chorus.(sig, predelay * 0.65, rate * 1.01, depth * 0.9);
            voice3 = chorus.(sig, predelay * 0.85, rate * 0.98, depth * 1.0);
            voice4 = chorus.(sig, predelay * 1.05, rate * 1.02, depth * 0.7);
            wet = [voice1[0] * 0.25 + voice2[0] * 0.25 + voice3[1] * 0.25 + voice4[1] * 0.25, voice1[1] * 0.25 + voice2[1] * 0.25 + voice3[0] * 0.25 + voice4[0] * 0.25];
            wide = wet * 6;
            ReplaceOut.ar(bus, XFade2.ar(sig, wide, mix * 2 - 1));
        }).add;

        SynthDef(\tape, {
            arg bus;
            var os = SampleRate.ir / 44100, sh = 0.596, fd = 0.6.pow(6) * 0.0011338, fhz = 0.4.cubed * 140.37, ob = 0.865.cubed * 44100, d, hs, x2, hb, lk;
            var sig = t9dub.(In.ar(bus, 2) * 2.25 + WhiteNoise.ar(1e-18), (1 - sh) / os, 1.2, 2.848, 1.152);
            sig = DelayC.ar(sig, 0.003, SinOsc.kr(fhz * LFNoise1.kr(fhz * 0.5 ! 2).range(0.24, 0.98), pi, fd, fd));
            sig = Slew.ar(sig, ob, ob);
            d = Delay1.ar(sig) - sig;
            hs = ((Delay1.ar(d * 0.5 + sig) - sig).abs * 0.12).min(1);
            hs = hs * (hs * -0.5 + 1);
            sig = (d * hs + sig).clip2(2.305929);
            x2 = sig.squared;
            sig = sig * (x2 * (x2 * (x2 * (x2 * (x2 * -0.000000100208 + 0.00000444473) - 0.0003952447) + 0.014492754) - 0.16666667) + 1);
            sig = (Delay1.ar(sig) - sig) * hs + sig;
            lk = (OnePole.ar(LocalIn.ar(2).squared, 0.998) * (0.0927 / os)).clip(1e-6, 0.9);
            hb = OnePole.ar(sig * (0.066 / os) * (1 - lk) / lk, 1 - lk);
            LocalOut.ar(hb);
            hb = BPF.ar(BPF.ar(hb, 60, 1.618), 56.25, 1.618);
            sig = (t9dub.(hb * 0.33 + sig, sh / os, -0.8, 2.628, 1.372) * 0.6309573).clip2(0.9085097);
            x2 = HPZ1.ar(sig).abs;
            ReplaceOut.ar(bus, sig.clip2(0.94 / (x2.max(Delay1.ar(x2)) * 2.7972026 + 1)));
        }).add;

        SynthDef(\wobble, {
            arg bus, mix=0.0, wobble_amp=0.05, wobble_rpm=33, flutter_amp=0.03, flutter_freq=6, flutter_var=2, flush=0;
            var pr, pw, rate, wet, flutter, wow, dry;
            dry = In.ar(bus, 2);
            wow = wobble_amp * SinOsc.kr(wobble_rpm/60, mul: 0.2);
            flutter = flutter_amp * SinOsc.kr(flutter_freq + LFNoise2.kr(flutter_var), mul: 0.1);
            rate = 1 + (wow + flutter);
            pw = Phasor.ar(0, BufRateScale.ir(wobbleBuffer), 0, BufFrames.ir(wobbleBuffer));
            BufWr.ar(dry * (1 - flush), wobbleBuffer, pw);
            pr = DelayL.ar(Phasor.ar(0, BufRateScale.ir(wobbleBuffer)*rate, 0, BufFrames.ir(wobbleBuffer)), 0.2, 0.2);
            wet = BufRd.ar(2, wobbleBuffer, pr, interpolation: 4);
            ReplaceOut.ar(bus, XFade2.ar(dry, wet, mix * 2 - 1));
        }).add;

        SynthDef(\glitch, {
            arg bus, glitch_ratio = 0.0, mix, minLength, maxLength, reverse, pitch, maxStutters, gate_amt = 1, decay = 0, flush = 0;
            var sig, sr, frames, busy, rest, writePos, idle, cool, trig, len, start, ps, dur, on, el, t, rel, pos, fade, env, wet;
            sig = In.ar(bus, 2);
            sr = SampleRate.ir;
            frames = BufFrames.ir(glitchBuffer);
            writePos = Phasor.ar(0, 1, 0, frames);
            BufWr.ar(sig * (1 - flush), glitchBuffer, writePos);
            #busy, rest = LocalIn.kr(2);
            idle = (2 + maxStutters) * (minLength + maxLength) * 0.25 * (1 - glitch_ratio).max(0.01) / glitch_ratio.max(0.0001);
            cool = (idle * 0.5).min(4);
            trig = Dust.kr((idle - cool).reciprocal) * (1 - rest) * (1 - busy);
            len = TRand.kr(minLength, maxLength, trig) * sr;
            start = (Latch.kr(writePos, trig) - len).wrap(0, frames);
            ps = Select.kr(TRand.kr(0, 1, trig) < pitch, [1, Select.kr(TIRand.kr(0, 3, trig), [0.707, 0.841, 1.189, 1.414])]);
            dur = (TIRand.kr(2, maxStutters, trig) * len / ps).min(frames - len - (sr * 0.02)) / sr;
            on = Trig1.kr(trig, dur);
            el = Sweep.kr(trig, 1);
            LocalOut.kr([on, Trig1.kr(busy * (1 - on), cool)]);
            t = T2A.ar(trig);
            len = Latch.ar(len, t);
            rel = Phasor.ar(t, ps, 0, len);
            pos = Latch.ar(start, t) + Select.ar(TRand.kr(0, 1, trig) < reverse, [rel, len - rel]);
            fade = (len * gate_amt * 0.25).clip(1, sr * 0.005);
            env = (rel / fade).clip(0, 1).min(((len * gate_amt - rel) / fade).clip(0, 1));
            wet = BufRd.ar(2, glitchBuffer, pos, 1, 2) * env * (1 - (decay * (el / dur.max(0.001)).clip(0, 1)));
            ReplaceOut.ar(bus, LinXFade2.ar(sig, wet, (Lag.kr(on, 0.005) * mix * 2) - 1));
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
            arg bus;
            var sig = In.ar(bus, 2);
            var out = [sig[0], DelayN.ar(sig[1], 0.05, 0.02)];
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
            arg bus, mix = 0.0, decay = 2.0, cutoff = 8000, f1 = 220, f2 = 277, f3 = 330, f4 = 440, f5 = 554, flush = 0;
            var sig, exc, freqs, amps, wet, cf, detune;
            sig = In.ar(bus, 2);
            exc = tanh(sig.sum * 0.15) * (1 - flush);
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
            arg bus, mix=0, rate=800, sweep=0.3;
            var x = In.ar(bus, 2), c = SinOsc.ar(rate * [1, 1.006] * SinOsc.kr(sweep.squared * [12, 9.96], 0, sweep * 0.75, 1));
            ReplaceOut.ar(bus, (x * c * 0.5 - x) * mix + x);
        }).add;

        SynthDef(\stchorus, {
            arg bus, mix=0;
            var dry = In.ar(bus, 2), sp = (0.5 / 6 + 0.32).pow(10), dp = 0.6 / 60 / sp;
            var air = OnePole.ar(dry * 252.1646, -0.9921), t = SinOsc.ar(sp * 7018.73, [1.16355, pi], dp, dp + 1) / 44100;
            var wet = DelayN.ar(HPZ2.ar(air), 0.14, t) * -0.04 + DelayL.ar(LPZ1.ar(air), 0.14, t);
            ReplaceOut.ar(bus, XFade2.ar(dry, wet, mix * 2 - 1));
        }).add;

        SynthDef(\spiral, {
            arg bus, mix=0, bpm=120, div=0.5, feedback=0.5, rise=0.75, glide=0, span=0.5, tone=0.5, flush=0;
            var x = In.ar(bus, 2), sr = SampleRate.ir, frames = BufFrames.ir(spiralBuffer), soft = csoft;
            var mono = x.sum * 0.5, ax = mono.abs, d = (sr * 60 / bpm * div).clip(sr * 0.0348, sr * 2.72);
            var envF = A2K.kr(OnePole.ar(ax, 0.98)), envS = A2K.kr(OnePole.ar(ax, 0.9992)), peak = PeakFollower.kr(envF, 0.99995465 ** (sr * ControlDur.ir));
            var fbT = LocalIn.kr(1), t = (envF > (envS * 1.7 + 0.008)) * (1 - SetResetFF.kr(fbT, envF < (peak * 0.08))) * (1 - Trig1.kr(fbT, 0.25));
            var ramp = 1 - Decay.kr(t, 6.9078 / (((1 - span).cubed * 1.13e-4 + 2.8e-6) * 44100)).min(1);
            var ratio = (Select.kr(rise < 0.5, [rise * 2, rise + 0.5]) * (glide * 0.6 * ramp * ((rise >= 0.5) * 2 - 1) + 1)).clip(0.25, (d / 1024).clip(1.05, 4));
            var gtrig = Impulse.ar(sr / 1024), gt = Sweep.ar(gtrig, sr), wp = Phasor.ar(0, 1, 0, frames), e, lp;
            LocalOut.kr(t);
            e = (gt.min(1024 - gt) * 0.001953125).clip(0, 1);
            lp = OnePole.ar(BufRd.ar(2, spiralBuffer, (Latch.ar(wp - d, gtrig) + Sweep.ar(gtrig, ratio * sr)).wrap(0, frames), 1, 2) * (e * e * (3 - (2 * e))), 0.97 - (tone * 0.5));
            BufWr.ar(soft.(lp * (feedback * 0.965) + x) * (1 - flush), spiralBuffer, wp);
            ReplaceOut.ar(bus, (soft.(x + lp) - x) * mix + x);
        }).add;

        SynthDef(\genloss, {
            arg bus, mix=0;
            var x = In.ar(bus, 2), m = SinOsc.ar(0.7, 0, 132) + SinOsc.ar(8, 0, 30) + OnePole.ar(WhiteNoise.ar(90), 0.9988);
            var w = DelayL.ar(csoft.(x * 1.8), 0.025, (m + 529) / 44100);
            w = OnePole.ar(w - OnePole.ar(w, 0.988), 0.77) + WhiteNoise.ar(0.0006 ! 2);
            ReplaceOut.ar(bus, (w * 1.15 - x) * mix + x);
        }).add;

        SynthDef(\fuzz, {
            arg bus, mix=0, octave=0.5, gain=0.6, tone=0.5;
            var x = In.ar(bus, 2), a = csoft.(OnePole.ar(csoft.((x - OnePole.ar(x, 0.987)) * 16 + 0.12) - 0.179136, 0.425) * (gain * 40 + 8));
            var env = LagUD.ar(a.abs, 0.006904, 0.348), sq = ToggleFF.ar(PulseDivider.ar(Schmidt.ar(OnePole.ar(a, 0.985), -0.02, 0.02), 2)) * 2 - 1;
            var b = OnePole.ar(csoft.(sq * env * (env > 0.004) * 4), 0.65);
            var y = (((a - OnePole.ar(a, 0.65245)) * ((tone - 0.5) * 2.2) + a) * (1 - octave) + (b * octave) * 0.06).clip2(1);
            ReplaceOut.ar(bus, (y - x) * mix + x);
        }).add;

        SynthDef(\sub, {
            arg bus, mix=0, detune=0.65;
            var x = In.ar(bus, 2), mono = x.sum * 0.5, off = SinOsc.kr(0.15, 0, detune * 0.0173287), s = SampleDur.ir;
            var d1 = (Phasor.ar(0, [0.5 - off, 0.5 + off], 0, 4096) + [0, 2048]) % 4096, d2 = (d1 + 2048) % 4096;
            var v = DelayL.ar(mono, 0.1, d1 * s) * tri.(d1) + (DelayL.ar(mono, 0.1, d2 * s) * tri.(d2));
            ReplaceOut.ar(bus, (OnePole.ar(csoft.(v * 2.5), 0.89 ** (44100 * s)) - x) * mix + x);
        }).add;

        SynthDef(\reel, {
            arg bus, mix=0;
            var x = In.ar(bus, 2), w = OnePole.ar(csoft.(x * 4.24 + 0.1) - 0.1495, 0.58) * 0.612;
            ReplaceOut.ar(bus, (w - x) * mix + x);
        }).add;

        SynthDef(\vibe, {
            arg bus, drift = 0.5, mix = 0;
            var x = In.ar(bus, 2), p = Phasor.kr(0, LocalIn.kr(1).max(0.4294967) * drift.cubed * 0.001 * SampleRate.ir * ControlDur.ir, 0, 2pi), ph = (p + 3) % 2pi;
            var wet = DelayL.ar(x, 260 * SampleDur.ir, (129 - (127 * [sin(ph), cos(ph)])) * SampleDur.ir);
            LocalOut.kr(TRand.kr(0.4294967, 0.6949, HPZ1.kr(p) < 0));
            ReplaceOut.ar(bus, x + ((wet - x) * mix));
        }).add;

        SynthDef(\limiter, {
            arg bus;
            ReplaceOut.ar(bus, Limiter.ar(In.ar(bus, 2), 0.97, 0.004));
        }).add;

        SynthDef(\ott, {
            arg bus, mix = 0;
            var x = In.ar(bus, 2), f1 = 88.3, f2 = 2500, amt = Lag.kr(mix, 0.1);
            var lo = LPF.ar(LPF.ar(x, f1), f1), rest = HPF.ar(HPF.ar(x, f1), f1);
            var mid = LPF.ar(LPF.ar(rest, f2), f2), hi = HPF.ar(HPF.ar(rest, f2), f2);
            var wet = [[BAllPass.ar(lo, f2, 1.4142), -33.8, -40.8, 0.0478, 0.282, 10.3, 0.15], [mid, -30.2, -41.8, 0.0224, 0.282, 5.7, 0.1], [hi, -35.5, -40.8, 0.0135, 0.132, 10.3, 0.02]].collect({ arg p;
                var b = p[0], lvl = (A2K.kr(Lag.ar((b[0].squared + b[1].squared) * 0.5, p[6])).max(1e-10).log10 * 10) + 3;
                var g = ((p[1] - lvl).min(0) * 0.985) + ((p[2] - lvl).clip(0, 36) * (((lvl + 90) * 0.05).clip(0, 1) * 0.76));
                b * ((LagUD.kr(g, p[4], p[3]) + p[5] + 6) * amt).dbamp
            }).sum;
            ReplaceOut.ar(bus, wet);
        }).add;

        context.server.sync;

        bitcrushEffect = Synth.newPaused(\bitcrush, [\bus, context.out_b.index, \mix, 0.0, \mod_mix, 0], context.xg, 'addToTail');
        resonatorEffect = Synth.newPaused(\resonator, [\bus, context.out_b.index, \mix, 0.0], context.xg, 'addToTail');
        wavefoldEffect = Synth.newPaused(\wavefold, [\bus, context.out_b.index, \mix, 0.0], context.xg, 'addToTail');
        ringmodEffect = Synth.newPaused(\ringmod, [\bus, context.out_b.index, \mix, 0.0], context.xg, 'addToTail');
        sineEffect = Synth.newPaused(\sine, [\bus, context.out_b.index, \sine_drive_wet, 0.0], context.xg, 'addToTail');
        analogDriveEffect = Synth.newPaused(\analogdrive, [\bus, context.out_b.index], context.xg, 'addToTail');
        fuzzEffect = Synth.newPaused(\fuzz, [\bus, context.out_b.index], context.xg, 'addToTail');
        glitchEffect = Synth.newPaused(\glitch, [\bus, context.out_b.index, \glitch_ratio, 0.0], context.xg, 'addToTail');
        tapeEffect = Synth.newPaused(\tape, [\bus, context.out_b.index], context.xg, 'addToTail');
        reelEffect = Synth.newPaused(\reel, [\bus, context.out_b.index], context.xg, 'addToTail');
        wobbleEffect = Synth.newPaused(\wobble, [\bus, context.out_b.index, \mix, 0.0], context.xg, 'addToTail');
        chewEffect = Synth.newPaused(\chew, [\bus, context.out_b.index, \chew_depth, 0.0], context.xg, 'addToTail');
        lossdegradeEffect = Synth.newPaused(\lossdegrade, [\bus, context.out_b.index, \mix, 0.0], context.xg, 'addToTail');
        genlossEffect = Synth.newPaused(\genloss, [\bus, context.out_b.index], context.xg, 'addToTail');
        subEffect = Synth.newPaused(\sub, [\bus, context.out_b.index], context.xg, 'addToTail');
        spiralEffect = Synth.newPaused(\spiral, [\bus, context.out_b.index], context.xg, 'addToTail');
        shimmerEffect = Synth.newPaused(\shimmer, [\bus, context.out_b.index, \mix, 0.0, \mod_mix, 0], context.xg, 'addToTail');
        delayEffect = Synth.newPaused(\delay, [\bus, context.out_b.index, \mix, 0.0], context.xg, 'addToTail');
        rotateEffect = Synth.newPaused(\rotate, [\bus, context.out_b.index], context.xg, 'addToTail');
        stChorusEffect = Synth.newPaused(\stchorus, [\bus, context.out_b.index], context.xg, 'addToTail');
        vibeEffect = Synth.newPaused(\vibe, [\bus, context.out_b.index], context.xg, 'addToTail');
        dimensionEffect = Synth.newPaused(\dimension, [\bus, context.out_b.index], context.xg, 'addToTail');
        haasEffect = Synth.newPaused(\haas, [\bus, context.out_b.index], context.xg, 'addToTail');
        widthEffect = Synth.newPaused(\width, [\bus, context.out_b.index, \width, 1.0], context.xg, 'addToTail');
        monobassEffect = Synth.newPaused(\monobass, [\bus, context.out_b.index], context.xg, 'addToTail');
        ottEffect = Synth.newPaused(\ott, [\bus, context.out_b.index], context.xg, 'addToTail');

        [
            [\delay, "f", delayEffect, \delay],
            [\fb_amt, "f", delayEffect, \fb_amt],
            [\dhpf, "f", delayEffect, \dhpf],
            [\lpf, "f", delayEffect, \lpf],
            [\w_rate, "f", delayEffect, \w_rate],
            [\stereo, "f", delayEffect, \stereo],
            [\delay_duck, "f", delayEffect, \duck_amt],
            [\shimmer_mod1, "i", shimmerEffect, \mod_mix],
            [\shimmer_oct1, "f", shimmerEffect, \shimmer_oct1],
            [\lowpass1, "f", shimmerEffect, \lowpass1],
            [\hipass1, "f", shimmerEffect, \hipass1],
            [\pitchv1, "f", shimmerEffect, \pitchv1],
            [\fb1, "f", shimmerEffect, \fb1],
            [\fbDelay1, "f", shimmerEffect, \fbDelay1],
            [\analogdrive_drive, "f", analogDriveEffect, \drive],
            [\analogdrive_tone, "f", analogDriveEffect, \tone],
            [\analogdrive_mode, "f", analogDriveEffect, \mode],
            [\analogdrive_mod, "i", analogDriveEffect, \mod_mix],
            [\bitcrush_rate, "f", bitcrushEffect, \rate],
            [\bitcrush_bits, "f", bitcrushEffect, \bits],
            [\bitcrush_mod, "i", bitcrushEffect, \mod_mix],
            [\glitch_maxstutters, "i", glitchEffect, \maxStutters],
            [\glitch_min_length, "f", glitchEffect, \minLength],
            [\glitch_max_length, "f", glitchEffect, \maxLength],
            [\glitch_reverse, "f", glitchEffect, \reverse],
            [\glitch_pitch, "f", glitchEffect, \pitch],
            [\glitch_gate, "f", glitchEffect, \gate_amt],
            [\glitch_decay, "f", glitchEffect, \decay],
            [\wobble_amp, "f", wobbleEffect, \wobble_amp],
            [\wobble_rpm, "f", wobbleEffect, \wobble_rpm],
            [\flutter_amp, "f", wobbleEffect, \flutter_amp],
            [\flutter_freq, "f", wobbleEffect, \flutter_freq],
            [\flutter_var, "f", wobbleEffect, \flutter_var],
            [\chew_freq, "f", chewEffect, \chew_freq],
            [\chew_variance, "f", chewEffect, \chew_variance],
            [\resonator_decay, "f", resonatorEffect, \decay],
            [\resonator_tone, "f", resonatorEffect, \cutoff],
            [\wavefold_drive, "f", wavefoldEffect, \drive],
            [\wavefold_sym, "f", wavefoldEffect, \sym],
            [\ringmod_rate, "f", ringmodEffect, \rate],
            [\ringmod_sweep, "f", ringmodEffect, \sweep],
            [\spiral_bpm, "f", spiralEffect, \bpm],
            [\spiral_div, "f", spiralEffect, \div],
            [\spiral_feedback, "f", spiralEffect, \feedback],
            [\spiral_rise, "f", spiralEffect, \rise],
            [\spiral_glide, "f", spiralEffect, \glide],
            [\spiral_span, "f", spiralEffect, \span],
            [\spiral_tone, "f", spiralEffect, \tone],
            [\fuzz_octave, "f", fuzzEffect, \octave],
            [\fuzz_gain, "f", fuzzEffect, \gain],
            [\fuzz_tone, "f", fuzzEffect, \tone],
            [\sub_detune, "f", subEffect, \detune],
            [\vibe_drift, "f", vibeEffect, \drift],
        ].do({ arg c; this.addCommand(c[0], c[1], { arg msg; c[2].set(c[3], msg[1]); }); });

        [
            [\mix, delayEffect, \mix, 5.1],
            [\shimmer_mix1, shimmerEffect, \mix, 1.6],
            [\analogdrive_mix, analogDriveEffect, \mix],
            [\bitcrush_mix, bitcrushEffect, \mix],
            [\tape_mix, tapeEffect, \mix],
            [\sine_drive_wet, sineEffect, \sine_drive_wet],
            [\wobble_mix, wobbleEffect, \mix, 0.3],
            [\chew_depth, chewEffect, \chew_depth],
            [\lossdegrade_mix, lossdegradeEffect, \mix],
            [\resonator_mix, resonatorEffect, \mix, 5.1],
            [\wavefold_mix, wavefoldEffect, \mix],
            [\ringmod_mix, ringmodEffect, \mix],
            [\stchorus_mix, stChorusEffect, \mix],
            [\spiral_mix, spiralEffect, \mix, 2.8],
            [\genloss_mix, genlossEffect, \mix],
            [\fuzz_mix, fuzzEffect, \mix],
            [\sub_mix, subEffect, \mix],
            [\reel_mix, reelEffect, \mix],
            [\ott_mix, ottEffect, \mix],
            [\dimension_mix, dimensionEffect, \mix],
            [\rspeed, rotateEffect, \rspeed],
            [\vibe_mix, vibeEffect, \mix],
        ].do({ arg c; this.addCommand(c[0], "f", { arg msg; c[1].set(c[2], msg[1]); this.fxRun(c[1], msg[1] > 0, c[3] ? 0); }); });

        this.addCommand(\w_depth, "f", { arg msg; delayEffect.set(\w_depth, msg[1]/100); });

        [
            [\env_select, "ii", currentEnvSelect],
            [\density_mod_amt, "if", currentDensityModAmt],
            [\subharmonics_1, "if", currentSubharmonics1],
            [\subharmonics_2, "if", currentSubharmonics2],
            [\subharmonics_3, "if", currentSubharmonics3],
            [\overtones_1, "if", currentOvertones1],
            [\overtones_2, "if", currentOvertones2],
            [\pitch_mode, "ii", currentPitchMode],
            [\pitch_offset, "if", currentPitch],
            [\direction_mod, "if", currentDirectionMod],
            [\size_variation, "if", currentSizeVariation],
            [\amp_randomize, "if", currentAmpRandomize],
            [\smoothbass, "if", currentSmoothbass],
            [\probability, "if", currentProbability],
            [\size, "if", currentSize],
            [\density, "if", currentDensity],
            [\spread, "if", currentSpread],
            [\pitch_lag, "if", currentPitchLag, \pitch_lag_time],
            [\key_hold, "ii", currentKeyHold],
            [\key_gate, "ii", currentKeyGate],
            [\vel_amp, "if", currentVelAmp]
        ].do({ arg c; this.addCommand(c[0], c[1], { arg msg; var v = msg[1] - 1; c[2][v] = msg[2]; voices[v].set(c[3] ? c[0], msg[2]); }); });

        [[\cutoff, currentCutoff], [\lpf_gain, currentlpf_gain], [\hpf, currentHpf]].do({ arg c; this.addCommand(c[0], "if", { arg msg; var v = msg[1] - 1; c[1][v] = msg[2]; filterSynths[v].set(c[0], msg[2]); this.updateFilterRun(v); }); });
        [[\eq_low_gain, currentLowGain, \low_gain], [\eq_mid_gain, currentMidGain, \mid_gain], [\eq_high_gain, currentHighGain, \high_gain]].do({ arg c; this.addCommand(c[0], "if", { arg msg; var v = msg[1] - 1; c[1][v] = msg[2]; eqSynths[v].set(c[2], msg[2]); this.updateEqRun(v); }); });

        this.addCommand("granular_gain", "if", { arg msg; var voice = msg[1] - 1; currentGranularGain[voice] = msg[2]; voices[voice].set(\granular_gain, msg[2]); drySynths[voice].set(\granular_gain, msg[2]); this.updateDryRun(voice); });
        this.addCommand("pitch_random_scale_type", "ii", { arg msg; var voice = msg[1] - 1; var scaleType = msg[2]; currentPitchRandomScale[voice] = scaleType; voices[voice].set(\pitch_random_scale_buf, pitchScaleBuffers[scaleType].bufnum, \pitch_random_scale_len, pitchScaleLengths[scaleType]); });
        this.addCommand("pitch_random_prob", "if", { arg msg; var voice = msg[1] - 1; currentPitchRandomProb[voice] = msg[2]; voices[voice].set(\pitch_random_prob, msg[2].abs * 0.01, \pitch_random_direction, msg[2].sign); });
        this.addCommand("ratcheting_prob", "if", { arg msg; var voice = msg[1] - 1; currentRatchetingProb[voice] = msg[2] * 0.01; voices[voice].set(\ratcheting_prob, msg[2] * 0.01); });

        this.addCommand("read", "is", { arg msg; var voice = msg[1] - 1; this.readBuf(voice, msg[2]); });
        this.addCommand("norm_load", "i", { arg msg; normOnLoad = msg[1]; 2.do({ arg i; var g; if(voicesUsingLiveBuffer[i].not, { g = this.normGain(i); voices[i].set(\norm, g); drySynths[i].set(\norm, g); }); }); });
        this.addCommand("seek", "if", { arg msg; var voice = msg[1] - 1; seekPos[voice] = msg[2]; lastPos[voice] = msg[2]; voices[voice].set(\pos, msg[2], \t_reset_pos, 1); drySynths[voice].set(\pos, msg[2], \t_reset_pos, 1); });
        this.addCommand("reseek", "i", { arg msg; var voice = msg[1] - 1; if(voices[voice].notNil, { voices[voice].set(\t_reset_pos, 1); }); if(drySynths[voice].notNil, { drySynths[voice].set(\t_reset_pos, 1); }); });
        this.addCommand("speed", "if", { arg msg; var voice = msg[1] - 1; currentSpeed[voice] = msg[2]; voices[voice].set(\speed, msg[2]); drySynths[voice].set(\speed, msg[2]); });
        this.addCommand("jitter", "if", { arg msg; var voice = msg[1] - 1; currentJitter[voice] = msg[2]; voices[voice].set(\jitter, msg[2] / 2); });
        this.addCommand("pan", "if", { arg msg; var voice = msg[1] - 1; currentPan[voice] = msg[2]; voices[voice].set(\pan, msg[2]); drySynths[voice].set(\pan, msg[2]); });
        this.addCommand("volume", "if", { arg msg; var voice = msg[1] - 1; currentVolume[voice] = msg[2]; voices[voice].set(\gain, msg[2]); if(bounceTracks.notNil, { var t = bounceTracks[voice]; t[0].set(t[1], msg[2].max(1e-4).reciprocal); }); });

        this.addCommand("glitch_ratio", "f", { arg msg; currentGlitchRatio = msg[1]; glitchEffect.set(\glitch_ratio, currentGlitchRatio); this.fxRun(glitchEffect, (currentGlitchRatio > 0) && (currentGlitchMix > 0), 0.6); });
        this.addCommand("glitch_mix", "f", { arg msg; currentGlitchMix = msg[1]; glitchEffect.set(\mix, currentGlitchMix); this.fxRun(glitchEffect, (currentGlitchRatio > 0) && (currentGlitchMix > 0), 0.6); });

        this.addCommand("resonator_freqs", "fffff", { arg msg; resonatorEffect.set(\f1, msg[1], \f2, msg[2], \f3, msg[3], \f4, msg[4], \f5, msg[5]); });

        this.addCommand("eq_tilt", "if", { arg msg; var voice = msg[1] - 1; currentTiltGain[voice] = msg[2]; tiltSynths[voice].set(\tilt, msg[2]); this.updateTiltRun(voice); });

        this.addCommand("width", "f", { arg msg; widthEffect.set(\width, msg[1]); widthEffect.run(msg[1] != 1); });
        this.addCommand("monobass_mix", "f", { arg msg; monobassEffect.run(msg[1] > 0); });
        this.addCommand("haas", "i", { arg msg; haasEffect.run(msg[1] > 0); });
        this.addCommand("limiter", "i", { arg msg; if(msg[1] > 0, { if(limiterEffect.isNil, { limiterEffect = Synth.new(\limiter, [\bus, context.out_b.index], context.xg, 'addToTail') }) }, { if(limiterEffect.notNil, { limiterEffect.free; limiterEffect = nil }) }); });

        this.addCommand("voice_run", "ii", { arg msg; var voice = msg[1] - 1; var state = msg[2]; if(voices[voice].notNil, { voices[voice].run(state > 0); voiceRunning[voice] = (state > 0); this.updateDryRun(voice); }); });
        this.addCommand("key_grain", "i", { arg msg; var voice = msg[1] - 1; if(voices[voice].notNil, { voices[voice].set(\t_key_trig, 1); }); });
        this.addCommand("key_ad", "iff", { arg msg; var voice = msg[1] - 1; currentAdA[voice] = msg[2]; currentAdD[voice] = msg[3]; if(voices[voice].notNil, { voices[voice].set(\ad_a, msg[2], \ad_d, msg[3]); }); });
        this.addCommand("set_live_input", "ii", { arg msg; var voice = msg[1] - 1; var enable = msg[2]; if (enable == 1, { this.cancelLoad(voice); if (liveInputRecorders[voice].notNil, { liveInputRecorders[voice].free; }); liveRecPosBuses[voice].set(-1.0); liveInputRecorders[voice] = Synth.new(\liveInputRecorder, [ \bufL, liveInputBuffersL[voice], \bufR, liveInputBuffersR[voice], \mix, liveBufferMix, \voice, voice, \recPosBus, liveRecPosBuses[voice].index, \isMono, inMono[voice] ], context.xg, 'addToHead'); voicesUsingLiveBuffer[voice] = true; voices[voice].set( \buf_l, liveInputBuffersL[voice], \buf_r, liveInputBuffersR[voice], \rec_pos_bus, liveRecPosBuses[voice].index, \is_stereo, 1, \norm, 1, \rscale, 1, \t_reset_pos, 1); voiceIsStereo[voice] = 1; voices[voice].run(true); drySynths[voice].set( \buf_l, liveInputBuffersL[voice], \buf_r, liveInputBuffersR[voice], \rec_pos_bus, liveRecPosBuses[voice].index, \norm, 1, \rscale, 1, \t_reset_pos, 1); voiceRunning[voice] = true; lastPos[voice] = seekPos[voice]; this.updateDryRun(voice); }, { if (liveInputRecorders[voice].notNil, { liveInputRecorders[voice].free; }); liveInputRecorders[voice] = nil; liveRecPosBuses[voice].set(-1.0); voices[voice].set(\rec_pos_bus, -1); drySynths[voice].set(\rec_pos_bus, -1); }); });
        this.addCommand("live_buffer_mix", "f", { arg msg; liveBufferMix = msg[1]; liveInputRecorders.do({ arg recorder; if (recorder.notNil, { recorder.set(\mix, liveBufferMix); }); }); });
        this.addCommand("live_direct", "ii", { arg msg; var voice = msg[1] - 1; var enable = msg[2]; if (enable == 1, { this.cancelLoad(voice); if (voices[voice].notNil, { voices[voice].free; }); if (liveInputRecorders[voice].notNil, { liveInputRecorders[voice].free; liveInputRecorders[voice] = nil; }); voices[voice] = Synth.new(\liveDirect, [ \out, voiceBuses[voice].index,\pan, currentPan[voice] ? 0,\gain, currentVolume[voice] ? 1, \voice, voice, \isMono, inMono[voice], \key_hold, currentKeyHold[voice], \key_gate, currentKeyGate[voice], \ad_a, currentAdA[voice], \ad_d, currentAdD[voice], \vel_amp, currentVelAmp[voice] ], target: pg); voices[voice].run(true); voiceRunning[voice] = false; this.updateDryRun(voice); }, { if (voices[voice].notNil, { voices[voice].free; }); this.directOff(voice); }); });
        this.addCommand("isMono", "ii", { arg msg; var voice = msg[1] - 1; inMono[voice] = msg[2]; voices[voice].set(\isMono, msg[2]); });
        this.addCommand("live_mono", "ii", { arg msg; var voice = msg[1] - 1; var mono = msg[2]; inMono[voice] = mono; if(liveInputRecorders[voice].notNil, { liveInputRecorders[voice].set(\isMono, mono); }); if(voicesUsingLiveBuffer[voice] && voices[voice].notNil, { voices[voice].set(\is_stereo, 1 - mono); voiceIsStereo[voice] = 1 - mono; }); });
        this.addCommand("unload_all", "", { this.unloadAll(); });
        this.addCommand("pause_voice", "i", { arg msg; var voice = msg[1] - 1; this.cancelLoad(voice); this.silence(voice); });
        this.addCommand("run_voice", "ii", { arg msg; var voice = msg[1] - 1; var on = msg[2]; if(voices[voice].notNil, { if(on == 1, { voices[voice].set(\t_reset_pos, 1); voices[voice].run(true); drySynths[voice].set(\t_reset_pos, 1); voiceRunning[voice] = true; lastPos[voice] = seekPos[voice]; }, { voices[voice].run(false); voiceRunning[voice] = false; }); this.updateDryRun(voice); }); });
        this.addCommand("save_live_buffer", "is", { arg msg; var voice = msg[1] - 1; var filename = msg[2]; this.saveLiveBufferToTape(voice, filename); });
        this.addCommand("bounce", "ifsif", { arg msg; this.bounce(msg[1], msg[2], msg[3].asString, msg[4], msg[5]); });
        this.addCommand("live_buffer_length","f",{ arg msg; var length=msg[1],myGeneration; liveBufferAllocGeneration=liveBufferAllocGeneration+1; myGeneration=liveBufferAllocGeneration; fork{ var newBufsL=Array.fill(2,{Buffer.alloc(context.server,(context.server.sampleRate*length).round.asInteger)}),newBufsR=Array.fill(2,{Buffer.alloc(context.server,(context.server.sampleRate*length).round.asInteger)}); context.server.sync; if(myGeneration==liveBufferAllocGeneration,{ var oldBufsL=liveInputBuffersL,oldBufsR=liveInputBuffersR; liveInputBuffersL=newBufsL; liveInputBuffersR=newBufsR; liveInputRecorders.do({ arg recorder,i; if(recorder.notNil,{ recorder.free; liveRecPosBuses[i].set(-1.0); liveInputRecorders[i]=Synth.new(\liveInputRecorder,[\bufL,liveInputBuffersL[i],\bufR,liveInputBuffersR[i],\mix,liveBufferMix,\voice,i,\recPosBus,liveRecPosBuses[i].index,\isMono,inMono[i]],context.xg,'addToHead'); voices[i].set(\buf_l,liveInputBuffersL[i],\buf_r,liveInputBuffersR[i],\rec_pos_bus,liveRecPosBuses[i].index,\t_reset_pos,1); drySynths[i].set(\buf_l,liveInputBuffersL[i],\buf_r,liveInputBuffersR[i],\rec_pos_bus,liveRecPosBuses[i].index,\t_reset_pos,1);},{ if(voicesUsingLiveBuffer[i] && voices[i].notNil,{ voices[i].set(\buf_l,liveInputBuffersL[i],\buf_r,liveInputBuffersR[i],\t_reset_pos,1); drySynths[i].set(\buf_l,liveInputBuffersL[i],\buf_r,liveInputBuffersR[i],\t_reset_pos,1); }); }); });oldBufsL.do({ arg buf; if(buf.notNil,{buf.free})}); oldBufsR.do({ arg buf; if(buf.notNil,{buf.free})});},{ newBufsL.do({ arg buf; if(buf.notNil,{buf.free})}); newBufsR.do({ arg buf; if(buf.notNil,{buf.free})});});};});

        o = OSCFunc({ |msg| lastPos[msg[3].asInteger] = msg[4]; nornsAddr.sendMsg("/twins/voice_state", msg[3].asInteger, msg[4], msg[5], msg[6], msg[7], msg[8], msg[9], msg[10], msg[11], msg[12]); }, '/voice_state', context.server.addr);
        o_rec = OSCFunc({ |msg| nornsAddr.sendMsg("/twins/rec_pos", msg[3].asInteger, msg[4], msg[5]); }, '/rec_pos', context.server.addr);
        o_voice_peak = OSCFunc({ |msg| nornsAddr.sendMsg("/twins/voice_peak", msg[3].asInteger, msg[4], msg[5]); }, '/voice_peak', context.server.addr);
        o_delayduck = OSCFunc({ |msg| nornsAddr.sendMsg("/twins/delay_duck", msg[3]); }, '/delay_duck', context.server.addr);
    }

updateFilterRun { arg voice;
        var on = (currentCutoff[voice] < 19990) || (currentHpf[voice] > 20.5) || (currentlpf_gain[voice] > 0), tok;
        if(on == filterOn[voice], { ^this });
        filterOn[voice] = on;
        filterTok[voice] = filterTok[voice] + 1;
        tok = filterTok[voice];
        if(on, {
            filterSynths[voice].set(\on, 1);
            filterSynths[voice].run(true);
        }, {
            filterSynths[voice].set(\on, 0);
            fork { 0.06.wait; if(tok == filterTok[voice], { filterSynths[voice].run(false) }) };
        });
}
updateEqRun { arg voice; eqSynths[voice].run((currentLowGain[voice] != 0) || (currentMidGain[voice] != 0) || (currentHighGain[voice] != 0)); }
updateTiltRun { arg voice; tiltSynths[voice].run(currentTiltGain[voice] != 0); }

updateDryRun { arg voice; var on = voiceRunning[voice] && (currentGranularGain[voice] < 1); if(on && dryOn[voice].not, { this.resumeAt(drySynths[voice], voice) }); dryOn[voice] = on; drySynths[voice].run(on); }

free {
        [voices, drySynths, filterSynths, eqSynths, tiltSynths, filterRouters, liveInputRecorders].do({ arg col; col.do({ arg x; if(x.notNil, { x.free }); }); });
        2.do({ arg i; this.cancelLoad(i); this.freePair(buffersL[i], buffersR[i]); });
        [liveInputBuffersL, liveInputBuffersR, liveRecPosBuses, pitchScaleBuffers, grainEnvs, voiceBuses, voiceAmpBuses, meterBuses].do({ arg col; col.do({ arg b; if(b.notNil, { b.free }); }); });
        [o, o_rec, o_voice_peak, o_delayduck, limiterEffect, vibeEffect, stChorusEffect, reelEffect, ottEffect, genlossEffect, fuzzEffect, subEffect, spiralEffect, spiralBuffer, wobbleBuffer, glitchBuffer, silentBuffer, bufSine, bitcrushEffect, shimmerEffect, analogDriveEffect, resonatorEffect, wavefoldEffect, ringmodEffect, tapeEffect, chewEffect, widthEffect, monobassEffect, lossdegradeEffect, sineEffect, wobbleEffect, glitchEffect, delayEffect, rotateEffect, haasEffect, dimensionEffect, dryGroup, pg].do({ arg x; if(x.notNil, { x.free }); });
    }
}