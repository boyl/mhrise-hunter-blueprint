local M={}
function M.run(request,report,checkpoint)
    local N=require("LoadoutClone.native")
    local reader=require("LoadoutClone.reader").new()
    local native=N.new()
    local field=N.field
    local target
    for _,member in ipairs(reader:list_members().members) do if member.key==request.key then target=member end end
    assert(target,"目标已离开")
    checkpoint("appearance packet IDs")
    local manager=assert(sdk.get_managed_singleton("snow.gui.EquipStatusParamManager"))
    local packet=field(manager,"_lobbyParam"):get_element(target.index)
    report.weapon_id=field(field(packet,"_overwearWeaponParam"),"Id")
    report.armor_ids={}
    local armor=field(packet,"_overwearParam")
    assert(armor:get_size()==5,"appearance part count")
    for i=0,4 do report.armor_ids[i+1]=field(armor:get_element(i),"Id") end
    checkpoint("appearance send data")
    local lobby=assert(sdk.get_managed_singleton("snow.LobbyManager"))
    local info=field(lobby,"_equipInfo"):get_element(target.index)
    local send=field(info,"_CharaCreate")
    local base_type="snow.player.PlayerManager.PlayerCreateBaseData"
    local base=assert(sdk.create_instance(base_type,true)):add_ref()
    checkpoint("detached PlayerCreateBaseData ctor")
    native:call(base_type,".ctor()",base)
    checkpoint("PlayerCreateSendData.copyTo detached base")
    native:call("snow.player.PlayerCreateSendData","copyTo",send,base)
    local function color(v)
        local rgba={}
        -- 字段 Float4 是 Vector4f，数组元素是装箱对象；统一分量后按值传参。
        for _,key in ipairs({"x","y","z","w"}) do rgba[key]=assert(v[key]) end
        local vector=Vector4f.new(rgba.x,rgba.y,rgba.z,rgba.w)
        local hsv=native:call("snow.gui.SnowGuiCommonUtility","convertFloat42HSV(via.Float4)",nil,vector)
        local out={rgba=rgba,hsv={}}
        for _,key in ipairs({"x","y","z"}) do out.hsv[key]=field(hsv,key) end
        return out
    end
    report.colors={}
    for channel=1,2 do
        local flags=field(base,"_IsEnableSymbolColor"..channel)
        local colors=field(base,"_SymbolColor"..channel)
        assert(flags:get_size()==5 and colors:get_size()==5,"color part count")
        report.colors[channel]={}
        for i=0,4 do
            checkpoint("color conversion "..channel..":"..i)
            local item=color(colors:get_element(i));item.enabled=N.scalar(flags:get_element(i))
            report.colors[channel][i+1]=item
        end
    end
    report.weapon_color=color(field(base,"_WeaponColor"))
    report.weapon_color.enabled=field(base,"_IsEnableWeaponColor")
    checkpoint("detached overwear set ctor")
    local set_type="snow.equip.PlOverwearMySetData"
    local set=assert(sdk.create_instance(set_type,true)):add_ref()
    native:call(set_type,".ctor()",set)
    report.empty_ids=N.array(field(set,"_PlOverwearIdList"))
    report.empty_weapon_id=field(set,"_OverwearWeaponId")
    local parts=field(field(set,"_OverwearSymbolColor"),"_Parts")
    report.color_layout={parts=parts:get_size(),channels={}}
    assert(parts:get_size()<=8,"color parts limit")
    for i=0,parts:get_size()-1 do report.color_layout.channels[i+1]=field(parts:get_element(i),"_ColorData"):get_size() end
    report.game_method_calls=native.game_method_calls
    report.writes=0
    checkpoint("appearance read complete")
end
return M
