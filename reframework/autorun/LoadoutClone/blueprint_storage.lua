local M={}
function M.new()
 local path='LoadoutClone/appearance-blueprints.json'
 local function exists()return #fs.glob([[LoadoutClone[\\/]appearance-blueprints\.json]])>0 end
 return {load=function()if exists() then return json.load_file(path)end end,
 exists=exists,
 write=function(value)return json.dump_file(path,value)end,
 backup=function(value)
  local backup='LoadoutClone/appearance-blueprints.backup.json'
  if not json.dump_file(backup,value) then return false end
  local ok,loaded=pcall(require('LoadoutClone.blueprints').validate,json.load_file(backup))
  return ok and require('LoadoutClone.appearance').same(loaded,value)
 end}
end
return M
