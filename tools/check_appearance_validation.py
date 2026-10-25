"""在无游戏 SDK 的隔离 Lua 中执行验证包入口，检查会话和请求边界。"""
from pathlib import Path
import posixpath
import zipfile
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "dist/HunterBlueprint-Appearance-Validation.zip"
PREFIX = "HunterBlueprint-appearance-diagnostic"


def main():
    with zipfile.ZipFile(PACKAGE) as archive:
        sources = {"/validation/" + n: archive.read(n).decode("utf-8-sig")
                   for n in archive.namelist() if n.endswith(".lua")}
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().source_text = lambda path: sources.get(posixpath.normpath(path.replace("\\", "/")))
    lua.execute('''
local files={}
json={load_file=function(p) return files[p] end,dump_file=function(p,v) files[p]=v end}
sdk_calls=0
sdk={get_managed_singleton=function() sdk_calls=sdk_calls+1;return nil end,
 create_instance=function() error("测试不得创建游戏对象") end}
local now=100
os.clock=function() return now end
local callback
re={on_application_entry=function(name,fn) assert(name=="UpdateBehavior");callback=fn end}
function loadfile(path,mode,env)
 local source=source_text(path)
 if not source then return nil,"missing isolated source: "..path end
 return load(source,"@"..path,mode or "t",env or _G)
end
function require(name)
 if package.loaded[name] then return package.loaded[name] end
 assert(name=="HunterBlueprintAppearance.dispatch","unexpected external module: "..name)
 local path="/validation/reframework/diagnostics/"..name:gsub("%.","/")..".lua"
 local value=assert(loadfile(path))();package.loaded[name]=value;return value
end
function tick() now=now+2;callback() end
function run_entry()
 assert(loadfile("/validation/reframework/autorun/HunterBlueprintAppearanceDiagnostic.lua"))()
end
''')
    lua.execute("run_entry()")
    get = lua.globals().json.load_file
    put = lua.globals().json.dump_file
    session = get(PREFIX + "-session.json")["session_id"]
    assert lua.globals().sdk_calls == 0
    assert list(get(PREFIX + "-request.json").keys()) == []
    print("PASS 独立验证包启动不调用 SDK 且清空旧请求")

    def request(identifier, mode="members", token=session, step="appearance_contract", operation="extended"):
        put(PREFIX + "-request.json", lua.table_from(dict(
            id=identifier, session_id=token, operation=operation, step=step, mode=mode)))
        for _ in range(3):
            lua.globals().tick()
        return get(PREFIX + "-report.json")

    assert request("stale", token="old") is None
    assert lua.globals().sdk_calls == 0
    print("PASS 旧会话请求不执行")
    result = request("invalid-operation", operation="weapon_arrays")
    assert result["status"] == "failed" and lua.globals().sdk_calls == 0
    print("PASS 旧诊断器的其他操作不能绕过外观范围限制")
    result = request("invalid-mode", mode="commit")
    assert result["status"] == "failed" and lua.globals().sdk_calls == 0
    print("PASS 未知或提交模式在游戏调用前拒绝")
    result = request("invalid-step", step="commit_hunter")
    assert result["status"] == "failed" and lua.globals().sdk_calls == 0
    print("PASS 独立验证包拒绝装备提交步骤")
    result = request("members")
    assert result["status"] == "complete" and result["inventory_writes"] == 0
    assert result["ready_for_inventory"] is False and len(result["members"]) == 0
    assert lua.globals().sdk_calls == 1
    print("PASS 无有效大厅时返回空成员列表且不授予写入能力")
    request("members")
    assert lua.globals().sdk_calls == 1
    print("PASS 同一请求只执行一次")
    result = request("missing-target", mode="read")
    assert result["status"] == "failed" and "目标猎人" in result["error"]
    print("PASS 目标缺失不创建临时对象")
    lua.execute("run_entry()")
    assert list(get(PREFIX + "-request.json").keys()) == []
    before = lua.globals().sdk_calls
    lua.globals().tick()
    assert lua.globals().sdk_calls == before
    print("PASS 重载后不重放前次请求")


if __name__ == "__main__":
    main()
