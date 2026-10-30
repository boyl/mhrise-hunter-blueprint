-- 只生成清理建议，不持有原生对象、不修改存档。
local M={}
function M.plan(snapshot)
 assert(type(snapshot)=="table" and type(snapshot.items)=="table" and type(snapshot.references)=="table","清理快照缺失")
 local by_index,groups={},{}
 for _,item in ipairs(snapshot.items) do
  assert(type(item.index)=="number" and item.index>=0 and item.index%1==0 and not by_index[item.index],"花链索引重复或无效")
  assert(type(item.kind)=="number" and item.kind>0 and type(item.id)=="number" and item.id>0,"花链类型或 ID 无效")
  by_index[item.index]=item
  local key=item.kind..":"..item.id
  groups[key]=groups[key] or {};table.insert(groups[key],item)
 end
 if snapshot.current and snapshot.current~=-1 then assert(by_index[snapshot.current],"当前花链引用缺失") end
 local out={remove={},retain={},redirect={},references={}}
 for _,items in pairs(groups) do
  table.sort(items,function(a,b)return a.index<b.index end)
  local keep=items[1]
  for _,item in ipairs(items) do if item.index==snapshot.current then keep=item;break end end
  out.retain[#out.retain+1]=keep.index
  for _,item in ipairs(items) do
   if item~=keep then
    -- 名片或锁定对象涉及额外语义；先保留，不能静默丢失这些标记。
    if item.locked or item.guild_card then out.retain[#out.retain+1]=item.index
    else out.remove[#out.remove+1]=item.index;out.redirect[item.index]=keep.index end
   end
  end
 end
 for _,ref in ipairs(snapshot.references) do
  assert(type(ref.owner)=="string" and type(ref.index)=="number","花链引用无效")
  if ref.index~=-1 then assert(by_index[ref.index],"已有组合花链引用悬空，停止清理") end
  if out.redirect[ref.index] then out.references[#out.references+1]={owner=ref.owner,before=ref.index,after=out.redirect[ref.index]} end
 end
 table.sort(out.remove);table.sort(out.retain)
 out.needs_layout=false
 for i,index in ipairs(out.retain)do if index~=i-1 then out.needs_layout=true end end
 return out
end
return M
