local macro = {}
local utils = include("lib/utils")
local is_param_locked = utils.is_param_locked
local stop_metro_safe = utils.stop_metro_safe

local RANGES = {
    speed   = {-1.99, 1.99},
    jitter  = {0,     1999},
    size    = {150,   599},
    density = {0.1,   49},
}
local PARAMS  = {"speed", "size", "jitter", "density"}
local TRACKS  = 2
local MARGIN  = 0.05
local LFO_DEPTH_FRACTION = 0.15
local TOLERANCE = 0.01
local FPS = 30

local m_min, m_abs = math.min, math.abs
local u_linlin = util.linlin

local lfo_ref
function macro.set_context(ctx) lfo_ref = ctx.lfo end

local anim_metro = metro.init()

local function clamped_range(suffix)
    local lo, hi = RANGES[suffix][1], RANGES[suffix][2]
    local margin = (hi - lo) * MARGIN
    return lo + margin, hi - margin
end

local function animate_lfo_job(job, factor)
    local current   = params:get(job.param)
    local new_value = current + (job.target - current) * factor
    local range      = job.lfo_max - job.lfo_min
    local max_safe   = m_min(new_value - job.lfo_min, job.lfo_max - new_value) * 2
    local safe_depth = m_min(LFO_DEPTH_FRACTION * range, max_safe)
    local new_offset = u_linlin(job.lfo_min, job.lfo_max, -1, 1, new_value)
    local new_depth  = safe_depth / range * 100
    local offset = params:get(job.offset_id)
    params:set(job.offset_id, offset + (new_offset - offset) * factor)
    local depth = params:get(job.depth_id)
    params:set(job.depth_id, depth + (new_depth - depth) * factor)
    params:set(job.param, new_value)
    return m_abs(new_value - job.target) < TOLERANCE
end

local function animate_plain_job(job, factor)
    local current   = params:get(job.param)
    local new_value = current + (job.target - current) * factor
    params:set(job.param, new_value)
    return m_abs(new_value - job.target) < TOLERANCE
end

local function build_jobs(multiplier)
    local going_up = multiplier > 1
    local jobs = {}
    for track = 1, TRACKS do
        for _, suffix in ipairs(PARAMS) do
            if not is_param_locked(track, suffix) then
                local param   = track .. suffix
                local current = params:get(param)
                local lo, hi  = clamped_range(suffix)
                local lfo_min, lfo_max
                if lfo_ref then
                    lfo_min, lfo_max = lfo_ref.get_parameter_range(param)
                    if lfo_min and lfo_min > lo then lo = lfo_min end
                    if lfo_max and lfo_max < hi then hi = lfo_max end
                end
                local target = going_up
                    and m_min(current * multiplier, hi)
                    or  math.max(current * multiplier, lo)
                local job = {param = param, target = target}
                local lfo_index = lfo_ref and lfo_ref.get_lfo_for_param(param)
                if lfo_index and lfo_min and lfo_max and lfo_max > lfo_min then
                    local keys = lfo_ref.keys
                    job.offset_id = keys.offset[lfo_index]
                    job.depth_id  = keys.depth[lfo_index]
                    job.lfo_min, job.lfo_max = lfo_min, lfo_max
                end
                jobs[#jobs + 1] = job
            end
        end
    end
    return jobs
end

local function adjust_params(multiplier)
    stop_metro_safe(anim_metro)
    local jobs = build_jobs(multiplier)
    if #jobs == 0 then return end
    local steps = utils.STEP_COUNTS[params:get("steps")] or 20
    anim_metro.time  = 1 / FPS
    anim_metro.event = function(count)
        local factor   = count / steps
        local all_done = true
        for _, job in ipairs(jobs) do
            local done
            if job.offset_id then
                done = animate_lfo_job(job, factor)
            else
                done = animate_plain_job(job, factor)
            end
            if not done then all_done = false end
        end
        if all_done or count >= steps then stop_metro_safe(anim_metro) end
    end
    utils.metro_start(anim_metro)
end

function macro.macro_more() adjust_params(1.5)  end
function macro.macro_less() adjust_params(0.66) end

return macro