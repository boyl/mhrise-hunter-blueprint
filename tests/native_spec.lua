local Native=require("LoadoutClone.native")
local retained=false
local weapon={add_ref=function(self) retained=true;return self end}
local slots={get_size=function() return 4 end,get_element=function(_,i) return i==0 and 1 or 0 end}
slots.add_ref=function() end
slots.get_type_definition=function() return {is_array=function() return true end,get_full_name=function() return "System.Int32[]" end,get_method=function() return {call=function(_,v,i) return v:get_element(i) end} end} end
sdk={find_type_definition=function() return {get_method=function() return {call=function(_,v) return v:get_size() end} end} end}
local native=Native.new()
function native:call(_,method,owner)
    if method:find("getPlainWeaponData",1,true) then return weapon end
    assert(retained,"新建临时武器必须在后续原生调用前持有引用")
    assert(owner==weapon)
    if method=="get_DecorationSlotNumList()" then return slots end
    return 3
end
local result=native:weapon_base(145752403)
assert(result.slots[1]==1 and result.table==3)
print("PASS 临时武器返回对象在后续调用前持有引用（1 项）")
