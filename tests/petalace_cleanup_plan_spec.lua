local P=require("LoadoutClone.petalace_cleanup_plan")
local function item(index,id) return {index=index,kind=4,id=id} end
local s={items={item(0,123),item(1,123),item(2,456)},current=1,references={{owner="set:0",index=0},{owner="set:1",index=2}}}
local p=P.plan(s)
assert(#p.remove==1 and p.remove[1]==0 and p.redirect[0]==1)
assert(#p.references==1 and p.references[1].after==1 and #s.items==3)
s.current=-1;p=P.plan(s);assert(p.remove[1]==1 and p.redirect[1]==0)
s.items[2].locked=true;p=P.plan(s);assert(#p.remove==0)
s.items[2].locked=false;s.items[2].guild_card=true;p=P.plan(s);assert(#p.remove==0)
s.items[2].guild_card=false;s.items[2].kind=5;p=P.plan(s);assert(#p.remove==0)
s.references[1].index=99;assert(not pcall(P.plan,s))
s.references[1].index=0;s.items[2].index=0;assert(not pcall(P.plan,s))
assert(#P.plan({items={},references={},current=-1}).remove==0)
print("PASS 清理纯规划：保留当前花链、同 ID 不同类型、锁定/名片保护、引用重定向及悬空拒绝；零写入")
