local function random_float(l, h)
    return l + math.random() * (h - l)
end

local function randomize_params()

    --DELAY
    if math.random() <= 0.65 then params:set("delay_h", 0) else params:set("delay_h", math.random(0, 50)) end
    params:set("delay_rate", random_float(0.3, 1.5))
    params:set("delay_feedback", math.random(30, 85))

    --GREYHOLE      
    params:set("greyhole_mix", random_float(0.30, 0.70))
    params:set("time", random_float(2, 4))
    params:set("size", random_float(3, 5))
    params:set("mod_depth", random_float(0.75, 1))
    params:set("mod_freq", random_float(0.3, 0.9))
    params:set("diff", random_float(0.50, 0.85))
    params:set("feedback", random_float(0.15, 0.75))
    params:set("damp", random_float(0.05, 0.3))
    
    --FVERB
    params:set("reverb_mix", math.random(5, 40))
    params:set("reverb_predelay", math.random(0, 85))
    params:set("reverb_lowpass_cutoff", math.random(8000, 12000))
    params:set("reverb_highpass_cutoff", math.random(100, 300))
    params:set("reverb_diffusion_1", math.random(60, 90))
    params:set("reverb_diffusion_2", math.random(60, 90))
    params:set("reverb_tail_density", math.random(50, 90))
    params:set("reverb_decay", math.random(60, 95))
    params:set("reverb_damping", math.random(5500, 7500))
    params:set("reverb_modulator_frequency", random_float(0.2, 1))
    params:set("reverb_modulator_depth", math.random(60, 100))
    
    --OTHERS
    params:set("density_mod_amt", math.random(0, 30))
    params:set("subharmonics_1", random_float(0, 0.15))
    params:set("subharmonics_2", random_float(0, 0.15))
    params:set("overtones_1", random_float(0, 0.15))
    params:set("overtones_2", random_float(0, 0.15))

end

return {
    randomize_params = randomize_params
}