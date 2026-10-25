local function clone(v) if type(v)~="table" then return v end;local o={};for k,x in pairs(v) do o[k]=clone(x) end;return o end
local N={field=function(o,k) return assert(o[k],k) end,array=function(v) return clone(v) end,
 array_access=function(v) return #v,function(i) return v[i+1] end end,new=function() return {} end}
package.loaded["LoadoutClone.native"]=N
package.loaded["LoadoutClone.appearance_color"]={read=function(v) return clone(v) end}
local detached=0
package.loaded["LoadoutClone.appearance_objects"]={new=function() return {detach_weapon_color=function(_,o) detached=detached+1;o._HyakuryuColorData=clone(o._HyakuryuColorData) end} end}
local W=require("LoadoutClone.writer")
local function equip(hue)
 local o={_CustomBuildup={},["<InventoryIndex>k__BackingField"]=0,_HyakuryuColorData={enabled=true,default=false,hsv={hue,50,50}}}
 function o:get_field(k) return self[k] end
 for _,k in ipairs({"_IdType","_IdVal","_BuildupPoint","_CustomEnable","_CustomCount","_CustomBuildupType","_BowgunCustomizeType","_PairInsectInventoryIndex","_HyakuryuDecoId","_IsLock","_IsSetGuildCard"}) do o[k]=0 end
 for _,k in ipairs({"_DecoIdList","_CustomOpenIdArray","_TalismanDecoSlotNumList","_TalismanSkillIdList","_TalismanSkillLvList","_HyakuryuSkillIdList","_PrevHyakuryuSkillId"}) do o[k]={} end
 return o
end
local w=W.new({})
function w:copy(_,dest,source) for k,v in pairs(source) do dest[k]=v end end
local dest,source,backup=equip(10),equip(200),equip(10)
local e={kind="equipment",with_color=true,dest=dest,object=source,backup=backup,index=0,before=W.equipment_state(dest,true)}
w:apply(e);assert(detached==1 and dest._HyakuryuColorData.hsv[1]==200)
source._HyakuryuColorData.hsv[1]=300;assert(dest._HyakuryuColorData.hsv[1]==200)
w:restore(e);w:verify_restored(e)
assert(detached==2 and dest._HyakuryuColorData.hsv[1]==10)
backup._HyakuryuColorData.hsv[1]=50;assert(dest._HyakuryuColorData.hsv[1]==10)
print("PASS 生产 Writer 写入与回滚均隔离武器颜色引用，恢复原颜色")
e.write_started=nil;e.before=W.equipment_state(dest,true);dest._HyakuryuColorData.hsv[1]=99
local count=w.write_count
assert(not pcall(w.apply,w,e) and w.write_count==count and not e.write_started)
print("PASS 预留武器槽颜色冲突在写入前拒绝")
