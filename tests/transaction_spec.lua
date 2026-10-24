local Transaction=require("LoadoutClone.transaction")
local function equal(a,b,message) assert(a==b,message or (tostring(a).." ~= "..tostring(b))) end
local tests=0
local function test(name,fn) fn(); tests=tests+1; print("PASS "..name) end
local function fixture(fail)
    local box={a=10,b=20,loadout=0}
    local calls={apply=0,restore=0}
    local adapter={}
    function adapter:prepare(target)
        if fail=="preflight" then error("capacity") end
        return {target=target,token="session-A",entries={{key="a",before=10,after=30},{key="b",before=20,after=40},{key="loadout",before=0,after=1}}}
    end
    function adapter:assert_context(plan)
        if fail=="context" then error("target left") end
        equal(plan.token,"session-A")
    end
    function adapter:apply(entry)
        calls.apply=calls.apply+1
        box[entry.key]=entry.after
        if fail==entry.key or fail=="rollback" then error("partial mutation") end
    end
    function adapter:verify(plan)
        if fail=="verify" then error("readback mismatch") end
        for _,entry in ipairs(plan.entries) do equal(box[entry.key],entry.after) end
        return {slot=224,name="copy"}
    end
    function adapter:restore(entry)
        calls.restore=calls.restore+1
        if fail=="rollback" then error("restore failed") end
        box[entry.key]=entry.before
    end
    function adapter:verify_restored(entry) equal(box[entry.key],entry.before) end
    return adapter,box,calls
end
test("完整回读后才成功",function()
    local a,box=fixture(); local tx=Transaction.new(a)
    local r=tx:execute("hunter-A"); equal(r.ok,true);equal(r.result.slot,224);equal(box.loadout,1)
end)
for _,stage in ipairs({"preflight","context","a","b","loadout","verify"}) do
    test("失败恢复: "..stage,function()
        local a,box,calls=fixture(stage);local tx=Transaction.new(a);local r=tx:execute("hunter-A")
        equal(r.ok,false);equal(tx.locked,false);equal(box.a,10);equal(box.b,20);equal(box.loadout,0)
        if stage=="preflight" or stage=="context" then equal(calls.apply,0) end
    end)
end
test("恢复失败锁定后续写入",function()
    local a,_,calls=fixture("rollback");local tx=Transaction.new(a)
    local r=tx:execute("hunter-A");equal(r.ok,false);equal(r.code,"recovery_failed");equal(tx.locked,true)
    local count=calls.apply;equal(tx:execute("hunter-A").code,"locked");equal(calls.apply,count)
end)
test("重入不重复写入",function()
    local a,_,calls=fixture();local tx=Transaction.new(a);local original=a.apply
    function a:apply(entry) equal(tx:execute("hunter-A").code,"busy");original(self,entry) end
    equal(tx:execute("hunter-A").ok,true);equal(calls.apply,3)
end)
test("无效计划不执行写入",function()
    local a,_,calls=fixture();function a:prepare() return {entries={}} end
    local tx=Transaction.new(a);equal(tx:execute("hunter-A").ok,false);equal(calls.apply,0)
end)
print("TOTAL "..tests)
