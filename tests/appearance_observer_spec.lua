local root=assert(test_root,"test_root must be supplied by the test runner")
local path=root.."tools/AppearanceHookObserver.lua"
local registrations=0
local pre,post,tick,saved
local hooks={}
sdk={find_type_definition=function(name)
 assert(name=="snow.data.EquipDataManager")
 return {get_method=function(_,signature)
  assert(signature=="applyHunterMySet(System.Int32)" or signature=="applyHunterMySet(snow.data.HunterMySetData)");return signature
 end}
end,hook=function(signature,a,b) registrations=registrations+1;hooks[signature]={a,b};pre=a;post=b end,to_int64=function(v)assert(type(v)=="number");return v end}
re={on_application_entry=function(name,fn)assert(name=="UpdateBehavior");tick=fn end}
json={dump_file=function(_,v)saved={pre=v.pre,post=v.post,success=v.last_success,writes=v.writes};return true end}
local co=coroutine.create(function()assert(loadfile(path))()end)
local ok=coroutine.resume(co)
assert(not ok and registrations==0)
assert(loadfile(path))()
assert(registrations==2 and saved.writes==0)
pre({nil,{}, {}});assert(post(1)==1);tick()
assert(saved.pre==1 and saved.post==1)
pre,post=table.unpack(hooks["applyHunterMySet(System.Int32)"])
pre({nil,{},3});assert(post(1)==1);tick()
assert(saved.pre==2 and saved.post==2 and saved.success==true and saved.writes==0)
pre({nil,{},4});assert(post(0)==0);tick()
assert(saved.pre==3 and saved.post==3 and saved.success==false)
print("PASS 主线程只读观察器保留原返回值，不访问游戏对象或修改状态")
