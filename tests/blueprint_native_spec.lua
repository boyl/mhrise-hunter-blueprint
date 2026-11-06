local N=require('LoadoutClone.blueprint_native')
local ids=N.legacy_actions({{id=43,group=0},{id=47,group=2},{id=120,group=3},{id=45,group=1},{id=123,group=5}})
assert(ids[1]==43 and ids[2]==45 and ids[3]==47 and #ids==3)
assert(N.legacy_actions({{id=9,group=2}})[1]==0)
assert(not pcall(N.legacy_actions,{{id=1,group=0},{id=2,group=0}}))
assert(not pcall(N.legacy_actions,{{id=1,group=-1}}))
print('PASS 本机五槽按原生分组转基础三槽、新增大师槽排除、缺项固定空值、重复及非法分组拒绝')

local Native=require('LoadoutClone.native');local Color=require('LoadoutClone.appearance_color')
local oldfield,oldarray,oldread=Native.field,Native.array_access,Color.read
Native.field=function(o,k)return assert(o[k],'缺少字段 '..k)end
Native.array_access=function(a)return #a,function(i)return a[i+1]end end
Color.read=function(v)return require('LoadoutClone.blueprints').copy(v)end
local parts={}
for p=1,5 do parts[p]={_ColorData={{enabled=false,default=false,hsv={0,84,74}},{enabled=true,default=false,hsv={52,85,83}}}}end
local manager={_PlArmorColorMySetData={_OverwearSymbolColor={_Parts=parts}},_PlOverwearMySetData={stale=true}}
local colors=N.current_colors(manager)
assert(colors[1][1].hsv[2]==84 and colors[2][5].hsv[1]==52 and colors[1][1].default==false)
parts[1]._ColorData[1].hsv[2]=1;assert(colors[1][1].hsv[2]==84)
assert(not pcall(N.current_colors,{_PlOverwearMySetData={stale=true}}),'缺少实时颜色不得回退到旧组合')
parts[5]=nil;assert(not pcall(N.current_colors,manager),'缺少部位须明确失败')
Native.field,Native.array_access,Color.read=oldfield,oldarray,oldread
print('PASS 当前外观染色独立于旧组合、双通道保真、快照隔离、缺失实时颜色拒绝')
