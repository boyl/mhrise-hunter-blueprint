local Planner=require("LoadoutClone.planner")
local status={switchActionId={19,21,23},switchActionId_MR_1={19,21,100,102,103},switchActionId_MR_2={20,21,101,102,104}}
Planner.validate_actions(status)
status.switchActionId={}
assert(not pcall(Planner.validate_actions,status),"远端旧版数组尚未加载时必须在写入前拒绝")
status.switchActionId={19,21,23};status.switchActionId_MR_2={20,21}
assert(not pcall(Planner.validate_actions,status),"不完整苍书不得入库")
status.switchActionId_MR_2={20,21,101,102,"104"}
assert(not pcall(Planner.validate_actions,status),"无效动作值不得入库")
print("PASS 替换技完整数据及三类缺失/非法数据拒绝（4 项）")
