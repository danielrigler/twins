Engine_twins : CroneEngine {
    classvar nvoices = 2;

    var fverbEffect;
    var shimmerEffect;
    var directOut;
    var <buffersL;
    var <buffersR;
    var <voices;
    var mixBus;
    var <seek_tasks;
    var bufSine;
    var <wobbleBuffers;

    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

readBuf { arg i, path;
    if(buffersL[i].notNil && buffersR[i].notNil, {
        if (File.exists(path), {
            var numChannels;
            var newbuf;
            numChannels = SoundFile.use(path.asString(), { |f| f.numChannels });
            newbuf = Buffer.readChannel(context.server, path, 0, -1, [0], { |b|
                voices[i].set(\buf_l, b);
                buffersL[i].free;
                buffersL[i] = b;
                voices[i].set(\pos, 0, \t_reset_pos, 1, \freeze, 0);
            });
            if (numChannels > 1, {
                newbuf = Buffer.readChannel(context.server, path, 0, -1, [1], { |b|
                    voices[i].set(\buf_r, b);
                    buffersR[i].free;
                    buffersR[i] = b;
                });
            }, {
                voices[i].set(\buf_r, newbuf);
                buffersR[i].free;
                buffersR[i] = newbuf;
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
        
        bufSine = Buffer.alloc(context.server, 1024 * 16, 1);
        bufSine.sine2([2], [0.5], false);
        wobbleBuffers = Array.fill(nvoices, {Buffer.alloc(context.server, 48000 * 5, 2) });
        context.server.sync;
      
        SynthDef(\synth, {
            arg out, buf_l, buf_r,
            pos=0, speed=1, jitter=0,
            size=0.1, density=20, density_mod_amt=0, pitch_offset=0, pan=0, spread=0, gain=1,
            freeze=0, t_reset_pos=0,
            granular_gain=1,
            pitch_mode=0,
            subharmonics_1=0, 
            subharmonics_2=0,
            subharmonics_3=0,
            overtones_1=0, 
            overtones_2=0, 
            cutoff=20000, hpf=20,
            sine_drive=1, sine_wet=0,
            chew_wet=0, chew_depth=0.5, chew_freq=0.5, chew_variance=0.5,
            direction_mod=0,
            size_variation=0,
            low_gain=0, high_gain=0,
            width=1,
            pitch_random_plus=0, pitch_random_minus=0,
            wobble_wet=0, wobble_amp=0.05, wobble_rpm=33, flutter_amp=0.03, flutter_freq=6, flutter_var=2, wobble_bufnum;
 
            var grain_trig;
            var jitter_sig;
            var buf_dur;
            var pan_sig;
            var buf_pos;
            var pos_sig;
            var sig_l;
            var sig_r;
            var sig_mix;
            var density_mod;
            var dry_sig;
            var granular_sig;
            var base_pitch;
            var grain_pitch;
            var shaped;
            var denominator = 1 + subharmonics_1 + subharmonics_2 + subharmonics_3 + overtones_1 + overtones_2;
            var main_vol = 1 / denominator;
            var subharmonic_1_vol = subharmonics_1 / denominator * 2;
            var subharmonic_2_vol = subharmonics_2 / denominator * 2;
            var subharmonic_3_vol = subharmonics_3 / denominator * 2;
            var overtone_1_vol = overtones_1 / denominator * 2;
            var overtone_2_vol = overtones_2 / denominator * 2;
            var lagPitchOffset = Lag.kr(pitch_offset, 1);
            var grain_direction = Select.kr(pitch_mode, [1, Select.kr(speed.abs > 0.001, [1, speed.sign])]) * ((LFNoise1.kr(density).range(0,1) < direction_mod).linlin(0,1,1,-1));
            var trig_rnd = LFNoise1.kr(density);
            var grain_size;
            var low, high;
            var positive_intervals = [12, 24], negative_intervals = [-12, -24];
            var rand_val, interval_plus, interval_minus, final_interval;
            var mid, side;
            var wow = wobble_amp * SinOsc.kr(wobble_rpm/60, mul:0.2);
            var flutter = flutter_amp * SinOsc.kr(flutter_freq + LFNoise2.kr(flutter_var), mul:0.1);
            var rate = 1 + (wobble_wet * (wow + flutter));
            var pw, pr;

            density_mod = density * (2**(trig_rnd * density_mod_amt));
            grain_trig = Impulse.kr(density_mod);

            pan_sig = Lag.kr(TRand.kr(trig: grain_trig, lo: spread.neg, hi: spread), 0.2);

            buf_dur = BufDur.kr(buf_l);
            jitter_sig = TRand.kr(trig: grain_trig, lo: buf_dur.reciprocal.neg * jitter, hi: buf_dur.reciprocal * jitter);
            buf_pos = Phasor.kr(trig: t_reset_pos, rate: buf_dur.reciprocal / ControlRate.ir * speed, resetPos: pos);
            pos_sig = Wrap.kr(Select.kr(freeze, [buf_pos, pos]));
            dry_sig = [PlayBuf.ar(1, buf_l, speed, startPos: pos * BufFrames.kr(buf_l), trigger: t_reset_pos, loop: 1), PlayBuf.ar(1, buf_r, speed, startPos: pos * BufFrames.kr(buf_r), trigger: t_reset_pos, loop: 1)];
            
            rand_val = LFNoise1.kr(density).range(0, 1);
            base_pitch = Select.kr(pitch_mode, [speed * lagPitchOffset, lagPitchOffset]);
            interval_plus = (rand_val < pitch_random_plus) * TChoose.kr(grain_trig, positive_intervals);
            interval_minus = (rand_val < pitch_random_minus) * TChoose.kr(grain_trig, negative_intervals);
            final_interval = interval_plus + interval_minus;
            grain_pitch = base_pitch * (2 ** (final_interval/12));

            grain_size = size * (1 + TRand.kr(trig: grain_trig, lo: -1 * size_variation, hi: size_variation));

            ~grainBufFunc = { |buf, pitch, size, vol| GrainBuf.ar(1, grain_trig, size, buf, pitch * grain_direction, pos_sig + jitter_sig, 2, mul: vol); };
            sig_l = ~grainBufFunc.(buf_l, grain_pitch, grain_size, main_vol);
            sig_r = ~grainBufFunc.(buf_r, grain_pitch, grain_size, main_vol);
            sig_l = sig_l + ~grainBufFunc.(buf_l, grain_pitch / 2, grain_size * 2, subharmonic_1_vol);
            sig_r = sig_r + ~grainBufFunc.(buf_r, grain_pitch / 2, grain_size * 2, subharmonic_1_vol);
            sig_l = sig_l + ~grainBufFunc.(buf_l, grain_pitch / 4, grain_size * 2, subharmonic_2_vol);
            sig_r = sig_r + ~grainBufFunc.(buf_r, grain_pitch / 4, grain_size * 2, subharmonic_2_vol);
            sig_l = sig_l + ~grainBufFunc.(buf_l, grain_pitch / 8, grain_size * 2, subharmonic_3_vol);
            sig_r = sig_r + ~grainBufFunc.(buf_r, grain_pitch / 8, grain_size * 2, subharmonic_3_vol);
            sig_l = sig_l + ~grainBufFunc.(buf_l, grain_pitch * 2, grain_size, overtone_1_vol);
            sig_r = sig_r + ~grainBufFunc.(buf_r, grain_pitch * 2, grain_size, overtone_1_vol);
            sig_l = sig_l + ~grainBufFunc.(buf_l, grain_pitch * 4, grain_size, overtone_2_vol);
            sig_r = sig_r + ~grainBufFunc.(buf_r, grain_pitch * 4, grain_size, overtone_2_vol);

            granular_sig = Balance2.ar(sig_l, sig_r, pan_sig);

            sig_mix = (dry_sig * (1 - granular_gain)) + (granular_sig * granular_gain);

            shaped = Shaper.ar(bufSine, sig_mix * sine_drive);
            sig_mix = SelectX.ar(sine_wet, [sig_mix, shaped]);

            // wow and flutter from Stefaan Himpe https://sccode.org/1-5bP & Zackary Scholl
            pw = Phasor.ar(0, BufRateScale.kr(wobble_bufnum), 0, BufFrames.kr(wobble_bufnum));
            BufWr.ar(sig_mix, wobble_bufnum, pw);
            pr = DelayL.ar(Phasor.ar(0, BufRateScale.kr(wobble_bufnum)*rate, 0, BufFrames.kr(wobble_bufnum)), 0.2, 0.2);
            sig_mix = BufRd.ar(2, wobble_bufnum, pr, interpolation:4);

            sig_mix = SelectX.ar(chew_wet, [sig_mix, AnalogChew.ar(sig_mix, chew_depth, chew_freq, chew_variance)]);

            sig_mix = HPF.ar(sig_mix, Lag.kr(hpf));
            sig_mix = LPF.ar(sig_mix, Lag.kr(cutoff));
            
            low = BLowShelf.ar(sig_mix, 250, 5, low_gain);
            high = BHiShelf.ar(sig_mix, 3600, 5, high_gain);
            sig_mix = low + high;

            sig_mix = Compander.ar(sig_mix,sig_mix,0.25)/2;
            
            mid = (sig_mix[0] + sig_mix[1]) * 0.5;
            side = (sig_mix[0] - sig_mix[1]) * 0.5 * width;
            sig_mix = [mid + side, mid - side];

            sig_mix = Balance2.ar(sig_mix[0], sig_mix[1], pan);

            Out.ar(out, sig_mix * gain);
        }).add;

        context.server.sync;

        mixBus = Bus.audio(context.server, 2);

        voices = Array.fill(nvoices, { arg i;
            Synth.new(\synth, [
                \out, mixBus.index, 
                \buf_l, buffersL[i],
                \buf_r, buffersR[i],
                \wobble_bufnum, wobbleBuffers[i]
            ]);
        });

        SynthDef(\shimmer, {
            arg in, out, mix=0.0;
            var pit, snd, orig, hpforig;
            orig = In.ar(in, 2);
            hpforig = HPF.ar(orig, 600);
            pit = LPF.ar(PitchShift.ar(hpforig, 0.13,2,0,1,mul:4), 16000);
		        pit = LeakDC.ar(pit);
            snd = SelectX.ar(mix, [orig, pit]);
            Out.ar(out, snd);
        }).add;

        SynthDef(\fverb, {
            arg in, out, mix=0.0, predelay=0, input_amount=100, input_lowpass_cutoff=10000, input_highpass_cutoff=100, input_diffusion_1=75, input_diffusion_2=62.5, tail_density=70, decay=50, damping=5500, modulator_frequency=1, modulator_depth=0.5;
            var dry = In.ar(in, 2); 
            var wet = Fverb2.ar(dry[0], dry[1], predelay, input_amount, input_lowpass_cutoff, input_highpass_cutoff, input_diffusion_1, input_diffusion_2, LFNoise2.kr(1/5).range(tail_density*0.8,tail_density*1.2), LFNoise2.kr(1/5).range(decay*0.8,decay*1.2), damping, modulator_frequency, modulator_depth);
            var sig = SelectX.ar(mix, [dry, wet]);
            Out.ar(out, sig);
        }).add;
        
        SynthDef(\directOut, {
            arg in, out;
            var sig = In.ar(in, 2);
            Out.ar(out, sig);
        }).add;

        context.server.sync;

        fverbEffect = Synth.new(\fverb, [
            \in, mixBus.index,
            \out, context.out_b.index,
            \mix, 0.5,
            \predelay, 0,
            \input_amount, 100,
            \input_lowpass_cutoff, 10000,
            \input_highpass_cutoff, 100,
            \input_diffusion_1, 75,
            \input_diffusion_2, 62.5,
            \tail_density, 70,
            \decay, 50,
            \damping, 5500,
            \modulator_frequency, 1,
            \modulator_depth, 0.5
        ], context.xg);
        
        shimmerEffect = Synth.new(\shimmer, [
            \in, mixBus.index,
            \out, context.out_b.index,
            \mix, 0.0
        ], context.xg);
        
        directOut = Synth.new(\directOut, [
            \in, mixBus.index,
            \out, context.out_b.index
        ], context.xg);

        
        this.addCommand("shimmer_mix", "f", { arg msg;
            var mix = msg[1];
            if (mix == 0) { 
                shimmerEffect.run(false);
                directOut.run(true);
            } { 
                shimmerEffect.run(true); 
                directOut.run(false);
            };
            shimmerEffect.set(\mix, mix);
        });
        
        this.addCommand("reverb_mix", "f", { arg msg; 
            var mix = msg[1];
            if (mix == 0) { fverbEffect.run(false) } { fverbEffect.run(true) };
            fverbEffect.set(\mix, mix);
            fverbEffect.get(\mix, { |fverbMix|
                if (fverbMix == 0) {
                    directOut.run(true);
                } {
                    directOut.run(false);
                };
            });
        });

        this.addCommand("reverb_predelay", "f", { arg msg; fverbEffect.set(\predelay, msg[1]); });
        this.addCommand("reverb_input_amount", "f", { arg msg; fverbEffect.set(\input_amount, msg[1]); });
        this.addCommand("reverb_lowpass_cutoff", "f", { arg msg; fverbEffect.set(\input_lowpass_cutoff, msg[1]); });
        this.addCommand("reverb_highpass_cutoff", "f", { arg msg; fverbEffect.set(\input_highpass_cutoff, msg[1]); });
        this.addCommand("reverb_diffusion_1", "f", { arg msg; fverbEffect.set(\input_diffusion_1, msg[1]); });
        this.addCommand("reverb_diffusion_2", "f", { arg msg; fverbEffect.set(\input_diffusion_2, msg[1]); });
        this.addCommand("reverb_tail_density", "f", { arg msg; fverbEffect.set(\tail_density, msg[1]); });
        this.addCommand("reverb_decay", "f", { arg msg; fverbEffect.set(\decay, msg[1]); });
        this.addCommand("reverb_damping", "f", { arg msg; fverbEffect.set(\damping, msg[1]); });
        this.addCommand("reverb_modulator_frequency", "f", { arg msg; fverbEffect.set(\modulator_frequency, msg[1]); });
        this.addCommand("reverb_modulator_depth", "f", { arg msg; fverbEffect.set(\modulator_depth, msg[1]); });

        this.addCommand("cutoff", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\cutoff, msg[2]); });
        this.addCommand("hpf", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\hpf, msg[2]); });
        
        this.addCommand("granular_gain", "if", { arg msg; var voice = msg[1] - 1; var gain = msg[2]; voices[voice].set(\granular_gain, gain); });
        this.addCommand("density_mod_amt", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\density_mod_amt, msg[2]); });
        this.addCommand("subharmonics_1", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\subharmonics_1, msg[2]); });
        this.addCommand("subharmonics_2", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\subharmonics_2, msg[2]); });
        this.addCommand("subharmonics_3", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\subharmonics_3, msg[2]); });
        this.addCommand("overtones_1", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\overtones_1, msg[2]); });
        this.addCommand("overtones_2", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\overtones_2, msg[2]); });
        this.addCommand("pitch_mode", "ii", { arg msg; var voice = msg[1] - 1; var mode = msg[2]; voices[voice].set(\pitch_mode, mode); });
        this.addCommand("pitch_offset", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\pitch_offset, msg[2]); });
        this.addCommand("direction_mod", "if", { arg msg; var voice = msg[1] - 1; var mod = msg[2]; voices[voice].set(\direction_mod, mod); });
        this.addCommand("size_variation", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\size_variation, msg[2]); });
        this.addCommand("pitch_random_plus", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\pitch_random_plus, msg[2]); });
        this.addCommand("pitch_random_minus", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\pitch_random_minus, msg[2]); });

        this.addCommand("read", "is", { arg msg; this.readBuf(msg[1] - 1, msg[2]); });
        this.addCommand("seek", "if", { arg msg; var voice = msg[1] - 1; var pos = msg[2]; seek_tasks[voice].stop; voices[voice].set(\pos, pos); voices[voice].set(\t_reset_pos, 1); voices[voice].set(\freeze, 0); });
        this.addCommand("speed", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\speed, msg[2]); });
        this.addCommand("jitter", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\jitter, msg[2]); });
        this.addCommand("size", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\size, msg[2]); });
        this.addCommand("density", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\density, msg[2]); });
        this.addCommand("pan", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\pan, msg[2]); });
        this.addCommand("spread", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\spread, msg[2]); });
        this.addCommand("volume", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\gain, msg[2]); });

        this.addCommand("sine_drive", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\sine_drive, msg[2]); });
        this.addCommand("sine_wet", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\sine_wet, msg[2]); });
        this.addCommand("wobble_wet", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\wobble_wet, msg[2]); });
        this.addCommand("wobble_amp", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\wobble_amp, msg[2]); });
        this.addCommand("wobble_rpm", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\wobble_rpm, msg[2]); });
        this.addCommand("flutter_amp", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\flutter_amp, msg[2]); });
        this.addCommand("flutter_freq", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\flutter_freq, msg[2]); });
        this.addCommand("flutter_var", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\flutter_var, msg[2]); });
        this.addCommand("chew_wet", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\chew_wet, msg[2]); });
        this.addCommand("chew_depth", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\chew_depth, msg[2]); });
        this.addCommand("chew_freq", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\chew_freq, msg[2]); });
        this.addCommand("chew_variance", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\chew_variance, msg[2]); });

        this.addCommand("eq_low_gain", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\low_gain, msg[2]); });
        this.addCommand("eq_high_gain", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\high_gain, msg[2]); });
        
        this.addCommand("width", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\width, msg[2]); });
        
        seek_tasks = Array.fill(nvoices, { arg i; Routine {} });
    }

    free {
        voices.do({ arg voice; voice.free; });
        buffersL.do({ arg b; b.free; });
        buffersR.do({ arg b; b.free; });
        wobbleBuffers.do({ arg b; b.free; });
        fverbEffect.free;
        shimmerEffect.free;
        directOut.free;
        mixBus.free;
        bufSine.free;
    }
}