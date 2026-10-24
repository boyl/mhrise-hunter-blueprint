local Reader=require("LoadoutClone.reader")
local Planner=require("LoadoutClone.planner")
local Writer=require("LoadoutClone.writer")
local M={}
function M.new()
    local reader=Reader.new()
    return setmetatable({reader=reader,planner=Planner.new(reader),writer=Writer.new(reader)},{__index=M})
end
function M:list_members() return self.reader:list_members() end
function M:capture(key) return self.reader:capture(key) end
function M:prepare(key,options) return self.planner:prepare(key,options) end
function M:commit(plan)
    local config=json.load_file("LoadoutClone/config.json")
    assert(config==nil or config.write_enabled==true,"配置已关闭装备写入")
    return self.writer:execute(plan)
end
return M
