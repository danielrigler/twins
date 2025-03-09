local function random_float(l, h)
    return l + math.random() * (h - l)
end

local function randomize_params()

    --DELAY
    if math.random() <= 0.5 then params:set("delay_h", 0) else params:set("delay_h", math.random(20, 80)) end
    params:set("delay_rate", random_float(0.2, 1))
    params:set("delay_feedback", math.random(30, 90))

    --GREYHOLE      
    params:set("greyhole_mix", random_float(0, 0.7))
    params:set("time", random_float(2, 8))
    params:set("size", random_float(2, 5))
    params:set("mod_depth", random_float(0.5, 1))
    params:set("mod_freq", random_float(0.1, 1.5))
    params:set("diff", random_float(0.50, 0.9))
    params:set("feedback", random_float(0.1, 0.75))
    params:set("damp", random_float(0.05, 0.3))
    
    --FVERB
    params:set("reverb_mix", math.random(0, 35))
    params:set("reverb_predelay", math.random(0, 300))
    params:set("reverb_lowpass_cutoff", math.random(2000, 12000))
    params:set("reverb_highpass_cutoff", math.random(75, 500))
    params:set("reverb_diffusion_1", math.random(50, 95))
    params:set("reverb_diffusion_2", math.random(50, 95))
    params:set("reverb_tail_density", math.random(40, 95))
    params:set("reverb_decay", math.random(40, 95))
    params:set("reverb_damping", math.random(2500, 8000))
    params:set("reverb_modulator_frequency", random_float(0.1, 1.5))
    params:set("reverb_modulator_depth", math.random(30, 100))
    
     --EXTRAS
    if math.random() <= 0.5 then params:set("density_mod_amt", 0) else params:set("density_mod_amt", math.random(0, 50)) end
    if math.random() <= 0.75 then params:set("subharmonics_1", 0) else params:set("subharmonics_1", random_float(0, 0.5)) end
    if math.random() <= 0.75 then params:set("subharmonics_2", 0) else params:set("subharmonics_2", random_float(0, 0.5)) end   
    if math.random() <= 0.75 then params:set("overtones_1", 0) else params:set("overtones_1", random_float(0, 0.5)) end
    if math.random() <= 0.75 then params:set("overtones_2", 0) else params:set("overtones_2", random_float(0, 0.5)) end    
end

return {
    randomize_params = randomize_params
}