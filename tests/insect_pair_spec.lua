local Writer=require("LoadoutClone.writer")
local fields={_PairInsectInventoryIndex=0}
local obj={get_field=function(_,key) return fields[key] end}
local linked={get_field=function(_,key) assert(key=="<InventoryIndex>k__BackingField");return 1234 end}
fields["<PairInsectInventory>k__BackingField"]=linked
assert(Writer.pair_index(obj)==1234,"运行时应验证真实关联对象，不能把尚未序列化的 0 当作配对失败")
fields["<PairInsectInventory>k__BackingField"]=nil
fields._PairInsectInventoryIndex=-1
assert(Writer.pair_index(obj)==-1)
print("PASS 猎虫运行时关联与无关联状态（2 项）")
