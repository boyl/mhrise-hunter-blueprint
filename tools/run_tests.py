"""运行纯 Lua 测试。需外部安装 lupa，不修改游戏。"""
from pathlib import Path
import argparse
from lupa.lua54 import LuaRuntime

parser = argparse.ArgumentParser()
parser.add_argument('--debug-mode', choices=['normal', 'absent', 'no-traceback'], default='normal')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
for path in sorted((root / "tests").glob("*_spec.lua")):
    # 独立开发诊断器使用 debug.getinfo 定位，不在正式发布包内。
    if args.debug_mode != 'normal' and path.name == 'diagnostic_spec.lua':
        print('SKIP development-only diagnostic_spec.lua in restricted runtime')
        continue
    lua = LuaRuntime(unpack_returned_tuples=True)
    if args.debug_mode == 'absent':
        lua.execute('debug=nil')
    elif args.debug_mode == 'no-traceback':
        lua.execute('debug={}')
    lua.globals().package.path = str(root / "reframework/autorun/?.lua").replace("\\", "/") + ";" + lua.globals().package.path
    lua.execute(path.read_text(encoding="utf-8-sig"), name=str(path))
