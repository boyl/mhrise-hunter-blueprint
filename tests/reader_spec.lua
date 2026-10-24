local Reader=require("LoadoutClone.reader")
local function object(fields)
    return {get_field=function(_,key) return fields[key] end}
end
local function hunter(index,name,network)
    return object({_memberIndex=index,_name=name,_NetworkId=network,_hunterRank=100,_masterRank=50,_hallStatus=6,
        _HunterUniqueId=object({mData1=network,mData2=2,mData3=3,mData4_0=0,mData4_1=1,mData4_2=2,mData4_3=3,mData4_4=4,mData4_5=5,mData4_6=6,mData4_7=7})})
end
local function array(values,size)
    return {get_size=function()return size end,get_element=function(_,i)return values[i]end}
end
local hunters={[0]=hunter(0,"本地",1),[1]=hunter(1,"任务中的大厅成员",2)}
local lobby=object({_myselfIndex=0,_hunterInfo=array(hunters,4),currentAliveLobbyPlayer=array({[0]=true,[1]=false,[2]=false,[3]=false},4)})
sdk={get_managed_singleton=function(name) if name=="snow.LobbyManager" then return lobby end end}
local reader=Reader.new()
local members=reader:list_members().members
assert(#members==1,"大厅成员在任务中也必须显示，不能以同场景存活数组筛掉")
assert(members[1].index==1)
print("PASS 大厅成员在任务中仍然列出")
hunters[1]=nil
assert(#reader:list_members().members==0,"离开的空槽不能保留为玩家")
print("PASS 大厅成员离开后移除")
