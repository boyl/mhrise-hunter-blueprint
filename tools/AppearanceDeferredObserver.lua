-- 主线程加载的只读集成对照；不随正式发布包分发。
local _,main=coroutine.running()
assert(main,"集成观察器必须由主线程加载")
local here=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])"))
local folder=here.."../diagnostics/HunterBlueprintAppearance/"
local cache={}
local function isolated(name)
 if cache[name] then return cache[name] end
 local short=assert(name:match("^LoadoutClone%.([a-z_]+)$"))
 local env=setmetatable({require=isolated},{__index=_G})
 cache[name]=assert(loadfile(folder..short..".lua","t",env))()
 return cache[name]
end
local reader=isolated("LoadoutClone.reader").new()
local binding=isolated("LoadoutClone.appearance_binding").new(reader)
local state=isolated("LoadoutClone.appearance_hooks").install(binding,true)
local last
re.on_application_entry("UpdateBehavior",function()
 local key=table.concat({state.calls,state.applied,state.errors,tostring(state.character),tostring(state.last_hidden)},"/")
 if key==last then return end
 last=key
 assert(json.dump_file("LoadoutClone/appearance-hook-observer.json",{
  schema=3,installed=true,observe_only=state.observe_only,calls=state.calls,
  applied=state.applied,errors=state.errors,last_error=state.last_error,
  character=state.character,last_hidden=state.last_hidden,writes=0
 }))
end)
