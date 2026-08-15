--==============================================================================
-- 注意：以下注释是字段说明文档，请勿简化！(该文件为纯数据配置，需要完整列出可填字段)
-- 自动装备：触发动作配置(纯数据)，新增勋章组只改这里，无需动 helper_autoequip.lua
-- 结构：key=勋章组名(见helper_autoequip_rules.lua)
--      value = {
--        action_ids     = { "CHOP", ... },      -- [可选]无条件动作列表：执行即触发，可不填
--        action_targets = {                     -- [可选]带条件动作：动作 → 目标条件，可不填
--          --排除字段(命中任一即不触发，优先于所有"要求"字段)：
--          动作 = { exclude_tags     = { "a" } },          -- 目标带"任一"指定标签则排除
--          动作 = { exclude_all_tags = { "a" } },          -- 目标带"全部"指定标签才排除
--          动作 = { exclude_prefabs  = { "a" } },          -- 目标为指定预制件则排除
--          --要求字段(组合时须同时满足)：
--          动作 = { tags           = { "tree", "stump" } },  -- 目标带"任一"指定标签即满足
--          动作 = { all_tags       = { "tag" } },            -- 目标必须带"全部"指定标签才满足
--          动作 = { prefabs        = { "prefab" } },         -- 目标为指定预制件才满足
--          动作 = { has_component  = { "stewer" } },         -- 目标带"任一"指定组件才满足(如锅的stewer)
--          动作 = { recipe_builder_tag = { "seasoningchef" } }, -- 制作配方的builder_tag命中才触发(区分勋章专属配方，如BUILD)
--          -- 多个条件字段可组合，组合时同时满足才触发(各自内部按其规则判定)
--        }
--      }
-- 说明：
--   - 一个勋章组可同时有 action_ids(无条件) 和 action_targets(带条件)，也可只有其一
--   - 任一动作执行时，只会从该动作所属的勋章组里挑选最高级勋章装备，不会跨组误装
--==============================================================================
HelperRules_AUTO_EQUIP_ACTIONS = {
	--伐木勋章组
	chopMedal = {
		action_targets = {
			CHOP = { exclude_tags = { "burnt" } },	--砍焦树不触发(能力勋章砍焦树不消耗耐久)
			DIG  = { tags = { "stump" } },			--仅挖树桩(stump标签)才触发
		},
	},
	--矿工勋章组
	minerMedal = {
		action_targets = {
			MINE = { exclude_prefabs = { "rock_avocado_fruit" } },	--排除不消耗耐久的石果
		},
	},
	--厨师勋章组
	chefMedal = {
		action_ids = {
			"COOK",				--烹饪/批量烤制(seasoningchef)。【作弊】红晶锅cook走:Do()未被捕获，整组烹饪需本源+主厨
			"MURDER",			--快速杀生(masterchef)
			"CHEFFLAVOUR",		--调味(seasoningchef，整组需本源勋章)
			"MEDAL_GRINDING",	--研磨(seasoningchef，整组需时空勋章)
			"MEDAL_EAT_SPICES",	--吃调料粉(seasoningchef+本源)
			"MAKECOOLDOWN",		--强制冷却(expertchef)
			"MEDALPOLLUTE",		--污染血糖(seasoningchef)
		},
		action_targets = {
			HARVEST       = { has_component = { "stewer" } },	--从锅收获料理
			RUMMAGE       = { prefabs = { "portablecookpot", "portablespicer" } },	--打开便携烹饪锅/调料站
			OPEN_CRAFTING = { prefabs = { "portableblender" } },	--打开便携搅拌器
			DEPLOY        = { prefabs = { "portablecookpot_item", "portablespicer_item", "portableblender_item" } },	--展开便携设备
			DISMANTLE     = { prefabs = { "portablecookpot", "portablespicer", "portableblender" } },	--收回便携设备
			BUILD         = { recipe_builder_tag = { "masterchef", "professionalchef", "seasoningchef" } },	--制作厨师专属配方
		},
	},
}
