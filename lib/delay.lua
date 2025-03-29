local sc={}

function sc.init()
  audio.level_cut(1.0)
  audio.level_adc_cut(0)
  audio.level_eng_cut(1)

  softcut.level_slew_time(1,0.25)
  softcut.level_input_cut(1,1,1.0)
  softcut.level_input_cut(2,2,1.0)
  softcut.pan(1,-1)
  softcut.pan(2,1)
  
  for i=1,2 do
    softcut.level(i,1.0)
    softcut.play(i,1)
    softcut.rate(i,1)
    softcut.rate_slew_time(i,0.25)
    softcut.loop_start(i,1+i*10)
    softcut.loop_end(i,1.5+i*10)
    softcut.loop(i,1)
    softcut.fade_time(i,0.1)
    softcut.rec(i,1)
    softcut.rec_level(i,1)
    softcut.pre_level(i,0.75)
    softcut.position(i,1)
    softcut.enable(i,1)

    softcut.filter_dry(i,0.125);
    softcut.filter_fc(i,1200);
    softcut.filter_lp(i,0);
    softcut.filter_bp(i,1.0);
    softcut.filter_rq(i,2.0);
  end

params:add{
    id = "tap_tempo",
    name = "Tap Tempo",
    type = "trigger",
    action = function()
        local current_time = util.time()
        if last_tap_time then
            local tempo = 60 / (current_time - last_tap_time)
            local delay_time = 60 / tempo
            params:set("delay_rate", delay_time)
        end
        last_tap_time = current_time
    end
}

params:add{
  id = "delay_h",
  name = "Mix",
  type = "control",
  controlspec = controlspec.new(0, 100, 'lin', 1, 0, "%"),  
  formatter = function(param) return tostring(param:get()) .. "%" end,
  action = function(x)
    local level = x / 100  
    softcut.level(1, level * math.random(90, 110) / 100)
    softcut.level(2, level * math.random(90, 110) / 100)
  end
}
  
params:add{
  id = "delay_rate",
  name = "Time",
  type = "control",
  controlspec = controlspec.new(0.15, 4, 'exp', 0, 0.5, "s"),
  formatter = function(param)
    local x = param:get()
    return string.format("%.2f s", x)
  end,
  action = function(x)
    local rate = 0.5 / x
    softcut.rate(1, rate * math.random(90, 110) / 100)
    softcut.rate(2, rate * math.random(90, 110) / 100)
  end
}

params:add{
  id = "delay_feedback",
  name = "Feedback",
  type = "control",
  controlspec = controlspec.new(0, 100, 'lin', 1, 80, "%"),  
  formatter = function(param) return tostring(param:get()) .. "%" end,
  action = function(x)
    local level = x / 100 
    softcut.pre_level(1, level * math.random(90, 110) / 100)
    softcut.pre_level(2, level * math.random(90, 110) / 100)
  end
}

end
return sc