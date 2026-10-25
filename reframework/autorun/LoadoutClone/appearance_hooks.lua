-- 原生钩子只记录数字；原生对象读取和设置统一延后到 UpdateBehavior。
local N=require("LoadoutClone.native")
local M={}
function M.install(binding,observe_only)
 local _,main=coroutine.running()
 assert(main,"外观回调必须由主 Lua 线程安装，禁止从诊断协程注册")
 assert(type(thread)=="table" and type(thread.get_hook_storage)=="function","运行环境缺少安全钩子存储")
 local old=_G.HunterBlueprintAppearanceHookState
 if old then
  assert(old.version==2,"旧外观回调需 Reset scripts 后更新")
  old.binding=binding;old.observe_only=observe_only==true;old.pending=nil;return old
 end
 local state={version=2,binding=binding,observe_only=observe_only==true,calls=0,applied=0,errors=0}
 local t=assert(sdk.find_type_definition("snow.data.EquipDataManager"))
 local indexed=assert(t:get_method("applyHunterMySet(System.Int32)"))
 local object=assert(t:get_method("applyHunterMySet(snow.data.HunterMySetData)"))
 local function failure(err)
  state.errors=state.errors+1;state.last_error=tostring(err)
  log.error("[HunterBlueprint appearance] "..state.last_error)
 end
 sdk.hook(indexed,function(args)
  state.pending=nil
  thread.get_hook_storage().hunter_blueprint={index=sdk.to_int64(args[3]),character=state.character}
 end,function(retval)
  state.calls=state.calls+1
  local event=thread.get_hook_storage().hunter_blueprint
  if event and event.character and (sdk.to_int64(retval)&1)==1 then state.pending=event end
  return retval
 end)
 -- 未验证的直接对象调用只作失效处理，不延长原生指针的生命周期。
 sdk.hook(object,function() state.pending=nil end,function(retval)return retval end)
 function state.update()
  local event=state.pending;state.pending=nil
  local ok,character=pcall(state.binding.character,state.binding)
  state.character=ok and character or nil
  if not event or not state.character or event.character~=state.character then return end
  local success,err=pcall(function()
   local manager=assert(sdk.get_managed_singleton("snow.data.EquipDataManager"))
   local n,get=N.array_access(N.field(manager,"_HunterMySetList"),1024)
   if event.index<0 or event.index>=n then return end
   local hunter=get(event.index)
   if not state.binding:matches_current(manager,hunter) then return end
   local hidden=state.binding:selection(manager,hunter)
   if hidden==nil then return end
   state.last_hidden=hidden
   if not state.observe_only then state.binding:apply_hidden(manager,hidden);state.applied=state.applied+1 end
  end)
  if not success then failure(err) end
 end
 re.on_application_entry("UpdateBehavior",state.update)
 _G.HunterBlueprintAppearanceHookState=state
 return state
end
return M
