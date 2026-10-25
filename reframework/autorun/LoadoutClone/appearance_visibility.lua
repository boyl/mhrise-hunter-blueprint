-- 显示状态的纯数据事务；原生切换钩子与文件 IO 由适配器提供。
local A=require("LoadoutClone.appearance")
local M={}
local function clone(v,depth)
 depth=depth or 0;assert(depth<=12,"显示状态数据过深")
 if type(v)~="table" then
  assert(type(v)=="string" or type(v)=="boolean" or (type(v)=="number" and v==v and math.abs(v)<math.huge),"显示状态不是纯数据")
  return v
 end
 local out={};local count=0
 for k,x in pairs(v) do
  count=count+1;assert(count<=4096 and (type(k)=="string" or type(k)=="number"),"显示状态结构无效")
  out[k]=clone(x,depth+1)
 end
 return out
end
local function document(value)
 assert(type(value)=="table" and value.schema==1 and type(value.records)=="table","显示状态文件缺失或损坏")
 assert(#value.records<=1024,"显示状态记录超出上限")
 local count=0
 for k,row in pairs(value.records) do
  count=count+1
  assert(type(k)=="number" and k%1==0 and k>=1 and k<=#value.records,"显示状态记录不连续")
  assert(type(row)=="table" and type(row.character)=="string" and type(row.fingerprint)=="table" and type(row.hidden)=="boolean","显示状态记录无效")
 end
 assert(count==#value.records)
 return clone(value)
end
function M.new(storage)
 assert(storage and type(storage.load)=="function" and type(storage.save)=="function","显示状态存储缺失")
 return setmetatable({storage=storage},{__index=M})
end
function M:lookup(character,fingerprint)
 local found
 for _,row in ipairs(document(self.storage.load()).records) do
  if row.character==character and A.same(row.fingerprint,fingerprint) then
   assert(found==nil,"显示状态绑定重复");found=row.hidden
  end
 end
 return found
end
function M:prepare(character,fingerprint,hidden)
 assert(type(character)=="string" and #character>0 and #character<=256,"角色身份无效")
 assert(type(fingerprint)=="table" and (hidden==nil or type(hidden)=="boolean"),"显示状态候选无效")
 local before=document(self.storage.load());local after=clone(before)
 local match
 for i,row in ipairs(after.records) do
  if row.character==character and A.same(row.fingerprint,fingerprint) then assert(not match,"显示状态绑定重复");match=i end
 end
 if hidden==nil then
  if match then table.remove(after.records,match) end
 else
  if not match then assert(#after.records<1024,"显示状态记录已满");match=#after.records+1 end
  after.records[match]={character=character,fingerprint=clone(fingerprint),hidden=hidden}
 end
 return {before=before,expected=after}
end
function M:apply(entry)
 assert(A.same(document(self.storage.load()),entry.before),"显示状态文件已变化")
 if A.same(entry.before,entry.expected) then return end
 entry.write_started=true
 self.storage.save(clone(entry.expected))
 self:verify(entry)
end
function M:verify(entry)
 assert(A.same(document(self.storage.load()),entry.expected),"显示状态保存回读失败")
end
function M:restore(entry)
 if not entry.write_started then return end
 local current=self.storage.load()
 assert(current==nil or A.same(current,entry.expected) or A.same(current,entry.before),"显示状态文件发生外部变更，拒绝覆盖")
 self.storage.save(clone(entry.before))
 assert(A.same(document(self.storage.load()),entry.before),"显示状态恢复失败")
end
return M
