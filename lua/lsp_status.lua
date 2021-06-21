--[[ This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/. ]]

local lsp = vim.lsp
local clients = {} -- key by client ID
local config = {spinner = {'-', '\\', '|', '/'}, interval = 130}

local function clean_stopped_clients()
  for id, client in ipairs(clients) do
    if lsp.client_is_stopped(id) then
      if client.timer then
        client.timer:close()
      end
      table.remove(clients, id)
    end
  end
end

local function find_index(tb, value)
  for i, v in ipairs(tb) do
    if v == value then
      return i
    end
  end
end

local function progress_callback(_, _, msg, client_id)
  local val = msg.value
  if val.kind == 'begin' then
    table.insert(clients[client_id].jobs, msg.token)
    if not clients[client_id].timer then
      local timer = vim.loop.new_timer()
      clients[client_id].timer = timer
      clients[client_id].frame = 1
      timer:start(config.interval, config.interval, vim.schedule_wrap(function()
        clients[client_id].frame =
          clients[client_id].frame < #config.spinner and
            clients[client_id].frame + 1 or 1
      end))
    end
  elseif val.kind == 'end' then
    local jobs = clients[client_id].jobs
    local index = find_index(jobs, msg.token)
    table.remove(jobs, index)
    if vim.tbl_isempty(jobs) then
      clients[client_id].timer:stop()
      clients[client_id].timer:close()
      clients[client_id].timer = nil
    end
  end
end

local function get_clients_by_bufnr(bufnr)
  local ids = {}
  for id, client in ipairs(clients) do
    if vim.tbl_contains(client.buffers, bufnr) then
      table.insert(ids, id)
    end
  end
  return ids
end

local function get_status(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  clean_stopped_clients()
  local status = ''
  local ids = get_clients_by_bufnr(bufnr)
  for i, id in ipairs(ids) do
    local client = clients[id]
    status = string.format('%s%s', status, client.name)
    if not vim.tbl_isempty(client.jobs) then
      status = string.format('%s %s', status, config.spinner[client.frame])
    end
    if i < vim.tbl_count(ids) then
      status = string.format('%s ', status)
    end
  end
  return status
end

local function init_capabilities(capabilities)
  vim.validate {
    capabilities = {
      capabilities, function(c)
        if not type(c) == 'table' then
          return false
        end
        if type(c.window) == 'table' then
          return true
        end
      end, 'capabilities.window = table',
    },
  }
  if not capabilities.window.workDoneProgress then
    capabilities.window.workDoneProgress = true
  end
end

local function setup(options)
  vim.validate {
    config = {
      options, function(c)
        if c and type(c) ~= 'table' then
          return false
        end
        if c and c.spinner and type(c.spinner) ~= 'table' then
          return false
        end
        if c and c.interval and type(c.interval) ~= 'number' then
          return false
        end
        return true
      end,
      'options = {spinner = {"frame1", "frame2", "frame3"}, interval = 80 (ms)}',
    },
  }
  if options then
    config = vim.tbl_extend('force', config, options)
  end
  lsp.handlers['$/progress'] = progress_callback
end

local function on_attach(client, bufnr)
  if not clients[client.id] then
    clients[client.id] = {name = client.name, jobs = {}, buffers = {bufnr}}
  else
    if not vim.tbl_contains(clients[client.id].buffers, bufnr) then
      table.insert(clients[client.id].buffers, bufnr)
    end
  end
end

return {
  setup = setup,
  on_attach = on_attach,
  init_capabilities = init_capabilities,
  status = get_status,
}
