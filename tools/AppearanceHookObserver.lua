-- 开发期只读对照：主线程注册，回调仅记录数字，不调用游戏对象方法。
-- 不随正式包发布。删除文件并 Reset scripts 即卸载。
local _,main=coroutine.running()
assert(main,"只读观察器必须从主 Lua 线程加载")
local path="LoadoutClone/appearance-hook-observer.json"
local state={schema=2,installed=false,pre=0,post=0,writes=0,overloads={}}
local manager=assert(sdk.find_type_definition("snow.data.EquipDataManager"))
local dirty=true
for _,kind in ipairs({"System.Int32","snow.data.HunterMySetData"}) do
local method=assert(manager:get_method("applyHunterMySet("..kind..")"))
local count={pre=0,post=0}
state.overloads[kind]=count
sdk.hook(method,function(args)
 state.pre=state.pre+1
 count.pre=count.pre+1
 if kind=="System.Int32" then state.last_index=sdk.to_int64(args[3]) end
 dirty=true
end,function(retval)
 state.post=state.post+1
 count.post=count.post+1
 state.last_success=(sdk.to_int64(retval)&1)==1
 dirty=true
 return retval
end)
end
state.installed=true
re.on_application_entry("UpdateBehavior",function()
 if dirty then
  dirty=false
  assert(json.dump_file(path,state),"只读观察报告写入失败")
 end
end)
json.dump_file(path,state)
