local root=assert(test_root,"test_root must be supplied by the test runner")
local probe=assert(loadfile(root.."tools/appearance_transaction_probe.lua"))()
for _,mode in ipairs({"transaction_prepare","transaction_rollback","transaction_commit","hook_install"}) do
 local ok,err=pcall(probe.run,{mode=mode},{},function() error("不应到达运行时") end)
 assert(not ok and tostring(err):find("外观实验已隔离",1,true),mode)
end
_G.HunterBlueprintAppearanceHookState={version=2,observe_only=true,calls=1,errors=0}
for _,request in ipairs({
 {mode="hook_install",isolation_stage="appearance_only"},
 {mode="transaction_commit",isolation_stage="appearance_only",with_visibility=true},
 {mode="transaction_commit"},
}) do
 local ok,err=pcall(probe.run,request,{},function()error("不应到达运行时")end)
 assert(not ok and tostring(err):find("外观实验已隔离",1,true))
end
_G.HunterBlueprintAppearanceHookState=nil
print("PASS 崩溃隔离在任何 SDK 调用、回调安装和库存写入之前拒绝实验入口")
