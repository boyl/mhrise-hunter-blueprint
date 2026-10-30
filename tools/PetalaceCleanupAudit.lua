-- 只读扫描器：按请求重载固定模块；禁止动态路径、删除或原生 setter。
local root=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])")).."../diagnostics/PetalaceCleanup/"
local session=tostring(os.time()).."-"..tostring(os.clock())
local last,next_poll,job,report=nil,0,nil,nil
json.dump_file("LoadoutClone/petalace-cleanup-session.json",{session=session,read_only=true})
local function begin(id)
 report={status="reading",writes=0,items={},references={},id=id,session=session}
 job=coroutine.create(function()
  local N=assert(loadfile(root.."native.lua"))()
  local P=assert(loadfile(root.."petalace_cleanup_plan.lua"))()
  local Scan=assert(loadfile(root.."petalace_cleanup_scan.lua"))()
  Scan.run(N,P,report)
 end)
end
begin("startup:"..session)
re.on_application_entry("UpdateBehavior",function()
 if not job and os.clock()>=next_poll then
  next_poll=os.clock()+1
  local request=json.load_file("LoadoutClone/petalace-cleanup-request.json")
  if request and request.session==session and type(request.id)=="string" and request.id~=last and request.operation=="scan" then
   last=request.id;begin(request.id)
  end
 end
 if not job then return end
 local ok,err=coroutine.resume(job)
 if not ok then report.status="error";report.error=tostring(err);job=nil
 elseif coroutine.status(job)=="dead" then job=nil end
 if not job then json.dump_file("LoadoutClone/petalace-cleanup-audit.json",report) end
end)
