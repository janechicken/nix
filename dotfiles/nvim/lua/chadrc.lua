-- This file needs to have same structure as nvconfig.lua 
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Please read that file to know all available options :( 

---@type ChadrcConfig
local M = {}

M.base46 = {
	theme = "default-dark",
  hl_override = {
    Comment = { italic = true },
    ["@comment"] = { link = "Comment" },
    ["@keyword"] = { italic = true }
  }
}
M.nvdash = { load_on_startup = true }
M.ui = {
  cmp = { style = "atom" },
  statusline = { theme = "vscode_colored" }
}
-- M.nvdash = { load_on_startup = true }
-- M.ui = {
--       tabufline = {
--          lazyload = false
--      }
--}

return M
