local font = {}

font.micro_font = {
  D = {
    {1,1,0},
    {1,0,1},
    {1,1,0},
  },
  B = {
    {1,0,0},
    {1,1,1},
    {1,1,1},
  },
  L = {
    {1,0},
    {1,0},
    {1,1},
  },
  C = {
    {1,1,1},
    {1,0,0},
    {1,1,1},
  },
  E = {
    {1,1,1},
    {1,1,0},
    {1,1,1},
  },
  I = {
    {1,0},
    {1,0},
    {1,0},
  },
  R = {
    {1,1,1},
    {1,1,0},
    {1,0,1},
  },
  T = {
    {1,1,1},
    {0,1,0},
    {0,1,0},
  },
  S = {
    {0,1,1},
    {0,1,0},
    {1,1,0},
  },
  X = {
    {0,1,1,1,0,1},
    {0,1,0,1,1,1},
    {1,1,0,1,0,1},
  },
  V = {
    {1,0,1},
    {1,0,1},
    {0,1,0},
  },
  H = {
    {1,0,1},
    {1,1,1},
    {1,0,1},
  },
  Z = {
    {0,1,1,1,1},
    {0,1,0,1,0},
    {1,1,0,1,0},
  },
  F = {
    {1,1,1},
    {1,1,0},
    {1,0,0},
  }
}

local fx_cache = {
  delay_mix = 0,
  reverb_mix = 0,
  shimmer_mix1 = 0,
  tape_mix = 1,
  sine_drive = 0,
  drive = 0,
  wobble_mix = 0,
  chew_depth = 0,
  lossdegrade_mix = 0,
  Width = 100,
  dimension_mix = 0,
  haas = 1,
  rspeed = 0,
  monobass_mix = 1,
  bitcrush_mix = 0,
  ["1cutoff"] = 20000,
  ["2cutoff"] = 20000,
  ["1hpf"] = 20,
  ["2hpf"] = 20
}

function font.update_fx_cache(param_name, value)
  if fx_cache[param_name] ~= nil then
    fx_cache[param_name] = value
  end
end

function font.init_fx_cache()
  for param_name, _ in pairs(fx_cache) do
    if params:lookup_param(param_name) then
      fx_cache[param_name] = params:get(param_name)
    end
  end
end

function font.draw_micro_text_bucketed(P_func, x, y, text, level)
  local cursor_x = x
  for i = 1, #text do
    local char = text:sub(i, i)
    local glyph = font.micro_font[char]
    if glyph then
      local w = #glyph[1]
      for row = 1, 3 do 
        for col = 1, w do 
          if glyph[row][col] == 1 then 
            P_func(level or 1, cursor_x + col - 1, y + row - 1)
          end 
        end 
      end
      cursor_x = cursor_x + w + 1
    else
      cursor_x = cursor_x + 3
    end
  end
end

function font.draw_fx_status_bucketed(P_func)
  local y = 0
  local x = 7

  if fx_cache.delay_mix > 0 then
    font.draw_micro_text_bucketed(P_func, x, y, "D", 1)
    x = x + 4
  end

  if fx_cache.reverb_mix > 0 then
    font.draw_micro_text_bucketed(P_func, x, y, "R", 1)
    x = x + 4
  end

  if fx_cache.shimmer_mix1 > 0 then
    font.draw_micro_text_bucketed(P_func, x, y, "X", 1)
    x = x + 7
  end
  
  if ((fx_cache.tape_mix == 2) or (fx_cache.sine_drive > 0) or (fx_cache.drive > 0) or (fx_cache.wobble_mix > 0) or (fx_cache.chew_depth > 0) or (fx_cache.lossdegrade_mix > 0)) then
    font.draw_micro_text_bucketed(P_func, x, y, "T", 1)
    x = x + 4
  end  
  
  if ((fx_cache.Width ~= 100) or (fx_cache.dimension_mix > 0) or (fx_cache.haas == 2) or (fx_cache.rspeed > 0) or (fx_cache.monobass_mix == 2)) then
    font.draw_micro_text_bucketed(P_func, x, y, "Z", 1)
    x = x + 6
  end  

  if fx_cache.bitcrush_mix > 0 then
    font.draw_micro_text_bucketed(P_func, x, y, "B", 1)
    x = x + 4
  end
  
  if (
    fx_cache["1cutoff"] < 19999 or
    fx_cache["2cutoff"] < 19999 or
    fx_cache["1hpf"] > 20.1 or
    fx_cache["2hpf"] > 20.1
  ) then
    font.draw_micro_text_bucketed(P_func, x, y, "F", 1)
    x = x + 5
  end
end

return font