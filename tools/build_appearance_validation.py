"""生成独立、仅用于原生契约检查的验证包；不安装、不发布、不包含装备写入器。"""
from pathlib import Path
import hashlib
import json
import zipfile
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "reframework/autorun/LoadoutClone"
PREFIX = "reframework/diagnostics/HunterBlueprintAppearance/"


def build():
    runner = (ROOT / "tools/LoadoutCloneDiagnostic.lua").read_text(encoding="utf-8-sig")
    # 使用已验证的分帧诊断器，但隔离会话文件与模块名，避免覆盖现有诊断入口。
    assert runner.count('local prefix="LoadoutClone-diagnostic"') == 1
    assert runner.count('LoadoutClone.diagnostic_steps') == 2
    runner = runner.replace('local prefix="LoadoutClone-diagnostic"', 'local prefix="HunterBlueprint-appearance-diagnostic"')
    runner = runner.replace("LoadoutClone.diagnostic_steps", "HunterBlueprintAppearance.dispatch")
    assert runner.count("local function run(request)") == 1
    runner = runner.replace("local function run(request)",
                            'local function run(request)\n    assert(request.operation=="extended","此验证包仅允许外观扩展检查")')
    dispatch = '''local M={}
function M.run(request,report,checkpoint)
 assert(request.step=="appearance_contract","此验证包只允许外观契约检查")
 local folder=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\\\])"))
 return assert(loadfile(folder.."appearance_contract.lua"))().run(request,report,checkpoint)
end
return M
'''
    payload = {
        "reframework/autorun/HunterBlueprintAppearanceDiagnostic.lua": runner.encode("utf-8"),
        PREFIX + "dispatch.lua": dispatch.encode("utf-8"),
        PREFIX + "appearance_contract.lua": (ROOT / "tools/appearance_contract.lua").read_bytes(),
    }
    for name in ("native", "reader", "appearance", "appearance_reader", "appearance_color", "appearance_objects"):
        payload[PREFIX + name + ".lua"] = (MODULE / (name + ".lua")).read_bytes()
    payload["验证说明.txt"] = """猎人蓝图：外观契约开发验证包（不是功能更新包）
仅在实机验收阶段安装，本次离线开发不安装。与正式 1.0.1 共存。
不包含 Writer、Planner 或正式面板，不会开放外观复制。

将 reframework 合并到游戏目录。ScriptRunner 重载一次后，读取：
reframework/data/HunterBlueprint-appearance-diagnostic-session.json
向同目录 HunterBlueprint-appearance-diagnostic-request.json 写入当前会话请求。
请求需包含独立 id、session_id、operation=extended、step=appearance_contract、
mode=members、read、detached_colors 或 detached_set。旧会话请求不会执行。
先运行 members 获取当前成员 key，再用该 key 运行 read，核对 ID 与颜色；
通过后运行 detached_colors，检查临时对象标志语义。每次请求必须使用不同 id。
报告为 HunterBlueprint-appearance-diagnostic-report.json；遇错不自动重试。
detached_set 验证幻化 ID、染色及原生副本独立性。
detached_colors 与 detached_set 只修改新建的临时对象，不向玩家、装备箱或组合写入。
ready_for_inventory 始终为 false：通过此脚本不等于真实外观写入已验收。
字段、方法或颜色不符合预期时保留报告，禁止跳过检查后直接复制。

移除本包列出的 autorun 脚本及 HunterBlueprintAppearance 诊断子目录即可卸载。
不要删除正式 LoadoutClone.lua、LoadoutClone 目录或其他 Mod。
""".encode("utf-8")
    assert not any("/LoadoutClone/" in name or name.endswith("writer.lua") for name in payload)
    manifest = {"kind": "appearance-contract-development-only", "inventory_write_enabled": False,
                "sha256": {p: hashlib.sha256(v).hexdigest() for p, v in payload.items()}}
    payload["manifest.json"] = json.dumps(manifest, ensure_ascii=False, indent=2).encode("utf-8")
    compiler = LuaRuntime().eval('function(s,n) local f,e=load(s,n,"t"); return f~=nil,e end')
    for name, content in payload.items():
        if name.endswith(".lua"):
            ok, error = compiler(content.decode("utf-8-sig"), name)
            assert ok, error
    out = ROOT / "dist/HunterBlueprint-Appearance-Validation.zip"
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, content in sorted(payload.items()):
            item = zipfile.ZipInfo(name, (2026, 10, 24, 0, 0, 0))
            item.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(item, content)
    with zipfile.ZipFile(out) as archive:
        assert archive.testzip() is None and set(archive.namelist()) == set(payload)
        for name, content in payload.items():
            assert archive.read(name) == content
    print(json.dumps({"path": str(out), "files": len(payload),
                      "sha256": hashlib.sha256(out.read_bytes()).hexdigest()}, indent=2))


if __name__ == "__main__":
    build()
