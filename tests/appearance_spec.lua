local A=require("LoadoutClone.appearance")
local count=0
local function test(name,fn) fn();count=count+1;print("PASS "..name) end
local function rejects(fn) assert(not pcall(fn),"应拒绝无效外观") end
local function near(a,b) assert(math.abs(a-b)<=1e-5,tostring(a).." ~= "..tostring(b)) end
-- 期望值来自 color-contract-002 原生 HSV2ColorToMaterial，只保留数值，无玩家信息。
local samples={
 {{0,0,0},{0.029999999329447746,0.029999999329447746,0.029999999329447746}},
 {{0,100,0},{0.029999999329447746,0,0}},
 {{0,100,100},{0.800000011920929,0,0}},
 {{120,100,50},{0,0.41499999165534973,0}},
 {{30,90,47},{0.391899973154068,0.215544983744621,0.0391900055110455}},
}
test("材质颜色还原匹配五组原生测量",function()
 for _,s in ipairs(samples) do
  local c={x=s[2][1],y=s[2][2],z=s[2][3]}
  local hsv=A.material_to_hsv(c)
  for i=1,3 do assert(hsv[i]==s[1][i]) end
  local rgb=A.hsv_to_material(hsv)
  near(rgb.x,c.x);near(rgb.y,c.y);near(rgb.z,c.z)
 end
end)
test("六个色相区间及整数 HSV 边界可往返",function()
 for h=0,359 do for _,s in ipairs({0,1,50,99,100}) do for _,v in ipairs({0,1,50,99,100}) do
  local rgb=A.hsv_to_material({h,s,v})
  local hsv=A.material_to_hsv(rgb)
  assert(hsv[1]==(s==0 and 0 or h) and hsv[2]==s and hsv[3]==v)
 end end end
end)
test("颜色输入拒绝非有限值和无法精确表示的颜色",function()
 for _,c in ipairs({{x=0,y=0,z=0},{x=1,y=0,z=0},{x=-0.1,y=0,z=0},{x=0/0,y=0,z=0},{x=math.huge,y=0,z=0},{x=0.4,y=0,z=0},{x=0.8,y=0}}) do
  rejects(function() A.material_to_hsv(c) end)
 end
 for _,hsv in ipairs({{360,0,0},{-1,0,0},{0,101,0},{0,0,101},{0,0,0.5},{0,0}}) do
  rejects(function() A.hsv_to_material(hsv) end)
 end
end)
local function snapshot()
 local out={weapon_id=134217728,armor_ids={0,4096,8192,12288,16384},weapon_hidden=false,
  weapon_color={enabled=false},colors={{},{}}}
 for ch=1,2 do for part=1,5 do out.colors[ch][part]={enabled=false} end end
 out.colors[1][1]={enabled=true,rgba={x=0.8,y=0,z=0}}
 return out
end
test("完整外观快照深拷贝，未启用染色不伪造默认色",function()
 local input=snapshot();local out=A.normalize(input)
 assert(out.colors[1][1].hsv[1]==0 and out.colors[1][1].hsv[2]==100)
 assert(out.weapon_color.enabled==false and out.weapon_color.hsv==nil)
 input.armor_ids[1]=99;input.colors[1][1].rgba.x=0.1
 assert(out.armor_ids[1]==0 and out.colors[1][1].hsv[3]==100)
end)
test("缺少部位、颜色、隐藏标志及非法 ID 均拒绝",function()
 for _,change in ipairs({
  function(s) s.armor_ids[5]=nil end,function(s) s.colors[2][3]=nil end,
  function(s) s.weapon_id=-1 end,function(s) s.weapon_id=0.5 end,
  function(s) s.weapon_hidden=nil end,function(s) s.weapon_color.enabled=0 end,
  function(s) s.colors[1][1].rgba=nil end,function(s) s.armor_ids[6]=0 end,
 }) do local s=snapshot();change(s);rejects(function() A.normalize(s) end) end
end)
test("上下文比较识别染色、ID、隐藏状态变化",function()
 local a=A.normalize(snapshot());local b=A.normalize(snapshot());assert(A.same(a,b))
 b.weapon_hidden=true;assert(not A.same(a,b));b=A.normalize(snapshot())
 b.armor_ids[1]=12;assert(not A.same(a,b));b=A.normalize(snapshot())
 b.colors[1][1].hsv[3]=99;assert(not A.same(a,b))
end)
test("外观空槽从尾部选择，满位和缺失状态拒绝",function()
 assert(A.last_empty_slot({true,false,true,false})==3)
 assert(A.last_empty_slot({false})==0)
 rejects(function() A.last_empty_slot({true,true}) end)
 rejects(function() A.last_empty_slot({true,0}) end)
 rejects(function() A.last_empty_slot({}) end)
end)
print(count.." appearance tests passed")
