local V=require("LoadoutClone.appearance_visibility")
local function clone(v) if type(v)~="table" then return v end;local o={};for k,x in pairs(v) do o[k]=clone(x) end;return o end
local data={schema=1,records={}}
local fail=false
local store={load=function() return clone(data) end,save=function(v) data=clone(v);if fail then fail=false;error("disk error") end end}
local model=V.new(store)
local fingerprint={hunter={name="blueprint",equip=3,overwear=4},armor={1,2,3,4,5},weapon=100}
local e=model:prepare("slot0:character-a",fingerprint,true)
assert(#data.records==0 and model:lookup("slot0:character-a",fingerprint)==nil)
model:apply(e);model:verify(e)
assert(model:lookup("slot0:character-a",fingerprint)==true)
assert(model:lookup("slot1:character-b",fingerprint)==nil)
local changed=clone(fingerprint);changed.weapon=101
assert(model:lookup("slot0:character-a",changed)==nil)
fingerprint.weapon=999
assert(data.records[1].fingerprint.weapon==100)
model:restore(e);assert(#data.records==0)
print("PASS 显示状态仅精确匹配角色与组合，拒绝陈旧绑定，备份不共享引用")
local e=model:prepare("slot0:a",changed,false)
fail=true;assert(not pcall(function() model:apply(e) end))
model:restore(e);assert(#data.records==0)
print("PASS 元数据部分保存失败后恢复原记录")
local e=model:prepare("slot0:a",changed,true)
data.records[1]={character="other",fingerprint={},hidden=false}
assert(not pcall(function() model:apply(e) end))
model:restore(e);assert(data.records[1].character=="other")
print("PASS 写入前文件冲突保留外部修改")
data={schema=1,records={}}
local e=model:prepare("slot0:a",changed,false);model:apply(e)
local reloaded=V.new(store);assert(reloaded:lookup("slot0:a",changed)==false)
assert(not pcall(function() reloaded:prepare("slot0:a",changed,"false") end))
print("PASS 重建服务保留显示值 false，错误状态类型拒绝")
local removed=model:prepare("slot0:a",changed,nil)
model:apply(removed);model:verify(removed)
assert(model:lookup("slot0:a",changed)==nil)
model:restore(removed);assert(model:lookup("slot0:a",changed)==false)
local noop=model:prepare("missing",changed,nil);model:apply(noop);assert(not noop.write_started)
print("PASS 不复制显示状态清除同指纹旧绑定，可回滚；无匹配记录时不写文件")
