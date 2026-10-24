"""使用独立 Lua 5.4 运行时检查语法；不执行游戏回调。"""
from pathlib import Path
from lupa.lua54 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval('function(s,n) local f,e=load(s,n,"t"); return f~=nil,e end')
paths = sorted((root / "reframework").rglob("*.lua")) + sorted((root / "tests").rglob("*.lua")) + sorted((root / "tools").rglob("*.lua"))
for path in paths:
    ok, error = compile_lua(path.read_text(encoding="utf-8-sig"), str(path))
    if not ok:
        raise SystemExit(error)
print(f"PASS: {len(paths)} Lua files compile (Lua 5.4; not in-game verification)")
