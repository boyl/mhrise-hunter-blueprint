-- 原生组合与按角色保存的武器显示状态之间的边界。
local N=require("LoadoutClone.native")
local A=require("LoadoutClone.appearance")
local H=require("LoadoutClone.hunter")
local O=require("LoadoutClone.appearance_objects")
local V=require("LoadoutClone.appearance_visibility")
local Identity=require("LoadoutClone.character_identity")
local M={}
local path="LoadoutClone/appearance-visibility.json"
local function storage()
 local function load()
  local v=json.load_file(path)
  assert(v and v.schema==1 and type(v.record_count)=="number","显示状态文件损坏")
  local records=v.records or (v.record_count==0 and {})
  assert(type(records)=="table" and #records==v.record_count,"显示状态文件记录数不符")
  return {schema=1,records=records}
 end
 local function save(v)
  assert(json.dump_file(path,{schema=1,record_count=#v.records,records=v.records}),"显示状态文件写入失败")
 end
 if json.load_file(path)==nil then
  assert(#fs.glob([[LoadoutClone[\\/]appearance-visibility\.json]])==0,"显示状态文件存在但无法读取")
  save({schema=1,records={}})
 end
 load()
 return {load=load,save=save}
end
function M.new(reader,io)
 local native=N.new()
 return setmetatable({reader=reader,native=native,objects=O.new(native),store=V.new(io or storage())},{__index=M})
end
function M:character()
 return Identity.current()
end
function M:fingerprint(manager,hunter)
 local h=H.state(hunter)
 assert(h._IsUsing,"猎人组合未登记")
 local n,equip=N.array_access(N.field(manager,"_PlEquipMySetList"),1024)
 assert(h._EquipMysetIndex>=-1 and h._EquipMysetIndex<n,"装备组合关联无效")
 local count,overwear=N.array_access(N.field(manager,"_PlOverwearMySetList"),1024)
 assert(h._OverwearMysetIndex>=0 and h._OverwearMysetIndex<count,"外观组合关联无效")
 return {hunter=h,equipment=h._EquipMysetIndex>=0 and require("LoadoutClone.writer").set_state(equip(h._EquipMysetIndex)) or false,
  appearance=self.objects:state(overwear(h._OverwearMysetIndex))}
end
function M:prepare(plan)
 return {kind="visibility",plan=plan,character=self:character(),before_document=self.store.storage.load()}
end
function M:apply(entry)
 assert(self:character()==entry.character,"显示状态角色已变化")
 assert(A.same(self.store.storage.load(),entry.before_document),"显示状态文件已变化")
 local plan=entry.plan
 local _,get=N.array_access(N.field(plan.manager,"_HunterMySetList"),1024)
 local fp=self:fingerprint(plan.manager,get(plan.hunter_slot))
 local hidden
 if plan.source.options and plan.source.options.copy_weapon_visibility==true then hidden=plan.source.appearance.snapshot.weapon_hidden end
 entry.record=self.store:prepare(entry.character,fp,hidden)
 entry.write_started=true
 self.store:apply(entry.record)
end
function M:verify(entry) self.store:verify(assert(entry.record)) end
function M:restore(entry)
 if entry.write_started and entry.record then self.store:restore(entry.record) end
end
function M:verify_restored(entry)
 if entry.write_started then assert(A.same(self.store.storage.load(),entry.before_document),"显示状态恢复回读失败") end
end
function M:selection(manager,hunter)
 if not N.field(hunter,"_IsUsing") or N.field(hunter,"_OverwearMysetIndex")<0 then return nil end
 return self.store:lookup(self:character(),self:fingerprint(manager,hunter))
end
function M:matches_current(manager,hunter)
 if not N.field(hunter,"_IsUsing") then return false end
 local slot=N.field(hunter,"_EquipMysetIndex")
 if slot==-1 then
  local fp=self:fingerprint(manager,hunter)
  local current=self.objects:state(N.field(manager,"_PlOverwearMySetData"))
  return A.same(current.armor,fp.appearance.armor) and A.same(current.colors,fp.appearance.colors) and current.weapon==fp.appearance.weapon
 end
 local n,get=N.array_access(N.field(manager,"_PlEquipMySetList"),1024)
 if slot<0 or slot>=n then return false end
 local expected=N.array(N.field(get(slot),"_InventoryIndexList"))
 local current=N.array(N.field(N.field(manager,"_PlEquipPack"),"_InventoryIndexList"))
 return A.same(current,expected)
end
function M:apply_hidden(manager,hidden)
 assert(type(hidden)=="boolean")
 local old=N.scalar(N.field(manager,"_VisiblePartsFlag"))
 self.native:call("snow.data.EquipDataManager","changeVisiblePartsFlag",manager,1,not hidden)
 local actual=N.scalar(N.field(manager,"_VisiblePartsFlag"))
 assert((actual & 1)==(hidden and 0 or 1) and (actual & ~1)==(old & ~1),"武器显示状态回读不一致")
end
return M
