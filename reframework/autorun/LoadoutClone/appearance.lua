-- 外观纯数据层。无 SDK、库存或文件副作用；尚未接入正式复制流程。
-- 材质亮度公式来自 color-contract-002 的原生测量，不能直接使用普通 RGB→HSV。
local M={}
local EPS=1e-5
local function finite(v)
 return type(v)=="number" and v==v and v>-math.huge and v<math.huge
end
local function integer(v,min,max,label)
 assert(finite(v) and v%1==0 and v>=min and v<=max,label.."无效")
 return v
end
local function sequence(t,size,label)
 assert(type(t)=="table",label.."缺失")
 local n=0
 for k in pairs(t) do
  assert(type(k)=="number" and k%1==0 and k>=1 and k<=size,label.."长度无效")
  n=n+1
 end
 assert(n==size,label.."长度无效")
 return t
end
function M.hsv_to_material(hsv)
 sequence(hsv,3,"染色 HSV")
 local h=integer(hsv[1],0,359,"色相")/60
 local s=integer(hsv[2],0,100,"饱和度")/100
 local v=0.03+0.77*integer(hsv[3],0,100,"明度")/100
 local c=v*s;local x=c*(1-math.abs(h%2-1));local m=v-c
 local r,g,b
 if h<1 then r,g,b=c,x,0 elseif h<2 then r,g,b=x,c,0
 elseif h<3 then r,g,b=0,c,x elseif h<4 then r,g,b=0,x,c
 elseif h<5 then r,g,b=x,0,c else r,g,b=c,0,x end
 return {x=r+m,y=g+m,z=b+m}
end
function M.material_to_hsv(rgb)
 assert(type(rgb)=="table","染色数据缺失")
 for _,key in ipairs({"x","y","z"}) do
  assert(finite(rgb[key]) and rgb[key]>=-EPS and rgb[key]<=0.8+EPS,"染色分量无效")
 end
 local r,g,b=rgb.x,rgb.y,rgb.z
 local hi,lo=math.max(r,g,b),math.min(r,g,b)
 assert(hi>=0.03-EPS,"材质亮度低于原生范围")
 local delta=hi-lo;local h=0
 if delta>1e-8 then
  if hi==r then h=60*((g-b)/delta%6)
  elseif hi==g then h=60*((b-r)/delta+2)
  else h=60*((r-g)/delta+4) end
 end
 local function round(v) return math.floor(v+0.5) end
 local hsv={round(h)%360,round(delta/hi*100),round((hi-0.03)/0.77*100)}
 -- 取整只能吸收原生 float 误差；不能把无法还原的颜色静默近似。
 local restored=M.hsv_to_material(hsv)
 for _,key in ipairs({"x","y","z"}) do
  assert(math.abs(restored[key]-rgb[key])<=EPS,"染色无法精确还原为原生整数 HSV")
 end
 return hsv
end
local function color(source)
 assert(type(source)=="table" and type(source.enabled)=="boolean","染色启用状态缺失")
 local out={enabled=source.enabled}
 if out.enabled then out.hsv=M.material_to_hsv(source.rgba) end
 -- 未启用的颜色不具有效果；不推断 _IsDefault 与 _IsEnable 的原生写入语义。
 return out
end
function M.normalize(source)
 assert(type(source)=="table","外观快照缺失")
 assert(type(source.weapon_hidden)=="boolean","武器显示状态缺失")
 local out={schema=1,weapon_id=integer(source.weapon_id,0,0xffffffff,"武器外观 ID"),
  weapon_hidden=source.weapon_hidden,armor_ids={},colors={{},{}},weapon_color=color(source.weapon_color)}
 sequence(source.armor_ids,5,"防具外观")
 sequence(source.colors,2,"染色通道")
 for i,id in ipairs(source.armor_ids) do out.armor_ids[i]=integer(id,0,0xffffffff,"防具外观 ID") end
 for channel=1,2 do
  sequence(source.colors[channel],5,"染色部位")
  for part=1,5 do out.colors[channel][part]=color(source.colors[channel][part]) end
 end
 -- ID 这里只检验传输值域；具体装备有效性、部位和性别由未来原生适配器验证。
 return out
end
function M.same(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~="table" then return a==b end
 for k,v in pairs(a) do if not M.same(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
function M.last_empty_slot(used)
 assert(type(used)=="table" and #used>0 and #used<=1024,"外观组合数量无效")
 sequence(used,#used,"外观组合状态")
 local last
 for i=1,#used do
  assert(type(used[i])=="boolean","外观组合状态缺失")
  if not used[i] then last=i-1 end
 end
 assert(last~=nil,"外观组合没有空位")
 return last
end
return M
