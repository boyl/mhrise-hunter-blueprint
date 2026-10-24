# 运行时证据与未完成项

2026-10-24，Steam build 17920865；本机 REFramework 历史日志 tag v.1.5.6 / commit 654bac566ad2cb645a5ddbf72d0008e8698187b8。以每次实际加载日志和证据报告为准。

## 已验证的只读入口

- `snow.LobbyManager._hunterInfo`：4 个大厅槽位。使用 `_memberIndex`、`_NetworkId` 与 `_HunterUniqueId` 区分成员；不能仅用名字。
- `snow.gui.EquipStatusParamManager._lobbyParam`：与大厅索引对应的详细装备显示数据。
- `ParamPacket._equipStatusParam.switchActionId_MR_1 / switchActionId_MR_2`：样本中两名远端玩家各有 5 项动作 ID，一名远端玩家为空。必须区分未加载与合法空内容。
- `ParamPacket._armorParam`：五件防具，包括等级、炼化技能与增量、孔位等级。
- `ParamPacket._weaponParam`：武器 ID、百龙珠 ID、傀异强化增量和容量。
- 自己的 `EquipDataManager._PlEquipPack` 包含实际 `EquipmentInventoryData` 引用。原生 `PlEquipMySetData` 有 `_IsUsing`、`_BackupDataList`、`_ActionIdListMR_Red/Blue`。

证据：`evidence/metadata-*.json` 与 `evidence/snapshot-001.json`，均为本机输出，包含玩家显示名，仅用于本地开发，不纳入发布包。

## 尚未解决的关键差异

远端显示数据和本地装备库存对象并非同一种数据结构。

- 远端 `WeaponDataParam/ArmorDataParam/PlTalismanParam` 父类是 `System.Object`，不存在遗漏的父类普通珠子 ID 字段。
- 普通珠子目前只看到孔位／珠子等级、图标颜色、技能汇总，没有本地 `_DecoIdList` 对应的逐槽 ID。
- 防具显示数据有 `CustomAddDef`、`CustomAddSlot`、`CustomAddReg`、`CustomSkillIdList/CustomSkillLvList`；未发现库存 `_CustomBuildup` 对应的 `_Id/_ValueIndex/_SkillId` 原始条目。
- 武器显示数据包含增量、容量，尚不能据此认定恢复了原生强化条目与开放状态。
- 不能用“字段存在”证明数据及时更新，也不能用相同名字证明缓存来自同一会话成员。

因此完整复制尚未开放，真实装备／配装写入数为零。下一步核对是否有额外原生同步入口；如需效果等价的确定性重建，必须逐项比对并明确与原样记录的差别，不能静默用猜测补齐。

## 自动测试

纯 Lua 5.4（lupa）测试：19 项通过，涵盖同名选择、成员退出、会话变化、重复请求、回读失败、部分写入后恢复、恢复失败锁定。它们验证逻辑，不能代替游戏内容量、原生写入、重启存档和 UI 验收。
