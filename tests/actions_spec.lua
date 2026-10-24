local Planner=require("LoadoutClone.planner")
local status={isMRRelease=true,switchActionId={19,21,23},switchActionId_MR_1={19,21,100,102,103},switchActionId_MR_2={20,21,101,102,104}}
Planner.validate_actions(status,true)
status.switchActionId={}
local padded=Planner.validate_actions(status,true)
assert(padded[1]==0 and padded[2]==0 and padded[3]==0,"空旧版列表须规范化为原生 None")
status.switchActionId={50,54}
padded=Planner.validate_actions(status,true)
assert(padded[1]==50 and padded[2]==54 and padded[3]==0,"保留实际旧版动作，空项只使用 ActionId_None")
status.switchActionId={50};padded=Planner.validate_actions(status,true)
assert(padded[1]==50 and padded[2]==0 and padded[3]==0)
status.switchActionId={unavailable=true};assert(not pcall(Planner.validate_actions,status,true))
status.switchActionId={1,2,3,4};assert(not pcall(Planner.validate_actions,status,true))
status.switchActionId={50};status.switchActionId_MR_1={49,51}
assert(not pcall(Planner.validate_actions,status,true),"短旧版列表不能放过不完整朱书")
status.switchActionId_MR_1={19,21,100,102,103}
status.switchActionId={19,21,23};status.switchActionId_MR_2={20,21}
assert(not pcall(Planner.validate_actions,status,true),"不完整苍书不得入库")
status.switchActionId_MR_2={20,21,101,102,"104"}
assert(not pcall(Planner.validate_actions,status,true),"无效动作值不得入库")
print("PASS 旧版替换技 0/1/2/3 项规范化及缺失、超长、朱苍书拒绝（9 项）")
