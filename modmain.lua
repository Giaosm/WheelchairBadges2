--参考能力勋章：设置mod环境可访问全局(EQUIPSLOTS等)
GLOBAL.setmetatable(env,{__index=function(t,k) return GLOBAL.rawget(GLOBAL,k) end})

if not (GLOBAL.MedalAPI or TUNING.FUNCTIONAL_MEDAL_IS_OPEN) then
	print("[坐着轮椅玩勋章] 警告: 未检测到「能力勋章」Mod，本Mod功能已停用。请先启用能力勋章。")
	return
end

TUNING.HELPER_DEBUG_SWITCH = GetModConfigData("debug_switch")--调试开关

--加载顺序：规则配置先加载，供各逻辑模块读取
modimport("scripts/helper_debug.lua")--调试日志
modimport("scripts/helper_rules.lua")--勋章标签规则
modimport("scripts/helper_globalfn.lua")--勋章扫描
modimport("scripts/helper_tags.lua")--标签同步
modimport("scripts/helper_crafting_patch.lua")--制作栏重建优化(客户端,关闭时轻量/打开时补刷)
modimport("scripts/helper_autoequip_rules.lua")--自动装备规则(勋章组等级)
modimport("scripts/helper_autoequip_actions.lua")--自动装备动作配置
modimport("scripts/helper_autoequip.lua")--自动装备
