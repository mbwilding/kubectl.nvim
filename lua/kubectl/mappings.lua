local ResourceBuilder = require("kubectl.resourcebuilder")
local config = require("kubectl.config")
local viewsTable = require("kubectl.utils.viewsTable")
local event_handler = require("kubectl.actions.eventhandler").handler
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local string_utils = require("kubectl.utils.string")
local M = {}

local function is_plug_mapped(plug_target, mode)
  local mappings = vim.tbl_extend("force", vim.api.nvim_get_keymap(mode), vim.api.nvim_buf_get_keymap(0, mode))
  for _, mapping in ipairs(mappings) do
    if mapping.rhs and mapping.rhs == plug_target then
      return true
    end
  end
  return false
end

function M.map_if_plug_not_set(mode, lhs, plug_target, opts)
  if not is_plug_mapped(plug_target, mode) then
    vim.api.nvim_buf_set_keymap(0, mode, lhs, plug_target, opts or { noremap = true, silent = true, callback = nil })
  end
end

--- Register kubectl key mappings
function M.register()
  local win_id = vim.api.nvim_get_current_win()
  local win_config = vim.api.nvim_win_get_config(win_id)

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.portforwards_view)", "", {
    noremap = true,
    silent = true,
    desc = "View Port Forwards",
    callback = function()
      local view = require("kubectl.views")
      view.PortForwards()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.go_up)", "", {
    noremap = true,
    silent = true,
    desc = "Go up",
    callback = function()
      local view = require("kubectl.views")
      local state = require("kubectl.state")
      local older_view = state.history[#state.history - 1]
      if not older_view then
        return
      end
      table.remove(state.history, #state.history)
      view.view_or_fallback(older_view)
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.help)", "", {
    noremap = true,
    silent = true,
    desc = "Help",
    callback = function()
      local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
      local view = require("kubectl.views")
      local _, definition = view.view_and_definition(string.lower(vim.trim(buf_name)))

      if definition then
        view.Hints(definition.hints)
      end
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.delete)", "", {
    noremap = true,
    silent = true,
    desc = "Delete",
    callback = function()
      local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
      local view_ok, view = pcall(require, "kubectl.views." .. string.lower(vim.trim(buf_name)))
      if not view_ok then
        view = require("kubectl.views.fallback")
      end
      local name, ns = view.getCurrentSelection()
      if name then
        local resource = string.lower(buf_name)
        if buf_name == "fallback" then
          resource = view.resource
        end
        local args = { "delete", resource, name }
        if ns and ns ~= "nil" then
          table.insert(args, "-n")
          table.insert(args, ns)
        end
        buffers.confirmation_buffer("execute: kubectl " .. table.concat(args, " "), "", function(confirm)
          if not confirm then
            return
          end
          commands.shell_command_async("kubectl", args, function(delete_data)
            vim.schedule(function()
              vim.notify(delete_data, vim.log.levels.INFO)
            end)
          end)
        end)
      end
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.yaml)", "", {
    noremap = true,
    silent = true,
    desc = "View yaml",
    callback = function()
      local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
      local view_ok, view = pcall(require, "kubectl.views." .. string.lower(vim.trim(buf_name)))
      if not view_ok then
        view = require("kubectl.views.fallback")
      end
      local name, ns = view.getCurrentSelection()

      if name then
        local def = {
          resource = buf_name .. "_" .. name,
          ft = "k8s_yaml",
          url = { "get", buf_name, name, "-o", "yaml" },
          syntax = "yaml",
        }
        if ns then
          table.insert(def.url, "-n")
          table.insert(def.url, ns)
          def.resource = def.resource .. "_" .. ns
        end

        ResourceBuilder:view_float(def, { cmd = "kubectl" })
      end
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.describe)", "", {
    noremap = true,
    silent = true,
    desc = "Describe resource",
    callback = function()
      local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
      local view_ok, view = pcall(require, "kubectl.views." .. string.lower(vim.trim(buf_name)))
      if not view_ok then
        view = require("kubectl.views.fallback")
      end
      local name, ns = view.getCurrentSelection()
      if name then
        local ok = pcall(view.Desc, name, ns, true)
        vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.refresh)", "", {
          noremap = true,
          silent = true,
          desc = "Refresh",
          callback = function()
            vim.schedule(function()
              pcall(view.Desc, name, ns, false)
            end)
          end,
        })
        vim.schedule(function()
          M.map_if_plug_not_set("n", "gr", "<Plug>(kubectl.refresh)")
        end)
        if ok then
          local state = require("kubectl.state")
          event_handler:on("MODIFIED", state.instance_float.buf_nr, function(event)
            if event.object.metadata.name == name and event.object.metadata.namespace == ns then
              vim.schedule(function()
                pcall(view.Desc, name, ns, false)
              end)
            end
          end)
        else
          vim.api.nvim_err_writeln("Failed to describe " .. buf_name .. ".")
        end
      end
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.refresh)", "", {
    noremap = true,
    silent = true,
    desc = "Reload",
    callback = function()
      if win_config.relative == "" then
        local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
        vim.notify("Reloading " .. buf_name, vim.log.levels.INFO)
        local ok, view = pcall(require, "kubectl.views." .. string.lower(vim.trim(buf_name)))
        if ok then
          pcall(view.View)
        else
          view = require("kubectl.views.fallback")
          view.View()
        end
      else
        local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")

        ---@type string @Expected format: "resource_operation_name_namespace"
        -- `resource`: string, the resource type
        -- `operation`: string, the operation type
        -- `name`: string|nil, the resource name
        -- `ns`: string|nil, the namespace
        local resource = vim.split(buf_name, "_")
        local ok, view = pcall(require, "kubectl.views." .. resource[1])

        if not ok then
          view = require("kubectl.views.fallback")
        end
        ---TODO: fix types
        ---@diagnostic disable-next-line: param-type-mismatch
        pcall(view[string_utils.capitalize(resource[2])], resource[3] or "", resource[4] or "")
      end
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.edit)", "", {
    noremap = true,
    silent = true,
    desc = "Edit resource",
    callback = function()
      local state = require("kubectl.state")

      -- Retrieve buffer name and load the appropriate view
      local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
      local view_ok, view = pcall(require, "kubectl.views." .. string.lower(vim.trim(buf_name)))
      if not view_ok then
        view = require("kubectl.views.fallback")
      end

      -- Get resource details and construct the kubectl command
      local resource = state.instance.resource
      local name, ns = view.getCurrentSelection()

      if not name then
        vim.notify("Not a valid selection to edit", vim.log.levels.INFO)
        return
      end

      local args = { "get", resource .. "/" .. name, "-o", "yaml" }
      if ns and ns ~= "nil" then
        table.insert(args, "-n")
        table.insert(args, ns)
      end

      -- Save the resource data to a temporary file
      local self = ResourceBuilder:new("edit_resource"):setCmd(args, "kubectl"):fetch()

      local tmpfilename = string.format("%s-%s-%s.yaml", vim.fn.tempname(), name, ns)
      vim.print("editing " .. tmpfilename)

      local tmpfile = assert(io.open(tmpfilename, "w+"), "Failed to open temp file")
      tmpfile:write(self.data)
      tmpfile:close()

      local original_mtime = vim.loop.fs_stat(tmpfilename).mtime.sec
      vim.api.nvim_buf_set_var(0, "original_mtime", original_mtime)

      -- open the file
      vim.cmd("tabnew | edit " .. tmpfilename)

      vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = 0 })
      local group = vim.api.nvim_create_augroup("__kubectl_edited", { clear = false })

      vim.api.nvim_create_autocmd("QuitPre", {
        buffer = 0,
        group = group,
        callback = function()
          -- Defer action to let :wq have time to modify file
          vim.defer_fn(function()
            local ok
            ok, original_mtime = pcall(vim.api.nvim_buf_get_var, 0, "original_mtime")
            local current_mtime = vim.loop.fs_stat(tmpfilename).mtime.sec

            if ok and current_mtime ~= original_mtime then
              vim.notify("Edited. Applying changes")
              commands.shell_command_async("kubectl", { "apply", "-f", tmpfilename }, function(apply_data)
                vim.schedule(function()
                  vim.notify(apply_data, vim.log.levels.INFO)
                end)
              end)
            else
              vim.notify("Not Edited", vim.log.levels.INFO)
            end
          end, 100)
        end,
      })
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.toggle_headers)", "", {
    noremap = true,
    silent = true,
    desc = "Toggle headers",
    callback = function()
      config.options.headers = not config.options.headers
      pcall(require("kubectl.views").Redraw)
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.alias_view)", "", {
    noremap = true,
    silent = true,
    desc = "Aliases",
    callback = function()
      local view = require("kubectl.views")
      view.Aliases()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.filter_view)", "", {
    noremap = true,
    silent = true,
    desc = "Filter",
    callback = function()
      local filter_view = require("kubectl.views.filter")
      filter_view.filter()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "v", "<Plug>(kubectl.filter_term)", "", {
    noremap = true,
    silent = true,
    desc = "Filter",
    callback = function()
      local filter_view = require("kubectl.views.filter")
      local state = require("kubectl.state")
      local filter_term = string_utils.get_visual_selection()
      if not filter_term then
        return
      end
      filter_view.save_history(filter_term)
      state.setFilter(filter_term)

      vim.api.nvim_set_option_value("modified", false, { buf = 0 })
      vim.notify("filtering for.. " .. filter_term)
      vim.api.nvim_input("<Plug>(kubectl.refresh)")
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.filter_label)", "", {
    noremap = true,
    silent = true,
    desc = "Filter",
    callback = function()
      local filter_view = require("kubectl.views.filter")
      filter_view.filter_label()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.namespace_view)", "", {
    noremap = true,
    silent = true,
    desc = "Change namespace",
    callback = function()
      local namespace_view = require("kubectl.views.namespace")
      namespace_view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.contexts_view)", "", {
    noremap = true,
    silent = true,
    desc = "Change context",
    callback = function()
      local contexts_view = require("kubectl.views.contexts")
      contexts_view.View()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.sort)", "", {
    noremap = true,
    silent = true,
    desc = "Sort",
    callback = function()
      local marks = require("kubectl.utils.marks")
      local state = require("kubectl.state")
      local find = require("kubectl.utils.find")

      local mark, word = marks.get_current_mark(state.content_row_start)

      if not mark then
        return
      end

      if not find.array(state.marks.header, mark[1]) then
        return
      end

      local ok, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
      if not ok then
        return
      end

      -- TODO: Get the current view in a different way
      buf_name = string.lower(buf_name)
      local sortby = state.sortby[buf_name]

      if not sortby then
        return
      end
      sortby.mark = mark
      sortby.current_word = word

      if state.sortby_old.current_word == sortby.current_word then
        if state.sortby[buf_name].order == "asc" then
          state.sortby[buf_name].order = "desc"
        else
          state.sortby[buf_name].order = "asc"
        end
      end
      state.sortby_old.current_word = sortby.current_word

      local view_ok, view = pcall(require, "kubectl.views." .. string.lower(vim.trim(buf_name)))
      if not view_ok then
        view = require("kubectl.views.fallback")
      end
      pcall(view.Draw)
    end,
  })

  for _, view_name in ipairs(vim.tbl_keys(viewsTable)) do
    local view = require("kubectl.views." .. view_name)
    local keymap_name = string.gsub(view_name, "-", "_")
    local desc = string_utils.capitalize(view_name) .. " view"
    vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.view_" .. keymap_name .. ")", "", {
      noremap = true,
      silent = true,
      desc = desc,
      callback = function()
        view.View()
      end,
    })
  end

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.quit)", "", {
    noremap = true,
    silent = true,
    desc = "Close buffer",
    callback = function()
      vim.api.nvim_set_option_value("modified", false, { buf = 0 })
      vim.cmd.close()
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.tab)", "", {
    noremap = true,
    silent = true,
    desc = "Select resource",
    callback = function()
      local state = require("kubectl.state")
      local view = require("kubectl.views")
      local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
      local current_view, _ = view.view_and_definition(string.lower(vim.trim(buf_name)))

      local name, ns = current_view.getCurrentSelection()

      for i, selection in ipairs(state.selections) do
        if selection.name == name and (ns and selection.namespace == ns or true) then
          table.remove(state.selections, i)
          vim.api.nvim_feedkeys("j", "n", true)
          current_view.Draw()
          return
        end
      end

      if name then
        table.insert(state.selections, { name = name, namespace = ns })
        vim.api.nvim_feedkeys("j", "n", true)
        current_view.Draw()
      end
    end,
  })

  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.lineage)", "", {
    noremap = true,
    silent = true,
    desc = "Application lineage",
    callback = function()
      local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
      local view = require("kubectl.views")
      local current_view, _ = view.view_and_definition(string.lower(vim.trim(buf_name)))

      local name, ns = current_view.getCurrentSelection()
      local lineage_view = require("kubectl.views.lineage")

      lineage_view.View(name, ns, buf_name)
    end,
  })

  vim.schedule(function()
    -- Global mappings
    if win_config.relative == "" then
      M.map_if_plug_not_set("n", "1", "<Plug>(kubectl.view_deployments)")
      M.map_if_plug_not_set("n", "2", "<Plug>(kubectl.view_pods)")
      M.map_if_plug_not_set("n", "3", "<Plug>(kubectl.view_configmaps)")
      M.map_if_plug_not_set("n", "4", "<Plug>(kubectl.view_secrets)")
      M.map_if_plug_not_set("n", "5", "<Plug>(kubectl.view_services)")
      M.map_if_plug_not_set("n", "6", "<Plug>(kubectl.view_ingresses)")
      M.map_if_plug_not_set("n", "<bs>", "<Plug>(kubectl.go_up)")
      M.map_if_plug_not_set("n", "gD", "<Plug>(kubectl.delete)")
      M.map_if_plug_not_set("n", "gd", "<Plug>(kubectl.describe)")
      M.map_if_plug_not_set("n", "gy", "<Plug>(kubectl.yaml)")
      M.map_if_plug_not_set("n", "ge", "<Plug>(kubectl.edit)")
      M.map_if_plug_not_set("n", "gs", "<Plug>(kubectl.sort)")
      M.map_if_plug_not_set("n", "<Tab>", "<Plug>(kubectl.tab)")
      M.map_if_plug_not_set("n", "<M-h>", "<Plug>(kubectl.toggle_headers)")
    else
      local opts = { noremap = true, silent = true, callback = nil }
      vim.api.nvim_buf_set_keymap(0, "n", "q", "<Plug>(kubectl.quit)", opts)
      vim.api.nvim_buf_set_keymap(0, "n", "<esc>", "<Plug>(kubectl.quit)", opts)
      vim.api.nvim_buf_set_keymap(0, "i", "<C-c>", "<Esc><Plug>(kubectl.quit)", opts)
    end

    M.map_if_plug_not_set("n", "gP", "<Plug>(kubectl.portforwards_view)")
    M.map_if_plug_not_set("n", "<C-a>", "<Plug>(kubectl.alias_view)")
    M.map_if_plug_not_set("n", "<C-f>", "<Plug>(kubectl.filter_view)")
    M.map_if_plug_not_set("v", "<C-f>", "<Plug>(kubectl.filter_term)")
    M.map_if_plug_not_set("n", "<C-l>", "<Plug>(kubectl.filter_label)")
    M.map_if_plug_not_set("n", "<C-n>", "<Plug>(kubectl.namespace_view)")
    M.map_if_plug_not_set("n", "<C-x>", "<Plug>(kubectl.contexts_view)")
    M.map_if_plug_not_set("n", "g?", "<Plug>(kubectl.help)")
    M.map_if_plug_not_set("n", "gr", "<Plug>(kubectl.refresh)")
    M.map_if_plug_not_set("n", "<cr>", "<Plug>(kubectl.select)")

    if config.options.lineage.enabled then
      M.map_if_plug_not_set("n", "gx", "<Plug>(kubectl.lineage)")
    end
  end)
end
return M
