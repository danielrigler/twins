Engine_twins : CroneEngine {
	classvar nvoices = 7;

	var pg;
	var effect;
	var <buffersL;
	var <buffersR;
	var <voices;
	var mixBus;
	var <phases;
	var <levels;

	var <seek_tasks;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	// disk read
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
			Buffer.alloc(
				context.server,
				context.server.sampleRate * 1,
			);
		});

		buffersR = Array.fill(nvoices, { arg i;
			Buffer.alloc(
				context.server,
				context.server.sampleRate * 1,
			);
		});

		// Define the SynthDef

SynthDef(\synth, {
	arg out, phase_out, level_out, buf_l, buf_r,
	gate=0, pos=0, speed=1, jitter=0,
	size=0.1, density=20, density_mod_amt=0, pitch=1, pan=0, spread=0, gain=1, envscale=1,
	freeze=0, t_reset_pos=0,
	granular_gain=1; // Add granular_gain parameter

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
	var dry_sig; // Dry signal
	var granular_sig; // Granular signal
	var env;
	var level;

	// Density modulation
	var trig_rnd = LFNoise1.kr(density);
	density_mod = density * (2**(trig_rnd * density_mod_amt));
	grain_trig = Impulse.kr(density_mod);

	buf_dur = BufDur.kr(buf_l);

	pan_sig = TRand.kr(trig: grain_trig,
		lo: spread.neg,
		hi: spread);

	jitter_sig = TRand.kr(trig: grain_trig,
		lo: buf_dur.reciprocal.neg * jitter,
		hi: buf_dur.reciprocal * jitter);

	buf_pos = Phasor.kr(trig: t_reset_pos,
		rate: buf_dur.reciprocal / ControlRate.ir * speed,
		resetPos: pos);

	pos_sig = Wrap.kr(Select.kr(freeze, [buf_pos, pos]));

	// Dry signal (unchanged)
	dry_sig = [PlayBuf.ar(1, buf_l, speed, loop: 1), PlayBuf.ar(1, buf_r, speed, loop: 1)];

	// Apply pan to the dry signal
	dry_sig = Balance2.ar(dry_sig[0], dry_sig[1], pan + pan_sig);

	// Granular signal
	sig_l = GrainBuf.ar(1, grain_trig, size, buf_l, pitch, pos_sig + jitter_sig, 2);
	sig_r = GrainBuf.ar(1, grain_trig, size, buf_r, pitch, pos_sig + jitter_sig, 2);
	granular_sig = Balance2.ar(sig_l, sig_r, pan + pan_sig);

	env = EnvGen.kr(Env.asr(1, 1, 1), gate: gate, timeScale: envscale);

	level = env;

	// Mix dry and granular signals
	granular_gain = granular_gain.clip(0, 1); // Ensure granular_gain is within bounds
	sig_mix = (dry_sig * (1 - granular_gain)) + (granular_sig * granular_gain);

	// Output the mixed signal
	Out.ar(out, sig_mix * level * gain);
	Out.kr(phase_out, pos_sig);
	Out.kr(level_out, level);
}).add;


		// Define the effect SynthDef
		SynthDef(\effect, {
			arg in, out, mix=0.5, predelay=0, input_amount=100, input_lowpass_cutoff=10000, input_highpass_cutoff=100, input_diffusion_1=75, input_diffusion_2=62.5, tail_density=70, decay=50, damping=5500, modulator_frequency=1, modulator_depth=0.5;
			var dry = In.ar(in, 2); // Capture the dry signal from the input bus
			var wet = Fverb2.ar(
				dry[0], dry[1], // Stereo input
				predelay,
				input_amount,
				input_lowpass_cutoff,
				input_highpass_cutoff,
				input_diffusion_1,
				input_diffusion_2,
				tail_density,
				decay,
				damping,
				modulator_frequency,
				modulator_depth
			);
			var sig = (wet * mix) + (dry * (1 - mix)); // Mix dry and wet signals
			Out.ar(out, sig); // Output the mixed signal
		}).add;

		context.server.sync;

		// mix bus for all synth outputs
		mixBus = Bus.audio(context.server, 2);

		effect = Synth.new(\effect, [\in, mixBus.index, \out, context.out_b.index], target: context.xg);

		phases = Array.fill(nvoices, { arg i; Bus.control(context.server); });
		levels = Array.fill(nvoices, { arg i; Bus.control(context.server); });

		pg = ParGroup.head(context.xg);

		voices = Array.fill(nvoices, { arg i;
			Synth.new(\synth, [
				\out, mixBus.index,
				\phase_out, phases[i].index,
				\level_out, levels[i].index,
				\buf_l, buffersL[i],
				\buf_r, buffersR[i],
				\granular_gain, 1, // Initialize granular_gain
				\density_mod_amt, 0, // Initialize density_mod_amt
			], target: pg);
		});

		context.server.sync;

		// Add commands
		this.addCommand("granular_gain", "f", { arg msg;
			var gain = msg[1];
			voices.do({ arg voice; voice.set(\granular_gain, gain); });
		});

		this.addCommand("density_mod_amt", "if", { arg msg;
			var voice = msg[1] - 1;
			voices[voice].set(\density_mod_amt, msg[2]);
		});
		
		this.addCommand("granular_gain_l", "if", { arg msg;
	var voice = msg[1] - 1;
	var gain = msg[2];
	voices[voice].set(\granular_gain_l, gain);
});

this.addCommand("granular_gain_r", "if", { arg msg;
	var voice = msg[1] - 1;
	var gain = msg[2];
	voices[voice].set(\granular_gain_r, gain);
});

		this.addCommand("reverb_mix", "f", { arg msg; effect.set(\mix, msg[1]); });
		this.addCommand("reverb_predelay", "f", { arg msg; effect.set(\predelay, msg[1]); });
		this.addCommand("reverb_input_amount", "f", { arg msg; effect.set(\input_amount, msg[1]); });
		this.addCommand("reverb_lowpass_cutoff", "f", { arg msg; effect.set(\input_lowpass_cutoff, msg[1]); });
		this.addCommand("reverb_highpass_cutoff", "f", { arg msg; effect.set(\input_highpass_cutoff, msg[1]); });
		this.addCommand("reverb_diffusion_1", "f", { arg msg; effect.set(\input_diffusion_1, msg[1]); });
		this.addCommand("reverb_diffusion_2", "f", { arg msg; effect.set(\input_diffusion_2, msg[1]); });
		this.addCommand("reverb_tail_density", "f", { arg msg; effect.set(\tail_density, msg[1]); });
		this.addCommand("reverb_decay", "f", { arg msg; effect.set(\decay, msg[1]); });
		this.addCommand("reverb_damping", "f", { arg msg; effect.set(\damping, msg[1]); });
		this.addCommand("reverb_modulator_frequency", "f", { arg msg; effect.set(\modulator_frequency, msg[1]); });
		this.addCommand("reverb_modulator_depth", "f", { arg msg; effect.set(\modulator_depth, msg[1]); });

		this.addCommand("read", "is", { arg msg;
			this.readBuf(msg[1] - 1, msg[2]);
		});

		this.addCommand("seek", "if", { arg msg;
			var voice = msg[1] - 1;
			var lvl, pos;
			var seek_rate = 1 / 750;

			seek_tasks[voice].stop;

			// TODO: async get
			lvl = levels[voice].getSynchronous();

			if (false, { // disable seeking until fully implemented
				var step;
				var target_pos;

				// TODO: async get
				pos = phases[voice].getSynchronous();
				voices[voice].set(\freeze, 1);

				target_pos = msg[2];
				step = (target_pos - pos) * seek_rate;

				seek_tasks[voice] = Routine {
					while({ abs(target_pos - pos) > abs(step) }, {
						pos = pos + step;
						voices[voice].set(\pos, pos);
						seek_rate.wait;
					});

					voices[voice].set(\pos, target_pos);
					voices[voice].set(\freeze, 0);
					voices[voice].set(\t_reset_pos, 1);
				};

				seek_tasks[voice].play();
			}, {
				pos = msg[2];

				voices[voice].set(\pos, pos);
				voices[voice].set(\t_reset_pos, 1);
				voices[voice].set(\freeze, 0);
			});
		});

		this.addCommand("gate", "ii", { arg msg;
			var voice = msg[1] - 1;
			voices[voice].set(\gate, msg[2]);
		});

		this.addCommand("speed", "if", { arg msg;
			var voice = msg[1] - 1;
			voices[voice].set(\speed, msg[2]);
		});

		this.addCommand("jitter", "if", { arg msg;
			var voice = msg[1] - 1;
			voices[voice].set(\jitter, msg[2]);
		});

		this.addCommand("size", "if", { arg msg;
			var voice = msg[1] - 1;
			voices[voice].set(\size, msg[2]);
		});

		this.addCommand("density", "if", { arg msg;
			var voice = msg[1] - 1;
			voices[voice].set(\density, msg[2]);
		});

		this.addCommand("pitch", "if", { arg msg;
			var voice = msg[1] - 1;
			voices[voice].set(\pitch, msg[2]);
		});

		this.addCommand("pan", "if", { arg msg;
			var voice = msg[1] - 1;
			voices[voice].set(\pan, msg[2]);
		});

		this.addCommand("spread", "if", { arg msg;
			var voice = msg[1] - 1;
			voices[voice].set(\spread, msg[2]);
		});

		this.addCommand("volume", "if", { arg msg;
			var voice = msg[1] - 1;
			voices[voice].set(\gain, msg[2]);
		});

		this.addCommand("envscale", "if", { arg msg;
			var voice = msg[1] - 1;
			voices[voice].set(\envscale, msg[2]);
		});

		nvoices.do({ arg i;
			this.addPoll(("phase_" ++ (i+1)).asSymbol, {
				var val = phases[i].getSynchronous;
				val
			});

			this.addPoll(("level_" ++ (i+1)).asSymbol, {
				var val = levels[i].getSynchronous;
				val
			});
		});

		seek_tasks = Array.fill(nvoices, { arg i;
			Routine {}
		});
	}

	free {
		voices.do({ arg voice; voice.free; });
		phases.do({ arg bus; bus.free; });
		levels.do({ arg bus; bus.free; });
		buffersL.do({ arg b; b.free; });
		buffersR.do({ arg b; b.free; });
		effect.free;
		mixBus.free;
	}
}