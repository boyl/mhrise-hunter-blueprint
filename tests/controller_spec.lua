local Controller=require("LoadoutClone.controller")
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function setup()
    local reads=0
    local source={session="one",members={{key="A",name="同名"},{key="B",name="同名"}}}
    local adapter={list_members=function() return source end,capture=function(_,key) reads=reads+1;return {key=key} end}
    local c=Controller.new(adapter)
    return c,source,function() return reads end
end
local count=0
local function test(name,fn) fn();count=count+1;print("PASS "..name) end
test("同名玩家按稳定身份选择",function()
    local c=setup();c:refresh();c:select("B");eq(c.selected,"B")
end)
test("刷新排序不改变选中身份",function()
    local c,s=setup();c:refresh();c:select("B");s.members={s.members[2],s.members[1]};c:refresh();eq(c.selected,"B")
end)
test("玩家退出清除选择和待处理操作",function()
    local c,s,reads=setup();c:refresh();c:select("B");c:request_capture();s.members={s.members[1]};c:refresh();c:step();eq(c.selected,nil);eq(reads(),0)
end)
test("切换会话清除旧选择",function()
    local c,s=setup();c:refresh();c:select("A");s.session="two";c:refresh();eq(c.selected,nil)
end)
test("一个待处理请求只读取一次",function()
    local c,_,reads=setup();c:refresh();c:select("A");eq(c:request_capture(),true);eq(c:request_capture(),false);c:step();c:step();eq(reads(),1)
end)
test("排队后换目标取消原请求",function()
    local c,_,reads=setup();c:refresh();c:select("A");c:request_capture();c:select("B");c:step();eq(reads(),0)
end)
test("读取异常明确可见且不伪造成功",function()
    local c=setup();c:refresh();c:select("A");c.adapter.capture=function() error("packet missing") end;c:request_capture();c:step();eq(c.state,"error");assert(c.error:find("packet missing"));eq(c.snapshot,nil)
end)
test("炼化默认开启且请求记录选项",function()
    local c=setup();eq(c.copy_augments,true);c:refresh();c:select("A");c:request_capture();eq(c.pending.options.copy_augments,true)
    c:step();eq(c.snapshot.options.copy_augments,true)
end)
test("切换炼化取消旧请求保留玩家",function()
    local c,_,reads=setup();c:refresh();c:select("A");c:request_capture();c:set_copy_augments(false);c:step()
    eq(reads(),0);eq(c.selected,"A");eq(c.pending,nil);eq(c.copy_augments,false)
    c:request_capture();c:step();eq(c.snapshot.options.copy_augments,false)
end)
test("切换炼化使旧结果失效，同值不清除",function()
    local c=setup();c:refresh();c:select("A");c:request_capture();c:step()
    c:set_copy_augments(true);assert(c.snapshot);c:set_copy_augments(false);eq(c.snapshot,nil);eq(c.state,"ready")
end)
test("放宽炼化默认开启并绑定请求",function()
    local c=setup();eq(c.allow_illegal_augments,true);c:refresh();c:select("A");c:request_capture()
    c:set_allow_illegal_augments(false);eq(c.pending,nil);eq(c.selected,"A")
    c:request_capture();c:step();eq(c.snapshot.options.allow_illegal_augments,false)
end)
test("关闭炼化清除非法选项且不能隐式开启",function()
    local c=setup();c:set_allow_illegal_augments(true);c:set_copy_augments(false);eq(c.allow_illegal_augments,false)
    eq(c:set_allow_illegal_augments(true),false);eq(c.allow_illegal_augments,false)
    c:set_copy_augments(true);eq(c.allow_illegal_augments,false)
end)
test("复制分帧准备且只提交一次",function()
    local c=setup();local commits=0
    c.adapter.prepare=function() coroutine.yield({phase="catalog",done=8});return {ready=true} end
    c.adapter.commit=function(_,plan) assert(plan.ready);commits=commits+1;return {ok=true,result={slot=9}} end
    c:refresh();c:select("A");assert(c:request_copy());eq(c:request_copy(),false)
    c:step();eq(commits,0);c:step();eq(commits,0);c:step();eq(commits,1);eq(c.result.slot,9);c:step();eq(commits,1)
end)
test("准备期间玩家退出取消提交",function()
    local c,s=setup();local commits=0
    c.adapter.prepare=function() return {} end
    c.adapter.commit=function() commits=commits+1;return {ok=true,result={}} end
    c:refresh();c:select("A");c:request_copy();c:step();s.members={};c:refresh();c:step();eq(commits,0)
end)
test("准备后改变炼化选项取消提交",function()
    local c=setup();local commits=0
    c.adapter.prepare=function() return {} end
    c.adapter.commit=function() commits=commits+1;return {ok=true,result={}} end
    c:refresh();c:select("A");c:request_copy();c:step();c:set_allow_illegal_augments(false);c:step();eq(commits,0)
end)
test("外观默认关闭并冻结到请求",function()
    local c=setup();eq(c.copy_appearance,false);c:refresh();c:select("A")
    c:set_copy_appearance(true);c:request_capture();eq(c.pending.options.copy_appearance,true)
    c:step();eq(c.snapshot.options.copy_appearance,true)
end)
test("准备后改变外观选项取消提交",function()
    local c=setup();local commits=0
    c.adapter.prepare=function(_,_,options) eq(options.copy_appearance,false);return {} end
    c.adapter.commit=function() commits=commits+1;return {ok=true,result={}} end
    c:refresh();c:select("A");c:request_copy();c:step();c:set_copy_appearance(true);c:step();eq(commits,0);eq(c.selected,"A")
end)
print("TOTAL "..count)

test("协程失败保留实际原因并清理任务",function()
 local c=setup();c:refresh();c:select("A")
 c.adapter.prepare=function() error("prepare sentinel") end
 c:request_copy();c:step()
 eq(c.state,"error");eq(c.pending,nil);eq(c.job,nil)
 assert(c.error:find("prepare sentinel",1,true),c.error)
end)
