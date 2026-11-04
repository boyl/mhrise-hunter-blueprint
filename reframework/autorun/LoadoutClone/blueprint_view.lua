local M={}
local parts={'头部','胸部','腕部','腰部','腿部'}
-- snow.data.weapon.WeaponTypes：blueprint-meta-004 实机枚举。
local weapons={'大剑','大锤','长枪','片手剑','轻弩','重弩','双刀','太刀','狩猎笛','铳枪','弓','斩斧','盾斧','操虫棍'}
function M.draw(c,width,ui)
 local full_width=width
 local text=function(s,color)ui.wrapped(s,width,color or ui.color.muted)end
 local height=math.max(36,math.ceil(imgui.calc_text_size('外观').y)+18)
 local busy=c.pending~=nil or c.external_busy
 text('保存、管理与导入角色蓝图。',ui.color.heading)
 text(c.current and ('当前角色：'..c.current.origin.name) or '请先进入角色')
 if c.context_error then text(c.context_error:match('[^\n]+'),ui.color.error)end
 if c.error then text(c.error:match('%.lua:%d+: ([^\n]+)') or c.error:match('[^\n]+'),ui.color.error)end
 if c.message then text(c.message,ui.color.success)end
 if busy then text('正在处理，请稍候……',ui.color.heading)end
 ui.space()
 local columns=full_width>=840 and imgui.begin_table('blueprint_layout',2,0,{full_width,0})
 if columns then
  imgui.table_setup_column('library',0,1)
  imgui.table_setup_column('details',0,1)
  imgui.table_next_column();width=math.floor(full_width/2)-24
 end
 local ok,err=pcall(function()
 ui.heading('保存蓝图')
 if not busy then
  text('蓝图名称')
  imgui.set_next_item_width(width)
  local changed,value=imgui.input_text('##blueprint_name',c.name)
  if changed then c.name=value end
  if c.ready and imgui.button('保存当前配装',{width,height})then c:queue('save')end
 end
 ui.heading('我的蓝图  ·  '..#c.entries..' / 100')
 if #c.entries==0 then text('还没有蓝图，可先保存当前角色的配装。')end
 local start=(c.page-1)*c.page_size+1
 for i=start,math.min(#c.entries,start+c.page_size-1)do
  local e=c.entries[i]
  imgui.push_id(e.id)
  local label=ui.fitted((c.selected==e.id and '已选中 | ' or '')..e.name,width-28)..'\n'..ui.fitted((e.equipment and '完整配装' or '外观蓝图')..' · '..e.origin.name..' · '..(weapons[e.origin.weapon_type+1] or '未知武器'),width-28)
  imgui.push_style_var(24,Vector2f.new(0,0.5))
  local pressed=imgui.button(label,{width,height*2-12})
  imgui.pop_style_var();imgui.pop_id()
  if pressed and not busy then c:select(e.id)end
  imgui.spacing()
 end
 local pages=math.max(1,math.ceil(#c.entries/c.page_size))
 if pages>1 then
  local w=math.floor((width-12)/2)
  if imgui.button('上一页',{w,height}) and c.page>1 then c.page=c.page-1 end
  imgui.same_line()
  if imgui.button('下一页',{w,height}) and c.page<pages then c.page=c.page+1 end
  text('第 '..c.page..' / '..pages..' 页')
 end
 if not busy and imgui.button('刷新列表',{width,height})then c:queue('refresh')end
 if columns then imgui.table_next_column()end
 if c.selected then
  local entry
  for _,e in ipairs(c.entries)do if e.id==c.selected then entry=e end end
  local has_equipment=entry and entry.equipment~=nil
  ui.heading(entry and entry.name or '蓝图详情')
  text(has_equipment and '完整配装 · 装备、珠子、炼化与替换技' or '外观蓝图 · 幻化与染色',ui.color.heading)
  ui.heading('导入选项')
  local function option(label,key)
   if not busy then local changed,value=imgui.checkbox(label,c[key]==true);if changed then c:set_option(key,value)end end
  end
  if has_equipment then option('仅导入外观','appearance_only')end
  local full=has_equipment and not c.appearance_only
  if full then
   option('复制炼化（武器与防具）','copy_augments')
   if c.copy_augments then option('允许非法炼化（不一定实际非法）','allow_illegal_augments')end
   option('复制外观（幻化与染色）','copy_appearance')
  else option('包含武器外观','include_weapon')end
  if (not full or c.copy_appearance) and (full or c.include_weapon) and c.service.appearance.weapon_visibility_available~=false then option('复制武器显示状态','copy_weapon_visibility')end
  if not full and not c.include_weapon then text('保留当前武器幻化，只导入防具幻化与染色。')end
  if c.service.appearance.visibility_warning then text(c.service.appearance.visibility_warning)end
  if c.preview then
   local preview=c.preview
   if preview.full then
    text('包含：武器、5 件防具、花链、护石及珠子。')
    text(preview.entry.equipment.data._equipStatusParam.isMRRelease and '替换技：朱／苍两书' or '替换技：基础配置')
   end
   if preview.description then
   ui.heading('外观预览')
   text('武器：'..preview.description.weapon)
   for i,name in ipairs(preview.description.armor)do text(parts[i]..'：'..name)end
   local count=0;for _,channel in ipairs(preview.snapshot.colors)do for _,color in ipairs(channel)do if color.enabled then count=count+1 end end end
   text('自定义染色：'..count..' 个通道  ·  保存于 '..os.date('%Y-%m-%d %H:%M',preview.entry.created))
   for _,change in ipairs(preview.changes)do text(parts[change.part]..'已适配为当前性别的对应款式。',ui.color.heading)end
   end
   ui.space()
   if not busy and imgui.button('导入到当前角色',{width,height+8})then c:queue('import')end
  elseif not busy and c.ready and imgui.button('检查所选蓝图',{width,height})then c:queue('preview')end
  text('保存为猎人个人组合，当前穿着不变。')
  ui.space()
  if not busy and imgui.tree_node('管理所选蓝图')then
   if imgui.button('使用填写的名称重命名',{width,height})then c:queue('rename')end
   if c.delete_id==c.selected then
    text('删除仅影响蓝图库，已导入的游戏组合会保留。')
    if imgui.button('确认删除蓝图',{width,height})then c:queue('delete')end
    if imgui.button('取消删除',{width,height})then c.delete_id=nil end
   elseif imgui.button('删除所选蓝图',{width,height})then c.delete_id=c.selected end
   imgui.tree_pop()
  end
 else
  ui.heading('蓝图详情')
  text('选择左侧蓝图，查看内容与导入选项。')
 end
 end)
 if columns then imgui.end_table()end
 if not ok then error(err)end
end
return M
