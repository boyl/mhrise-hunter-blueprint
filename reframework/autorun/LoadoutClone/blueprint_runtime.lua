local M={}
function M.new(appearance)
 assert(appearance,'外观服务未就绪')
 local library=require('LoadoutClone.blueprints').new(require('LoadoutClone.blueprint_storage').new())
 local service=require('LoadoutClone.blueprint_service').new(library,require('LoadoutClone.blueprint_native').new(),appearance,function(a,reader)
  local config=json.load_file('LoadoutClone/config.json')
  assert(config==nil or config.write_enabled==true,'配置已关闭写入')
  return require('LoadoutClone.writer').new(reader,a)
 end)
 return require('LoadoutClone.blueprint_controller').new(service)
end
return M
