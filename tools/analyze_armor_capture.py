"""对只读快照逐件分析合法、预算及无限制等效炼化，不连接游戏。"""
import argparse
import json
from pathlib import Path
from lupa.lua54 import LuaRuntime

p = argparse.ArgumentParser()
p.add_argument("evidence", type=Path)
p.add_argument("--capture", required=True)
p.add_argument("--bases", required=True)
p.add_argument("--output", required=True)
a = p.parse_args()
read = lambda name: json.loads((a.evidence / name).read_text(encoding="utf-8-sig"))
root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().package.path = str(root / "reframework/autorun/?.lua").replace("\\", "/") + ";" + lua.globals().package.path
aug = lua.eval('require("LoadoutClone.augments")')[0]
table = lambda x: lua.table_from(x, recursive=True)
catalog = read("catalog-003.json")["results"][0]["catalog"]
parts = read(a.capture)["snapshot"]["data"]["_armorParam"]
bases = read(a.bases)["bases"]
out = []
for index, (part, base) in enumerate(zip(parts, bases), 1):
    assert part["ArmorId"] == base["_Id"]
    deltas = {k: v for k, v in zip(part["CustomSkillIdList"], part["CustomSkillLvList"]) if k and v}
    vector = {"defense": part["CustomAddDef"], "slots": part["CustomAddSlot"]}
    vector.update({f"resist{i}": v for i, v in enumerate(part["CustomAddReg"], 1)})
    vector.update({f"skill{k}": v for k, v in deltas.items()})
    row = {"part": index, "armor_id": base["_Id"], "budget": base["_CustomCost"], "delta": vector}
    for mode in ("legal", "budget_only", "unrestricted"):
        candidates = aug.armor_candidates(table(catalog), table(base), table(deltas), mode == "unrestricted")
        result = aug.legal_armor(table(catalog), table(base), table(vector), table(deltas)) if mode == "legal" else aug.solve(candidates, table(vector), 7, None if mode == "unrestricted" else base["_CustomCost"])
        if isinstance(result, tuple):
            row[mode] = {"error": result[1]}
        else:
            row[mode] = {"cost": result["cost"], "entries": [dict(v) for v in result["entries"].values()]}
    out.append(row)
(a.evidence / a.output).write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
for row in out:
    print(json.dumps({"part": row["part"], **{mode: row[mode].get("error", f'{len(row[mode].get("entries", []))} rows, cost {row[mode].get("cost")}') for mode in ("legal", "budget_only", "unrestricted")}}, ensure_ascii=False))
