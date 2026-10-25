-- 集中审查：只读准备或明确的故障回滚，不支持保留新增装备。
local M={}
function M.run(request,report,checkpoint)
 assert(not request.commit,"集中审查不允许提交新装备")
 local folder=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])"))
 local D=assert(loadfile(folder.."audit_decorations.lua"))()
 local Reader=assert(loadfile(folder.."audit_reader.lua"))()
 local Native=assert(loadfile(folder.."audit_native.lua"))()
 local env=setmetatable({require=function(name)
  if name=="LoadoutClone.decorations" then return D end
  if name=="LoadoutClone.native" then return Native end
  return require(name)
 end},{__index=_G})
 local Planner=assert(loadfile(folder.."audit_planner.lua","t",env))()
 local Writer=assert(loadfile(folder.."audit_writer.lua","t",env))()
 local reader=Reader.new()
 local members=reader:list_members().members
 assert(#members>0,"大厅没有其他玩家")
 report.cases={};report.writes=0;report.restores=0
 local planner=Planner.new(reader)
 for _,member in ipairs(members) do
  for _,mode in ipairs({{name="base",copy_augments=false,allow_illegal_augments=false},
   {name="normal",copy_augments=true,allow_illegal_augments=false},
   {name="relaxed",copy_augments=true,allow_illegal_augments=true}}) do
   mode.copy_appearance=false
   local row={index=member.index,mode=mode.name};report.cases[#report.cases+1]=row
   checkpoint("audit "..member.index.." "..mode.name)
   local ok,err=xpcall(function()
    local source=planner:prepare(member.key,mode)
    row.weapon_id=source.items[1].candidate.target.WeaponId
    row.actions=source.actions;row.red=source.red;row.blue=source.blue
    local writer=Writer.new(reader)
    if request.rollback then
     local backup=json.load_file("LoadoutClone/development-backup.json")
     assert(backup and backup.backup_verified,"verified backup required")
     writer.fault_on_verify=true
     local result=writer:execute(source);row.transaction=result
     row.writes=writer.write_count;row.restores=writer.restore_count
     report.writes=report.writes+row.writes;report.restores=report.restores+row.restores
     assert(not result.ok and result.code=="failed" and result.error:find("development verification failure",1,true),"unexpected rollback outcome")
     assert(row.writes>0 and row.writes==row.restores,"rollback count mismatch")
    else
     local plan=writer:prepare(source);writer:assert_context(plan)
     row.entries=#plan.entries;assert(writer.write_count==0)
    end
   end,debug.traceback)
   row.ok=ok;row.error=not ok and tostring(err) or nil
   checkpoint("audit case complete")
   if row.transaction and row.transaction.code=="recovery_failed" then error("回滚失败，停止审查") end
   coroutine.yield({phase="audit",done=#report.cases})
  end
 end
end
return M
