local M={}
function M.run(request,report,checkpoint)
 local folder=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])"))
 local D=assert(loadfile(folder.."weapon_deco_fix_decorations.lua"))()
 local env=setmetatable({require=function(name)
  if name=="LoadoutClone.decorations" then return D end
  return require(name)
 end},{__index=_G})
 local Planner=assert(loadfile(folder.."weapon_deco_fix_planner.lua","t",env))()
 if request.activate_fix then
  local active=assert(package.loaded["LoadoutClone.planner"],"正式 Planner 尚未加载")
  local active_decorations=assert(package.loaded["LoadoutClone.decorations"],"正式珠子模块尚未加载")
  active_decorations.resolve_weapon=D.resolve_weapon
  active.prepare=Planner.prepare
  active.validate_actions=Planner.validate_actions
  report.activated=true;report.writes=0
  checkpoint("weapon decoration fix active for subsequent requests")
  return
 end
 local reader=require("LoadoutClone.reader").new()
 local planner=Planner.new(reader)
 checkpoint("resolve current weapon from full native decoration catalog")
 local snapshot=reader:capture(assert(request.key))
 planner.catalog=planner.native:read_catalog()
 local weapon=snapshot.data._weaponParam
 local old,reason=D.resolve(weapon,planner.catalog.decorations)
 report.previous_generic_result=old;report.previous_generic_reason=reason
 local fixed,err=D.resolve_weapon(weapon,planner.catalog.decorations)
 assert(fixed,err);report.decorations=fixed.ids;report.weapon_id=weapon.WeaponId
 report.weapon=weapon;report.writes=0
 checkpoint("prepare fixed weapon decorations and complete detached loadout")
 local plan=planner:prepare(assert(request.key),{copy_augments=true,allow_illegal_augments=true,copy_appearance=false})
 report.actions=plan.actions;report.red=plan.red;report.blue=plan.blue
 report.weapon_id=plan.snapshot.data._weaponParam.WeaponId
 report.decorations=plan.items[1].candidate.decorations
 report.items={}
 for i,item in ipairs(plan.items) do report.items[i]={kind=item.kind,verification=item.verification} end
 report.writes=0
 checkpoint("all detached candidates prepared; no inventory writes")
end
return M
