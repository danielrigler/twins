local function random_float(l, h)
    return l + math.random() * (h - l)
end

local function randomize_params()

    --DELAY
    if math.random() <= 0.3 then params:set("delay_h", 0) else params:set("delay_h", math.random(15, 70)) end
    params:set("delay_rate", random_float(0.2, 1))
    params:set("delay_feedback", math.random(30, 90))

    --GREYHOLE      
    params:set("greyhole_mix", random_float(0, 0.7))
    params:set("time", random_float(2, 8))
    params:set("size", random_float(2, 5))
    params:set("mod_depth", random_float(0.2, 1))
    params:set("mod_freq", random_float(0.1, 2))
    params:set("diff", random_float(0.30, 0.95))
    params:set("feedback", random_float(0.1, 0.6))
    params:set("damp", random_float(0.05, 0.4))
    
    --FVERB
    params:set("reverb_mix", math.random(0, 40))
    params:set("reverb_predelay", math.random(0, 150))
    params:set("reverb_lowpass_cutoff", math.random(2000, 11000))
    params:set("reverb_highpass_cutoff", math.random(20, 300))
    params:set("reverb_diffusion_1", math.random(50, 95))
    params:set("reverb_diffusion_2", math.random(50, 95))
    params:set("reverb_tail_density", math.random(40, 95))
    params:set("reverb_decay", math.random(40, 90))
    params:set("reverb_damping", math.random(2500, 8500))
    params:set("reverb_modulator_frequency", random_float(0.1, 2.5))
    params:set("reverb_modulator_depth", math.random(20, 100))
    
     --EXTRAS
    if math.random() <= 0.5 then params:set("density_mod_amt", 0) else params:set("density_mod_amt", math.random(0, 50)) end
    if math.random() <= 0.75 then params:set("subharmonics_1", 0) else params:set("subharmonics_1", random_float(0, 0.5)) end
    if math.random() <= 0.75 then params:set("subharmonics_2", 0) else params:set("subharmonics_2", random_float(0, 0.5)) end   
    if math.random() <= 0.75 then params:set("overtones_1", 0) else params:set("overtones_1", random_float(0, 0.5)) end
    if math.random() <= 0.75 then params:set("overtones_2", 0) else params:set("overtones_2", random_float(0, 0.5)) end
    if math.random() <= 0.4 then params:set("1direction_mod", 0) else params:set("1direction_mod", math.random(0, 30)) end
    if math.random() <= 0.4 then params:set("2direction_mod", 0) else params:set("2direction_mod", math.random(0, 30)) end
    if math.random() <= 0.5 then params:set("sine_wet", 0) else params:set("sine_wet", math.random(1, 25)) end
    if math.random() <= 0.5 then params:set("sine_drive", 1) else params:set("sine_drive", random_float(0.5, 1.5)) end
    if math.random() <= 0.8 then params:set("1granular_gain", 100) else params:set("1granular_gain", math.random(80, 100)) end
    if math.random() <= 0.8 then params:set("2granular_gain", 100) else params:set("2granular_gain", math.random(80, 100)) end
    if math.random() <= 0.75 then params:set("chew_wet", 0) else params:set("chew_wet", math.random(0, 25)) end
    if math.random() <= 0.5 then params:set("chew_depth", 0.4) else params:set("chew_depth", random_float(0.2, 0.5)) end
    if math.random() <= 0.5 then params:set("chew_freq", 0.4) else params:set("chew_freq", random_float(0.2, 0.5)) end
    if math.random() <= 0.5 then params:set("chew_variance", 0.5) else params:set("chew_variance", random_float(0.4, 0.8)) end
    if math.random() <= 0.4 then params:set("1size_variation", 0) else params:set("1size_variation", math.random(0, 30)) end  
    if math.random() <= 0.4 then params:set("2size_variation", 0) else params:set("2size_variation", math.random(0, 30)) end
end

return {
    randomize_params = randomize_params
}