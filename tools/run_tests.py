"""运行纯 Lua 测试。需外部安装 lupa，不修改游戏。"""
from pathlib import Path
from lupa.lua54 import LuaRuntime

root = Path(__file__).resolve().parents[1]
for path in sorted((root / "tests").glob("*_spec.lua")):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().package.path = str(root / "reframework/autorun/?.lua").replace("\\", "/") + ";" + lua.globals().package.path
    lua.execute(path.read_text(encoding="utf-8-sig"), name=str(path))
