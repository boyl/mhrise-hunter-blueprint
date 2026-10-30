local hooks,tick,saved={},nil,nil
sdk={find_type_definition=function()return {get_method=function(_,s)return s end}end,hook=function(m,pre,post)hooks[m]={pre,post}end,get_managed_singleton=function()error("SDK object access in hook")end}
re={on_application_entry=function(_,fn)tick=fn end}
json={dump_file=function(_,v)saved=v;return true end}
local path=test_root.."tools/NativeSortObserver.lua"
local co=coroutine.create(function()assert(loadfile(path))()end)
assert(not coroutine.resume(co) and next(hooks)==nil)
assert(loadfile(path))()
local n=0
for name,pair in pairs(hooks)do
 n=n+1;assert(pair[1]({})==nil);local v={};assert(pair[2](v)==v)
 assert(saved.calls[name].pre==1 and saved.calls[name].post==1)
end
assert(n==4 and saved.read_only and #saved.snapshots==0)
print("PASS 原生整理观察器仅主线程注册；四个入口回调不读对象、不改变参数或返回值")
