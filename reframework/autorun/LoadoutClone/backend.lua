local Reader=require("LoadoutClone.reader")
local Planner=require("LoadoutClone.planner")
local Writer=require("LoadoutClone.writer")
local M={}
function M.new(appearance_factory)
    local reader=Reader.new()
    -- 只有代码中的已验收适配器可接入；配置文件不能启用未验收原生写入。
    assert(appearance_factory==nil or type(appearance_factory)=="function","外观工厂无效")
    local appearance=appearance_factory and assert(appearance_factory(reader),"外观服务未就绪") or nil
    return setmetatable({reader=reader,appearance=appearance,planner=Planner.new(reader,appearance),writer=Writer.new(reader,appearance)},{__index=M})
end
function M:supports_appearance() return self.appearance~=nil end
function M:list_members() return self.reader:list_members() end
function M:capture(key) return self.reader:capture(key) end
function M:prepare(key,options) return self.planner:prepare(key,options) end
function M:commit(plan)
    local config=json.load_file("LoadoutClone/config.json")
    assert(config==nil or config.write_enabled==true,"配置已关闭装备写入")
    return self.writer:execute(plan)
end
return M
