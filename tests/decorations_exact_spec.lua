local D=require('LoadoutClone.decorations')
local part={DecoLvType={1,0,0},SlotIconColor={1,0,0},SkillIdList={5},SkillLv={1},ExactDecoIds={11,0,0}}
local catalog={{id=10,level=1,color=1,skills={5},levels={1}},{id=11,level=1,color=1,skills={5},levels={1}}}
local result=D.resolve(part,catalog,{base_skills={}});assert(result and result.ids[1]==11)
part.ExactDecoIds={12,0,0};assert(not D.resolve(part,catalog,{base_skills={}}))
part.ExactDecoIds={11,11,0};assert(not D.resolve(part,catalog,{base_skills={}}))
part.ExactDecoIds=nil;local _,reason=D.resolve(part,catalog,{base_skills={}});assert(reason=='ambiguous_decoration')
print('PASS 本机原始珠子 ID 消歧、无效 ID 与空槽冲突拒绝、大厅反推规则保留')
