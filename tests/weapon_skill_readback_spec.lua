local actual={}
package.loaded["LoadoutClone.native"]={new=function() return {
 read_catalog=function() return {decorations={{id=7,level=1,color=1,skills={10},levels={1}}}} end,
 weapon_base=function() return {} end,
 build_weapon=function() return {},{all_skills=actual,cheat_check=false} end,
 armor_base=function() error("unexpected later stage") end,
} end}
local P=require("LoadoutClone.planner")
local snapshot={schema=1,source={key="a"},data={
 _equipStatusParam={isMRRelease=true,switchActionId={},switchActionId_MR_1={1,2,3,4,5},switchActionId_MR_2={1,2,3,4,5}},
 _armorParam={{},{},{},{},{}},
 _weaponParam={WeaponId=1,EquipSkill={10},EquipSkillLv={1},DecoLvType={1,0,0},SlotIconColor={1,0,0}}
}}
for _,skills in ipairs({{}, {[10]=1,[20]=1}}) do
 actual=skills
 local p=P.new({progression_state=function() return true end,capture=function() return snapshot end})
 local ok,err=pcall(p.prepare,p,"a",{copy_augments=false,allow_illegal_augments=false})
 assert(not ok and tostring(err):find("技能",1,true),tostring(err))
end
print("PASS 武器原生技能少于或多于目标时在防具处理前拒绝（2 项）")
