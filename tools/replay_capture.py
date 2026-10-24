"""以真实只读快照对照还原算法；不连接游戏，不修改装备。"""
import argparse
import json
from pathlib import Path
from lupa.lua54 import LuaRuntime

def plain(x):
    if isinstance(x, list):
        return [plain(v) for v in x]
    if not isinstance(x, dict):
        return x
    if 'fields' in x:
        return {k: plain(v) for k, v in x['fields'].items()}
    if 'size' in x:
        return [plain(v) for v in (x.get('values') or [])]
    return {k: plain(v) for k, v in x.items()}

parser = argparse.ArgumentParser()
parser.add_argument('evidence', type=Path)
parser.add_argument('--strict', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
read = lambda name: json.loads((args.evidence / name).read_text(encoding='utf-8-sig'))
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().package.path = str(root / 'reframework/autorun/?.lua').replace('\\', '/') + ';' + lua.globals().package.path
decorations = lua.eval('require("LoadoutClone.decorations")')[0]
augments = lua.eval('require("LoadoutClone.augments")')[0]
table = lambda x: lua.table_from(x, recursive=True)
catalog = read('catalog-003.json')['results'][0]['catalog']
catalog['decorations'] = read('decorations-complete.json')['decorations']
bases = {p['_Id']: p for p in read('armor-bases-contract-003.json')['results'][0]['armors']}
snap = plain(read('snapshot-003.json')['results'][0])
own = snap['own_equipment']['<InventoryDataList>k__BackingField']
weapons = read('weapon-bases-001.json')['results'][0]
weapon_bases = {p['id']: p for p in weapons['weapons']}
results = []
for member_index, packet in enumerate(snap['lobby_packets']):
    if '_equipStatusParam' not in packet:
        continue
    parts = [packet['_weaponParam'], *packet['_armorParam'], packet['_talismanParam']]
    actual = [own[0], *own[1:6], own[7]] if member_index == snap['my_index'] else None
    for index, part in enumerate(parts):
        options = {'max_residual_skills': 2} if index == 6 else {}
        if 1 <= index <= 5:
            base = bases[part['ArmorId']]
            intrinsic = {skill: lv for skill, lv in zip(base['_SkillList'], base['_SkillLvList']) if skill}
            for skill, lv in zip(part['CustomSkillIdList'], part['CustomSkillLvList']):
                if skill:
                    intrinsic[skill] = intrinsic.get(skill, 0) + lv
            assert all(lv >= 0 for lv in intrinsic.values())
            options['base_skills'] = intrinsic
        answer = decorations.resolve(table(part), table(catalog['decorations']), table(options))
        row = {'member_slot': member_index, 'part': index}
        if isinstance(answer, tuple):
            row['decoration_error'] = answer[1]
            results.append(row)
            continue
        row['decorations'] = [answer['ids'][i] for i in range(1, 4)]
        if actual:
            row['matches_inventory'] = row['decorations'] == actual[index]['_DecoIdList']
            assert row['matches_inventory'], row
        if index == 6:
            skills = [{'id': int(k), 'level': int(v)} for k,v in answer['residual_skills'].items()]
            request = {'id': f'talisman-validate-{member_index}', 'mode': 'contract', 'action': 'validate_talisman', 'candidate': {'skills': skills, 'target': part, 'decorations': row['decorations']}}
            (args.evidence / (request['id']+'-request.json')).write_text(json.dumps(request), encoding='utf-8')
        if index == 0:
            result = augments.weapon(table(catalog), table(weapon_bases[part['WeaponId']]), table(part), table(weapons['slot_bonuses']), False)
            assert not isinstance(result, tuple), result
            row['weapon'] = {'entries': [dict(result['entries'][i]) for i in range(1,len(result['entries'])+1)], 'open_ids': list(result['open_ids'].values()), 'cost': result['cost']}
            request = {'id': f'weapon-validate-{member_index}', 'mode': 'contract', 'action': 'validate_weapon', 'candidate': {**row['weapon'], 'target': part, 'decorations': row['decorations']}}
            (args.evidence / (request['id']+'-request.json')).write_text(json.dumps(request), encoding='utf-8')
        if 1 <= index <= 5:
            base = bases[part['ArmorId']]
            skills = {int(k): int(v) for k, v in answer['residual_skills'].items()}
            for skill, lv in zip(base['_SkillList'], base['_SkillLvList']):
                if skill:
                    skills[skill] = skills.get(skill, 0) - lv
            skills = {k: v for k, v in skills.items() if v}
            target = {'defense': part['CustomAddDef'], 'slots': part['CustomAddSlot']}
            target.update({f'resist{i+1}': v for i, v in enumerate(part['CustomAddReg'])})
            target.update({f'skill{k}': v for k, v in skills.items()})
            row['skill_deltas'] = skills
            for illegal in [False, True]:
                candidates = augments.armor_candidates(table(catalog), table(base), table(skills), illegal)
                result = augments.legal_armor(table(catalog), table(base), table(target), table(skills)) if args.strict and not illegal else augments.solve(candidates, table(target), 7, None if illegal else base['_CustomCost'])
                key = 'unrestricted' if illegal else 'budget_checked_candidate'
                if isinstance(result, tuple):
                    row[key] = {'error': result[1]}
                else:
                    row[key] = {'cost': result['cost'], 'entries': [dict(result['entries'][i]) for i in range(1, len(result['entries'])+1)]}
        results.append(row)
output = args.evidence / ('strict-reconstruction-replay.json' if args.strict else 'reconstruction-replay.json')
output.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'Compared {len(results)} parts; own decoration mismatches: 0')
for row in results:
    print(row['member_slot'], row['part'], row.get('decoration_error', row.get('decorations')), {k: v.get('error', f"cost={v['cost']}") if 'cost' in v else v['error'] for k, v in row.items() if k in ('budget_checked_candidate', 'unrestricted')})
