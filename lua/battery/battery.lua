local M = {}

local L = require("plenary.log")
local powershell = require("battery.powershell")
local pmset = require("battery.pmset")
local acpi = require("battery.acpi")
local config = require("battery.config")

-- TODO check for icons and if not available fallback to text
-- TODO allow user to select no icons
-- TODO maybe autodetect icons?

local log = L.new({ plugin = "battery" })

-- https://www.nerdfonts.com/cheat-sheet
local no_battery_icon = "󰂎 "
local plugged_icon = "󱐋 "
local discharging_battery_icons = {
  { "󰁺 ", 10 },
  { "󰁻 ", 20 },
  { "󰁼 ", 30 },
  { "󰁽 ", 40 },
  { "󰁾 ", 50 },
  { "󰁿 ", 60 },
  { "󰂀 ", 70 },
  { "󰂁 ", 80 },
  { "󰂂 ", 90 },
  { "󰁹 ", 100 },
}

-- TODO maybe store the update time here?
local battery_status = {
  percent_charge_remaining = 0,
  battery_count = 0,
  ac_power = nil,
}

-- Gets the last updated battery information
-- TODO may add the ability to ask for it to be updated right now
local function get_battery_status()
  return battery_status
end

-- This maps to a timer sequence number in the utils module so the user
-- can reload the battery module and we can detect the old job is still running.
local timer = nil

-- Select the battery info job to run based on platform and what programs
-- are available
local function select_job()
  if vim.fn.has("win32") and vim.fn.executable("powershell") == 1 then
    log.debug("windows powershell battery job")
    return powershell.get_battery_info_job
  elseif vim.fn.executable("pmset") == 1 then
    log.debug("pmset battery job")
    return pmset.get_battery_info_job
  elseif vim.fn.executable("acpi") == 1 then
    log.debug("acpi battery job")
    return acpi.get_battery_info_job
  else
    log.debug("no battery job")
  end
end

local function timer_loop()
  vim.defer_fn(function()
    log.debug(timer .. " is running now")
    local job_function = select_job()

    if job_function then
      job_function(battery_status):start()
    end

    -- When the user reloads the battery module the job can just keep running. In order to stop it
    -- the user must call stop_timer. All this does is increments the timer sequence number. Whenever
    -- the running job knows that the sequence number no longer matches it will stop running,
    -- regardless of whether the user made a new job or not.

    if require("util.timers").get_current() ~= timer then
      log.info("Update job stopping due to newer timer.")
    else
      timer_loop()
    end
  end, config.current.update_rate_seconds * 1000)
end

-- local function stop_timer()
--   timer = require("util.timers").get_next()
--   log.debug("Incremented timer to " .. timer .. " to stop the battery update job")
-- end

local function start_timer()
  timer = require("util.timers").get_next()

  -- Always call the job immediately before starting the timed loop
  local job_function = select_job()

  if job_function then
    job_function(battery_status):start()
  end

  timer_loop()
  log.debug("start timer seq no " .. timer)
end

local function setup(user_opts)
  config.from_user_opts(user_opts)

  local config_update_rate_seconds = tonumber(config.current.update_rate_seconds)
  if config_update_rate_seconds then
    if config_update_rate_seconds < 10 then
      vim.notify("Update rate less than 10 seconds is not recommended", vim.log.levels.WARN)
    end
  end

  start_timer()
end

-- Convert percentage charge to icon given a table of icons
-- and max charge for that icon
local function icon_for_percentage(p, icon_table)
  for _, icon in ipairs(icon_table) do
    if tonumber(p) <= tonumber(icon[2]) then
      return icon[1]
    end
  end
  vim.notify("No icon found for percentage " .. p)
  return "!"
end

local function discharging_battery_icon_for_percent(p)
  return icon_for_percentage(p, discharging_battery_icons)
end

local function get_status_line()
  if battery_status.battery_count == 0 then
    return no_battery_icon
  else
    local ac_power = battery_status.ac_power
    local battery_percent = battery_status.percent_charge_remaining

    local plug_icon = ""
    if ac_power then
      plug_icon = plugged_icon
    end

    local percent = battery_percent .. "%%"

    local icon = discharging_battery_icon_for_percent(battery_percent)

    local message = ""
    if config.show_message_low_battery == true then
      if not ac_power and battery_percent <= config.low_battery then
        message = " | Conecte o carregador"
      end
    end

    return plug_icon .. icon .. percent .. message
  end
end

M.setup = setup
M.get_battery_status = get_battery_status
M.get_status_line = get_status_line
return M
