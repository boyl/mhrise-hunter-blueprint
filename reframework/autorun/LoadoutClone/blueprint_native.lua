-- 本机读取契约：blueprint-current-001/002/003；不依赖大厅。
local N=require('LoadoutClone.native')
local O=require('LoadoutClone.appearance_objects')
local C=require('LoadoutClone.appearance_color')
local B=require('LoadoutClone.blueprints')
local Identity=require('LoadoutClone.character_identity')
local M={}
local shortcut='snow.equip.EquipShortcut'
function M.new()return setmetatable({native=N.new()},{__index=M})end
function M:capture()
 self.native.game_method_calls=0
 local identity=Identity.current()
 local manager=assert(sdk.get_managed_singleton('snow.data.EquipDataManager'),'当前装备尚未就绪')
 local current=O.new(self.native):state(N.field(manager,'_PlOverwearMySetData'))
 local card=N.field(N.field(assert(sdk.get_managed_singleton('snow.GuildCardManager')),'_GuildCard'),'MyData')
 local sex=N.scalar(N.field(card,'Sex'));assert(sex==0 or sex==1,'当前角色性别未就绪')
 local pm=assert(sdk.get_managed_singleton('snow.player.PlayerManager'),'请先进入角色')
 local index=N.scalar(self.native:call('snow.player.PlayerManager','getMasterPlayerID()',pm))
 local n,get=N.array_access(N.field(pm,'<PlayerParam>k__BackingField'),16)
 assert(index>=0 and index<n,'请先进入角色')
 assert(N.scalar(self.native:call('snow.player.PlayerManager','getPlayerSexType(snow.player.PlayerRequestEquipsData)',pm,get(index)))==sex,'角色切换尚未完成')
 local indices=N.array(N.field(N.field(manager,'_PlEquipPack'),'_InventoryIndexList'))
 local box=N.field(assert(sdk.get_managed_singleton('snow.data.DataManager')),'_PlEquipBox')
 local list=N.field(box,'_WeaponArmorInventoryList')
 local count,at=N.array_access(N.field(list,'mItems'),5000)
 assert(indices[1]>=0 and indices[1]<count,'当前武器尚未就绪')
 local weapon=assert(at(indices[1]))
 assert(N.field(weapon,'<InventoryIndex>k__BackingField')==indices[1],'当前武器索引不一致')
 local kind=N.scalar(self.native:call(shortcut,'getPlWeaponType(snow.data.ContentsIdSystem.WeaponId)',nil,N.field(weapon,'_IdVal')))
 local snapshot={schema=1,weapon_id=current.weapon,armor_ids=current.armor,colors={{},{}},
  weapon_hidden=(N.scalar(N.field(manager,'_VisiblePartsFlag'))&1)==0,weapon_color=C.read(N.field(weapon,'_HyakuryuColorData'))}
 for p=1,5 do for ch=1,2 do snapshot.colors[ch][p]=current.colors[p][ch]end end
 assert(Identity.current()==identity,'读取期间角色已变化')
 return {identity=identity,origin={name=N.field(card,'HunterName'),sex=sex,weapon_type=kind},snapshot=B.snapshot(snapshot)}
end
-- 原生只读构造器经 blueprint-local-equipment-002 验证，不借用大厅缓存。
function M.legacy_actions(records)
 local legacy={0,0,0};local seen={}
 for _,entry in ipairs(records)do
  local group,id=entry.group,entry.id
  assert(type(group)=='number' and group%1==0 and group>=0 and type(id)=='number' and id%1==0 and id>=0,'基础替换技记录无效')
  if group<3 then assert(not seen[group],'基础替换技分组重复');seen[group]=true;legacy[group+1]=id end
 end
 return legacy
end
function M:capture_loadout()
 local before=self:capture()
 local Reader=require('LoadoutClone.reader')
 local function read(method,empty)
  local obj
  if method:find('Boolean',1,true)then obj=self.native:call('snow.gui.define.EquipDetailParamShortcut',method,nil,false,false)
  else obj=self.native:call('snow.gui.define.EquipDetailParamShortcut',method,nil)end
  if not obj then assert(empty,'本机配装尚未就绪');return {empty=true}end
  obj:add_ref();return Reader.plain(obj)
 end
 local data={_equipStatusParam=read('createEquipStatusParam(System.Boolean, System.Boolean)'),
  _weaponParam=read('createWeaponDataParam(System.Boolean, System.Boolean)'),
  _armorParam=read('createArmorDataParam()'),_lvBuffParam=read('createLvBuffDataParam()'),_talismanParam=read('createPlTalismanParam()',true)}
 local manager=assert(sdk.get_managed_singleton('snow.data.EquipDataManager'))
 local indices=N.array(N.field(N.field(manager,'_PlEquipPack'),'_InventoryIndexList'))
 local box=N.field(assert(sdk.get_managed_singleton('snow.data.DataManager')),'_PlEquipBox')
 local count,at=N.array_access(N.field(N.field(box,'_WeaponArmorInventoryList'),'mItems'),5000)
 local function exact(part,index,id)
  assert(type(index)=='number' and index>=0 and index<count,'当前装备索引无效')
  local item=assert(at(index));assert(N.scalar(N.field(item,'_IdVal'))==id,'本机显示数据与当前装备不一致')
  assert(N.scalar(N.field(item,'<InventoryIndex>k__BackingField'))==index,'当前装备索引不一致')
  part.ExactDecoIds=N.array(N.field(item,'_DecoIdList'))
  assert(#part.ExactDecoIds==3,'原始珠子列表长度无效')
 end
 exact(data._weaponParam,indices[1],data._weaponParam.WeaponId)
 for i=1,5 do exact(data._armorParam[i],indices[i+1],data._armorParam[i].ArmorId)end
 if not data._talismanParam.empty then exact(data._talismanParam,indices[8],data._talismanParam.id)
 else assert(indices[8]==-1,'护石数据尚未完整加载')end
 -- 本机界面包在大师等级下省略旧版列表；按原生 GroupIndex 读取独立配置。
 local actions=N.field(N.field(assert(sdk.get_managed_singleton('snow.data.SystemDataManager')),'_SwitchActionSystem'),'<ActiveActionDataList>k__BackingField')
 local weapon_count,get_weapon=N.array_access(actions,32)
 assert(before.origin.weapon_type<weapon_count,'替换技武器类型无效')
 local action_count,get_action=N.array_access(get_weapon(before.origin.weapon_type),8)
 local records={}
 for i=0,action_count-1 do
  local action=get_action(i)
  if action then
   local group=N.scalar(self.native:call('snow.data.PlSwitchActionData','get_GroupIndex()',action))
   records[#records+1]={group=group,id=N.scalar(N.field(action,'<ActionId>k__BackingField'))}
  end
 end
 data._equipStatusParam.switchActionId=M.legacy_actions(records)
 assert(data._equipStatusParam.name==before.origin.name,'配装与当前角色不一致')
 assert(require('LoadoutClone.appearance').same(before,self:capture()),'读取期间角色或外观已变化')
 return B.equipment({schema=1,data=data}),before
end
function M:progression_state()
 local obj=assert(self.native:call('snow.gui.define.EquipDetailParamShortcut','createEquipStatusParam(System.Boolean, System.Boolean)',nil,false,false),'角色状态尚未就绪'):add_ref()
 local state=N.scalar(N.field(obj,'isMRRelease'));assert(type(state)=='boolean','大师等级状态无效');return state
end
function M:adapt(snapshot,sex)
 self.native.game_method_calls=0
 local result=B.snapshot(snapshot);local changes={}
 for part,id in ipairs(result.armor_ids)do
  if id~=(part-1)*4096 then
   assert(self.native:call(shortcut,'isValid(snow.equip.PlOverwearId)',nil,id),'防具幻化 ID 无效')
   local flag=N.scalar(self.native:call(shortcut,'getSexualEquipableFlag(snow.equip.PlOverwearId)',nil,id))
   assert(flag==0 or flag==1 or flag==2,'防具幻化适用信息无效')
   if flag~=2 and flag~=sex then
    local pair=N.scalar(self.native:call(shortcut,'findPairSexOverwearId(snow.equip.PlOverwearId)',nil,id))
    assert(pair~=id and self.native:call(shortcut,'isValid(snow.equip.PlOverwearId)',nil,pair),'没有适用于当前角色的对应幻化')
    assert(N.scalar(self.native:call(shortcut,'getSexualEquipableFlag(snow.equip.PlOverwearId)',nil,pair))==sex,'对应幻化性别不匹配')
    assert(N.scalar(self.native:call(shortcut,'getArmorPartsType(snow.equip.PlOverwearId)',nil,pair))==part-1,'对应幻化部位不匹配')
    result.armor_ids[part]=pair;changes[#changes+1]={part=part,from=id,to=pair}
   end
  end
 end
 O.new(self.native):build(result,'蓝图校验')
 return result,changes
end
function M:describe(snapshot)
 self.native.game_method_calls=0
 local out={armor={},weapon='不使用武器幻化'}
 for part,id in ipairs(snapshot.armor_ids)do
  out.armor[part]=id==(part-1)*4096 and '不使用幻化' or self.native:call(shortcut,'getName(snow.equip.PlOverwearId)',nil,id)
 end
 if snapshot.weapon_id~=134217728 then out.weapon=self.native:call(shortcut,'getName(snow.data.ContentsIdSystem.OverwearWeaponId)',nil,snapshot.weapon_id)end
 return out
end
function M:weapon_type(id)
 assert(id~=134217728,'空武器幻化没有武器类型')
 return N.scalar(self.native:call(shortcut,'getDtWeaponType(snow.data.ContentsIdSystem.OverwearWeaponId)',nil,id))
end
return M
