local V=require('LoadoutClone.blueprint_view')
local texts,buttons={},{ }
Vector2f={new=function(x,y)return {x=x,y=y}end}
local width=320
local tables=0
imgui={begin_table=function()tables=tables+1;return true end,end_table=function()tables=tables-1 end,table_setup_column=function()end,table_next_column=function()end,set_next_item_width=function(w)assert(w<=width)end,tree_node=function()return false end,tree_pop=function()end,calc_text_size=function()return {x=22,y=22}end,input_text=function(_,v)return false,v end,
 checkbox=function(_,v)return false,v end,button=function(label,size)assert(size[1]<=width and size[2]>=36);buttons[#buttons+1]=label;return false end,
 push_id=function()end,pop_id=function()end,push_style_var=function()end,pop_style_var=function()end,spacing=function()end,same_line=function()end}
local ui={wrapped=function(s)texts[#texts+1]=s end,fitted=function(s)return s end,heading=function()end,space=function()end,color={}}
local c={ready=true,current={origin={name='当前角色'}},entries={},page=1,page_size=4,name='',service={appearance={weapon_visibility_available=false,visibility_warning='接口缺失'}},include_weapon=true}
V.draw(c,width,ui);assert(buttons[1]=='保存当前配装')
for i=1,9 do c.entries[i]={id=i,name='蓝图'..i,origin={name='来源角色',weapon_type=9}}end
c.selected=1
c.preview={snapshot={colors={{},{}}},description={weapon='武器',armor={'头','胸','腕','腰','腿'}},entry={created=1},changes={}}
for _,w in ipairs({320,584,900})do width=w;buttons={};V.draw(c,width,ui);local cards=0;for _,v in ipairs(buttons)do if v:find('外观蓝图 ·',1,true)then cards=cards+1 end;assert(v~='复制武器显示状态')end;assert(cards==4)end
c.page=3;buttons={};V.draw(c,width,ui);local cards=0;for _,v in ipairs(buttons)do if v:find('外观蓝图 ·',1,true)then cards=cards+1 end end;assert(cards==1)
assert(tables==0)
for _,t in ipairs(texts)do assert(not t:find('大号',1,true) and not t:find('小号',1,true))end
print('PASS 蓝图空列表、分页末页、三种窗口宽度按钮边界与缺少显示能力的呈现')
