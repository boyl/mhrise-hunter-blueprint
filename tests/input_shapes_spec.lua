local D=require("LoadoutClone.decorations")
local function part() return {DecoLvType={0,0,0},SlotIconColor={0,0,0},EquipSkill={},EquipSkillLv={}} end
local p=part();p.EquipSkillLv={1}
assert(not pcall(D.resolve_weapon,p,{}),"额外技能等级不能被静默忽略")
p=part();p.EquipSkill={1};p.EquipSkillLv={1};p.DecoSkillEquipUp={}
assert(not pcall(D.resolve,p,{}),"存在但缺项的技能标志必须拒绝")
local Planner=require("LoadoutClone.planner")
local status={isMRRelease=true,switchActionId={[1]=50,[3]=54},switchActionId_MR_1={1,2,3,4,5},switchActionId_MR_2={1,2,3,4,5}}
assert(not pcall(Planner.validate_actions,status,true),"旧版数组孔洞不得当作 None")
status.switchActionId={1,2,3};status.switchActionId_MR_1={[1]=1,[3]=3,[4]=4,[5]=5}
assert(not pcall(Planner.validate_actions,status,true),"五项长度不能替代每项存在性")
print("PASS 技能数量不配对、标志缺项及替换技数组孔洞拒绝（4 项）")
