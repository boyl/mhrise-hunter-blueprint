-- 跨角色蓝图库：只保存纯数据；所有文件写入由 storage 负责。
local A=require('LoadoutClone.appearance')
local C=require('LoadoutClone.appearance_color')
local M={limit=100}
local function integer(v,lo,hi,label)
 assert(type(v)=='number' and v%1==0 and v>=lo and v<=hi,label..'无效');return v
end
function M.copy(v)
 if type(v)~='table' then return v end
 local out={};for k,x in pairs(v)do out[k]=M.copy(x)end;return out
end
function M.name(v)
 assert(type(v)=='string' and #v<=192,'名称过长')
 v=v:gsub('^%s+',''):gsub('%s+$','')
 local len=utf8.len(v)
 assert(len and len>0 and len<=48 and not v:find('[%c]'),'名称须为 1～48 个字符且不能换行')
 return v
end
function M.snapshot(s)
 assert(type(s)=='table' and s.schema==1,'外观蓝图版本不支持')
 local out={schema=1,weapon_id=integer(s.weapon_id,0,0xffffffff,'武器外观'),weapon_hidden=s.weapon_hidden,armor_ids={},colors={{},{}}}
 assert(type(s.weapon_hidden)=='boolean','武器显示状态无效')
 local function sequence(t,n)
  assert(type(t)=='table','外观数据缺失');local count=0
  for k in pairs(t)do assert(type(k)=='number' and k%1==0 and k>=1 and k<=n,'外观数组无效');count=count+1 end
  assert(count==n,'外观数组长度无效')
 end
 local function color(v)
  local c=C.from_snapshot(v)
  local out={enabled=c.enabled}
  -- 保留本机原生快照；旧格式不补字段，避免改变既有文件比较和恢复契约。
  if v.default~=nil then out.default=c.default end
  if c.enabled or v.hsv~=nil then out.hsv=c.hsv end
  return out
 end
 sequence(s.armor_ids,5);sequence(s.colors,2)
 for i=1,5 do out.armor_ids[i]=integer(s.armor_ids[i],0,0xffffffff,'防具外观')end
 for ch=1,2 do sequence(s.colors[ch],5);for part=1,5 do out.colors[ch][part]=color(s.colors[ch][part])end end
 out.weapon_color=color(s.weapon_color)
 return out
end
-- 文件边界：限制深度、大小和标量范围，再交给原有配装规划器核验真实游戏契约。
function M.equipment(value)
 local budget=10000
 local function plain(v,depth)
  budget=budget-1;assert(budget>=0 and depth<=9,'装备蓝图数据过大')
  local kind=type(v)
  if kind=='number' then assert(v==v and v>-1e12 and v<1e12,'装备蓝图数值无效');return v end
  if kind=='boolean' then return v end
  if kind=='string' then assert(#v<=256 and utf8.len(v),'装备蓝图文本无效');return v end
  assert(kind=='table' and not getmetatable(v),'装备蓝图数据类型无效')
  local out={};for k,x in pairs(v)do
   assert((type(k)=='string' and #k<=80) or (type(k)=='number' and k%1==0 and k>=1 and k<=512),'装备蓝图索引无效')
   out[k]=plain(x,depth+1)
  end;return out
 end
 local out=plain(value,0);assert(out.schema==1 and type(out.data)=='table','装备蓝图版本不支持')
 local d=out.data
 -- REFramework 将空 Lua 数组编码为 null；显式记录路径，回读后恢复数组类型。
 local paths=out.empty_arrays or {};assert(type(paths)=='table' and #paths<=512,'空数组索引无效')
 for _,path in ipairs(paths)do
  assert(type(path)=='table' and #path>=1 and #path<=8,'空数组路径无效')
  local owner=d
  for i=1,#path-1 do owner=owner[path[i]];assert(type(owner)=='table','空数组路径不存在')end
  local key=path[#path];assert(type(key)=='string' or type(key)=='number','空数组字段无效')
  assert(owner[key]==nil or (type(owner[key])=='table' and next(owner[key])==nil),'空数组标记与数据冲突')
  owner[key]={}
 end
 assert(type(d._weaponParam)=='table','武器数据缺失');integer(d._weaponParam.WeaponId,1,0xffffffff,'武器 ID')
 assert(type(d._armorParam)=='table' and #d._armorParam==5,'五件防具数据缺失')
 for i=1,5 do assert(type(d._armorParam[i])=='table','防具数据缺失');integer(d._armorParam[i].ArmorId,1,0xffffffff,'防具 ID')end
 assert(type(d._lvBuffParam)=='table','花链数据缺失');integer(d._lvBuffParam.id,1,0xffffffff,'花链 ID')
 assert(type(d._talismanParam)=='table','护石数据缺失')
 local status=d._equipStatusParam;assert(type(status)=='table','替换技数据缺失')
 if status.isMRRelease==false and status.switchActionId==nil then status.switchActionId={}end
 require('LoadoutClone.planner').validate_actions(status,status.isMRRelease)
 local empty={}
 local function collect(t,path)
  if next(t)==nil then empty[#empty+1]=path;return end
  for k,v in pairs(t)do if type(v)=='table' then local p=M.copy(path);p[#p+1]=k;collect(v,p)end end
 end
 collect(d,{})
 table.sort(empty,function(a,b)return table.concat(a,'/')<table.concat(b,'/')end)
 return {schema=1,data=d,empty_arrays=empty}
end
function M.validate(doc)
 assert(type(doc)=='table' and (doc.schema==1 or doc.schema==2),'蓝图库版本不支持或文件损坏')
 local count=integer(doc.count,0,M.limit,'蓝图数量')
 local out={schema=doc.schema,count=count,next_id=integer(doc.next_id,1,2147483647,'蓝图序号'),entries={}}
 local entries=doc.entries or (count==0 and {})
 assert(type(entries)=='table' and #entries==count,'蓝图库条目数量不一致')
 local seen={}
 for i,e in ipairs(entries)do
  assert(type(e)=='table' and type(e.origin)=='table','蓝图来源缺失')
  local id=integer(e.id,1,out.next_id-1,'蓝图编号');assert(not seen[id],'蓝图编号重复');seen[id]=true
  out.entries[i]={id=id,name=M.name(e.name),created=integer(e.created,0,9007199254740991,'保存时间'),
   origin={name=M.name(e.origin.name),sex=integer(e.origin.sex,0,1,'来源性别'),weapon_type=integer(e.origin.weapon_type,0,13,'武器类型')},snapshot=M.snapshot(e.snapshot),equipment=e.equipment and M.equipment(e.equipment) or nil}
  assert(not e.equipment or doc.schema==2,'完整配装需要新版蓝图库')
 end
 for k in pairs(entries)do assert(type(k)=='number' and k%1==0 and k>=1 and k<=count,'蓝图库条目无效')end
 return out
end
function M.new(storage) return setmetatable({storage=storage},{__index=M})end
function M:load()
 local value=self.storage.load()
 if value==nil then assert(not self.storage.exists(),'蓝图库存在但无法读取，请保留文件并检查备份');return {schema=1,count=0,next_id=1,entries={}}end
 return M.validate(value)
end
function M:save(before,after)
 assert(A.same(self:load(),before),'蓝图库已被更新，请刷新后重试')
 after=M.validate(after)
 assert(self.storage.backup(before),'蓝图库备份失败，未覆盖原文件')
 local ok,err=pcall(function()
  assert(self.storage.write(after),'蓝图库写入失败')
  assert(A.same(self:load(),after),'蓝图库保存回读不一致')
 end)
 if not ok then
  local restored=pcall(function()assert(self.storage.write(before));assert(A.same(self:load(),before))end)
  error(tostring(err)..(restored and '；已恢复原蓝图库' or '；恢复失败，请保留蓝图库与备份'))
 end
 return after
end
function M:find(id)
 local doc=self:load();for _,e in ipairs(doc.entries)do if e.id==id then return M.copy(e),doc end end
 error('蓝图已不存在，请刷新列表')
end
local function unique(doc,name,skip)
 local base=M.name(name);local result=base;local n=1
 local function used()for _,e in ipairs(doc.entries)do if e.id~=skip and e.name==result then return true end end end
 while used()do
  n=n+1;local suffix=' ('..n..')';local start=utf8.offset(base,math.max(1,49-#suffix));local shortened=start and base:sub(1,start-1) or base
  result=shortened..suffix
 end
 return result
end
function M:add(name,origin,snapshot,now,equipment)
 local before=self:load();assert(before.count<M.limit,'蓝图库已满，请删除不需要的蓝图')
 local after=M.copy(before);local entry={id=after.next_id,name=unique(after,name),origin=M.copy(origin),snapshot=M.snapshot(snapshot),created=now,equipment=equipment and M.equipment(equipment) or nil}
 if equipment then after.schema=2 end
 after.next_id=after.next_id+1;after.entries[#after.entries+1]=entry;after.count=#after.entries
 self:save(before,after);return M.copy(entry)
end
function M:rename(id,name)
 local _,before=self:find(id);local after=M.copy(before)
 for _,e in ipairs(after.entries)do if e.id==id then e.name=unique(after,name,id)end end
 return self:save(before,after)
end
function M:remove(id)
 local _,before=self:find(id);local after=M.copy(before)
 for i,e in ipairs(after.entries)do if e.id==id then table.remove(after.entries,i);break end end
 after.count=#after.entries;return self:save(before,after)
end
return M
