Engine_twins : CroneEngine {
    classvar nvoices = 2;

    var greyholeEffect;
    var fverbEffect;
    var directOut;
    var <buffersL;
    var <buffersR;
    var <voices;
    var mixBus;
    var <seek_tasks;
    var bufSine;

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
            overtones_1=0, 
            overtones_2=0, 
            cutoff=20000, q=1, hpf=20, hpfrq=1,
            sine_drive=1, sine_wet=0,
            chew_wet=0, chew_depth=0.5, chew_freq=0.5, chew_variance=0.5,
            direction_mod=0,
            size_variation=0,
            low_gain=0, high_gain=0,
            shimmer=0;
 
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
            var grain_pitch;
            var shaped;
            var main_vol = 1 / (1 + subharmonics_1 + subharmonics_2 + overtones_1 + overtones_2);
            var subharmonic_1_vol = subharmonics_1 / (1 + subharmonics_1 + subharmonics_2 + overtones_1 + overtones_2) * 2;
            var subharmonic_2_vol = subharmonics_2 / (1 + subharmonics_1 + subharmonics_2 + overtones_1 + overtones_2) * 2;
            var overtone_1_vol = overtones_1 / (1 + subharmonics_1 + subharmonics_2 + overtones_1 + overtones_2);
            var overtone_2_vol = overtones_2 / (1 + subharmonics_1 + subharmonics_2 + overtones_1 + overtones_2);
            var lagSpeed = Lag.kr(speed);
            var lagPitchOffset = Lag.kr(pitch_offset, 0.5);
            var grain_direction = Select.kr(pitch_mode, [1, Select.kr(speed < 0, [1, -1])]);
            var direction_mod_sig = LFNoise1.kr(density).range(0, 1) < direction_mod;
            var trig_rnd = LFNoise1.kr(density);
            var grain_size;
            var low, high;

            density_mod = density * (2**(trig_rnd * density_mod_amt));
            grain_trig = Impulse.kr(density_mod);

            grain_direction = grain_direction * Select.kr(direction_mod_sig, [1, -1]);

            buf_dur = BufDur.kr(buf_l);

            pan_sig = Lag.kr(TRand.kr(trig: grain_trig,
                lo: spread.neg,
                hi: spread),0.2);

            jitter_sig = TRand.kr(trig: grain_trig,
                lo: buf_dur.reciprocal.neg * jitter,
                hi: buf_dur.reciprocal * jitter);

            buf_pos = Phasor.kr(trig: t_reset_pos,
                rate: buf_dur.reciprocal / ControlRate.ir * Lag.kr(speed),
                resetPos: pos);

            pos_sig = Wrap.kr(Select.kr(freeze, [buf_pos, pos]));

            dry_sig = [PlayBuf.ar(1, buf_l, lagSpeed, loop: 1), PlayBuf.ar(1, buf_r, lagSpeed, loop: 1)];
            dry_sig = Balance2.ar(dry_sig[0], dry_sig[1], Lag.kr(pan));

            grain_pitch = Select.kr(pitch_mode, [Lag.kr(speed) * lagPitchOffset, lagPitchOffset]);

            grain_size = size * (1 + TRand.kr(trig: grain_trig, lo: -1 * size_variation, hi: size_variation));

            sig_l = GrainBuf.ar(1, grain_trig, grain_size, buf_l, grain_pitch * grain_direction, pos_sig + jitter_sig, 2, mul: main_vol);
            sig_r = GrainBuf.ar(1, grain_trig, grain_size, buf_r, grain_pitch * grain_direction, pos_sig + jitter_sig, 2, mul: main_vol);

            sig_l = sig_l + GrainBuf.ar(1, grain_trig, grain_size * 2, buf_l, grain_pitch / 2 * grain_direction, pos_sig + jitter_sig, 2, mul: subharmonic_1_vol);
            sig_r = sig_r + GrainBuf.ar(1, grain_trig, grain_size * 2, buf_r, grain_pitch / 2 * grain_direction, pos_sig + jitter_sig, 2, mul: subharmonic_1_vol);
            sig_l = sig_l + GrainBuf.ar(1, grain_trig, grain_size * 2, buf_l, grain_pitch / 4 * grain_direction, pos_sig + jitter_sig, 2, mul: subharmonic_2_vol);
            sig_r = sig_r + GrainBuf.ar(1, grain_trig, grain_size * 2, buf_r, grain_pitch / 4 * grain_direction, pos_sig + jitter_sig, 2, mul: subharmonic_2_vol);

            sig_l = sig_l + GrainBuf.ar(1, grain_trig, grain_size, buf_l, grain_pitch * 2 * grain_direction, pos_sig + jitter_sig, 2, mul: overtone_1_vol);
            sig_r = sig_r + GrainBuf.ar(1, grain_trig, grain_size, buf_r, grain_pitch * 2 * grain_direction, pos_sig + jitter_sig, 2, mul: overtone_1_vol);
            sig_l = sig_l + GrainBuf.ar(1, grain_trig, grain_size, buf_l, grain_pitch * 4 * grain_direction, pos_sig + jitter_sig, 2, mul: overtone_2_vol);
            sig_r = sig_r + GrainBuf.ar(1, grain_trig, grain_size, buf_r, grain_pitch * 4 * grain_direction, pos_sig + jitter_sig, 2, mul: overtone_2_vol);

            granular_sig = Balance2.ar(sig_l, sig_r, pan + pan_sig);

            granular_gain = granular_gain.clip(0, 1);
            sig_mix = (dry_sig * (1 - granular_gain)) + (granular_sig * granular_gain);

            low = BLowShelf.ar(sig_mix, 375, 5, low_gain);
            high = BHiShelf.ar(sig_mix, 3600, 5, high_gain);
            sig_mix = low + high;

            shaped = Shaper.ar(bufSine, sig_mix * sine_drive);
            sig_mix = SelectX.ar(Lag.kr(sine_wet), [sig_mix, shaped]);

            sig_mix = SelectX.ar(Lag.kr(chew_wet), [sig_mix, AnalogChew.ar(sig_mix, chew_depth, chew_freq, chew_variance)]);

            sig_mix = sig_mix + DelayN.ar(PitchShift.ar(sig_mix, 0.13, 2,0,1,1*shimmer/2), 0.03, 0.03);
            sig_mix = sig_mix + DelayN.ar(PitchShift.ar(sig_mix, 0.1, 4,0,1,0.5*shimmer/2), 0.03, 0.03);

            sig_mix = BHiPass4.ar(sig_mix, Lag.kr(hpf), Lag.kr(hpfrq));
            sig_mix = MoogFF.ar(sig_mix, Lag.kr(cutoff), Lag.kr(q));
            
            sig_mix = Compander.ar(sig_mix,sig_mix,0.25)/2;
            
            Out.ar(out, sig_mix * gain);

        }).add;

        context.server.sync;


        mixBus = Bus.audio(context.server, 2);

        voices = Array.fill(nvoices, { arg i;
            Synth.new(\synth, [
                \out, mixBus.index, 
                \buf_l, buffersL[i],
                \buf_r, buffersR[i],
            ], 
            );
        });
 
        context.server.sync;


        // Define the Greyhole effect SynthDef
        SynthDef(\greyhole, {
            arg in, out, delayTime=2.0, damp=0.1, size=3.0, diff=0.7, feedback=0.2, modDepth=0.0, modFreq=0.1, mix=0.5;
            var dry = In.ar(in, 2);
            var wet = Greyhole.ar(dry, delayTime, damp, size, diff, feedback, modDepth, modFreq);
            var sig = (wet * mix) + (dry * (1 - mix));
            Out.ar(out, sig);
        }).add;
        
        context.server.sync;


        // Define the Fverb effect SynthDef
        SynthDef(\fverb, {
            arg in, out, mix=0.5, predelay=0, input_amount=100, input_lowpass_cutoff=10000, input_highpass_cutoff=100, input_diffusion_1=75, input_diffusion_2=62.5, tail_density=70, decay=50, damping=5500, modulator_frequency=1, modulator_depth=0.5;
            var dry = In.ar(in, 2); 
            var wet = Fverb2.ar(dry[0], dry[1], predelay, input_amount, input_lowpass_cutoff, input_highpass_cutoff, input_diffusion_1, input_diffusion_2, tail_density, decay, damping, modulator_frequency, modulator_depth);
            var sig = (wet * mix) + (dry * (1 - mix)); 
            Out.ar(out, sig);
        }).add;

        context.server.sync;

        // Define the Direct Out SynthDef
        SynthDef(\directOut, {
            arg in, out;
            var sig = In.ar(in, 2);
            Out.ar(out, sig);
        }).add;

        context.server.sync;

        greyholeEffect = Synth.new(\greyhole, [
            \in, mixBus.index,
            \out, context.out_b.index,
            \delayTime, 2.0,
            \damp, 0.1,
            \size, 3.0,
            \diff, 0.7,
            \feedback, 0.2,
            \modDepth, 0.0,
            \modFreq, 1.0,
            \mix, 0.5
        ], context.xg);

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

        context.server.sync;

        // Create the Direct Out Synth
        directOut = Synth.new(\directOut, [
            \in, mixBus.index,
            \out, context.out_b.index
        ], context.xg);
        
        context.server.sync;

        this.addCommand("greyhole_mix", "f", { arg msg; 
            var mix = msg[1];
            if (mix == 0) { greyholeEffect.run(false) } { greyholeEffect.run(true) };
            greyholeEffect.set(\mix, mix); // Set the mix value first

            // Retrieve mix values asynchronously
            greyholeEffect.get(\mix, { |greyholeMix|
                // Activate/deactivate directOut based on condition
                if (greyholeMix == 0) {
                    directOut.run(true);
                } {
                    directOut.run(false);
                };
            });
        });

        this.addCommand("reverb_mix", "f", { arg msg; 
            var mix = msg[1];
            if (mix == 0) { fverbEffect.run(false) } { fverbEffect.run(true) };
            fverbEffect.set(\mix, mix); // Set the mix value first

            // Retrieve mix values asynchronously
            fverbEffect.get(\mix, { |fverbMix|
                // Activate/deactivate directOut based on condition
                if (fverbMix == 0) {
                    directOut.run(true);
                } {
                    directOut.run(false);
                };
            });
        });

        this.addCommand("greyhole_delay_time", "f", { arg msg; greyholeEffect.set(\delayTime, msg[1]); });
        this.addCommand("greyhole_damp", "f", { arg msg; greyholeEffect.set(\damp, msg[1]); });
        this.addCommand("greyhole_size", "f", { arg msg; greyholeEffect.set(\size, msg[1]); });
        this.addCommand("greyhole_diff", "f", { arg msg; greyholeEffect.set(\diff, msg[1]); });
        this.addCommand("greyhole_feedback", "f", { arg msg; greyholeEffect.set(\feedback, msg[1]); });
        this.addCommand("greyhole_mod_depth", "f", { arg msg; greyholeEffect.set(\modDepth, msg[1]); });
        this.addCommand("greyhole_mod_freq", "f", { arg msg; greyholeEffect.set(\modFreq, msg[1]); });

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
        this.addCommand("q", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\q, msg[2]); });
        this.addCommand("hpf", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\hpf, msg[2]); });
        this.addCommand("hpfrq", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\hpfrq, msg[2]); });
        
        this.addCommand("granular_gain", "if", { arg msg; var voice = msg[1] - 1; var gain = msg[2]; voices[voice].set(\granular_gain, gain); });
        this.addCommand("density_mod_amt", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\density_mod_amt, msg[2]); });
        this.addCommand("shimmer", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\shimmer, msg[2]); });
        this.addCommand("subharmonics_1", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\subharmonics_1, msg[2]); });
        this.addCommand("subharmonics_2", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\subharmonics_2, msg[2]); });
        this.addCommand("overtones_1", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\overtones_1, msg[2]); });
        this.addCommand("overtones_2", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\overtones_2, msg[2]); });
        this.addCommand("pitch_mode", "ii", { arg msg; var voice = msg[1] - 1; var mode = msg[2]; voices[voice].set(\pitch_mode, mode); });
        this.addCommand("pitch_offset", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\pitch_offset, msg[2]); });
        this.addCommand("direction_mod", "if", { arg msg; var voice = msg[1] - 1; var mod = msg[2]; voices[voice].set(\direction_mod, mod); });
        this.addCommand("size_variation", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\size_variation, msg[2]); });

        this.addCommand("read", "is", { arg msg; this.readBuf(msg[1] - 1, msg[2]); });
        this.addCommand("seek", "if", { arg msg; var voice = msg[1] - 1; var pos; seek_tasks[voice].stop; pos = msg[2]; voices[voice].set(\pos, pos); voices[voice].set(\t_reset_pos, 1); voices[voice].set(\freeze, 0);});
        this.addCommand("speed", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\speed, msg[2]); });
        this.addCommand("jitter", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\jitter, msg[2]); });
        this.addCommand("size", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\size, msg[2]); });
        this.addCommand("density", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\density, msg[2]); });
        this.addCommand("pan", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\pan, msg[2]); });
        this.addCommand("spread", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\spread, msg[2]); });
        this.addCommand("volume", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\gain, msg[2]); });

        this.addCommand("sine_drive", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\sine_drive, msg[2]); });
        this.addCommand("sine_wet", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\sine_wet, msg[2]); });
        this.addCommand("chew_wet", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\chew_wet, msg[2]); });
        this.addCommand("chew_depth", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\chew_depth, msg[2]); });
        this.addCommand("chew_freq", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\chew_freq, msg[2]); });
        this.addCommand("chew_variance", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\chew_variance, msg[2]); });
        
        this.addCommand("eq_low_gain", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\low_gain, msg[2]); });
        this.addCommand("eq_high_gain", "if", { arg msg; var voice = msg[1] - 1; voices[voice].set(\high_gain, msg[2]); });

        seek_tasks = Array.fill(nvoices, { arg i; Routine {} });
    }

    free {
        voices.do({ arg voice; voice.free; });
        buffersL.do({ arg b; b.free; });
        buffersR.do({ arg b; b.free; });
        greyholeEffect.free;
        fverbEffect.free;
        directOut.free;
        mixBus.free;
        bufSine.free;
    }
}