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
--          动作 = { props          = { is_oversized = true } }, -- 目标须满足指定属性(如农场作物植株的is_oversized)，值true=须有且为真，false=须无/为假
--          动作 = { hand_tags      = { "deployedfarmplant" } }, -- 手持物品(invobject)带"任一"指定标签即整体通过(与目标条件为"或"关系，常用于DEPLOY种下种子)
--          动作 = { season_fish    = { prefab="season" } },      -- [必要条件]玩家周围献祭范围(BOOK_SACRIFICE_RADIUS)有指定季节鱼(地上实体)且当前季节≠对应季节才可触发(换季献祭需勋章)，未命中则return false(与目标prefabs判断为"与"关系)
--          动作 = { slingshot_ammo = { "ammo" } },               -- [必要条件]手持弹弓当前装的弹药是"任一"指定prefab才触发(如沙刺弹medalslingshotammo_sandspike)
--          动作 = { recipe_builder_tag = { "seasoningchef" } }, -- 制作配方的builder_tag命中才触发(区分勋章专属配方，如BUILD)
--          动作 = { exclude_recipe_props = { "builder_tag" } }, -- 制作配方带指定属性(如builder_tag)则排除(其他勋章专属)
--          动作 = { keep_recipe_builder_tag = { "handyperson" } }, -- 被exclude_recipe_props排除时，builder_tag命中此列表的保留(自己的专属配方)
--          -- 多个条件字段可组合，组合时同时满足才触发(各自内部按其规则判定)
--        }
--      }
-- 说明：
--   - 一个勋章组可同时有 action_ids(无条件) 和 action_targets(带条件)，也可只有其一
--   - 任一动作执行时，只会从该动作所属的勋章组里挑选最高级勋章装备，不会跨组误装
--   - 同一动作要"按勋章分别限制"时，可用"按勋章分组"写法：动作 = { 勋章prefab = 条件表, ... }，
--     命中对应子条件则装组内该枚勋章(如 PICK = { transplant_certificate = {tags={"thorny"}}, plant_certificate = {props={is_oversized=true}} })
--==============================================================================
HelperRules_AUTO_EQUIP_ACTIONS = {
	--伐木勋章组
	chopMedal = {
		name = "伐木勋章",
		action_targets = {
			CHOP = { exclude_tags = { "burnt" } },	--砍焦树不触发(能力勋章砍焦树不消耗耐久)
			DIG  = { tags = { "stump" } },			--仅挖树桩(stump标签)才触发
		},
	},
	--矿工勋章组
	minerMedal = {
		name = "矿工勋章",
		action_targets = {
			MINE = { exclude_prefabs = { "rock_avocado_fruit" } },	--排除不消耗耐久的石果
		},
	},
	--厨师勋章组
	chefMedal = {
		name = "厨师勋章",
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
	--巧手勋章组
	handyMedal = {
		name = "巧手勋章",
		action_ids = {
			"MEDAL_GRINDING",	--研磨(戴巧手勋章缩短动作domediumaction)
		},
		action_targets = {
			BUILD                   = { exclude_recipe_props = { "builder_tag" }, keep_recipe_builder_tag = { "handyperson", "has_handy_medal" } },	--制作所有东西(快速制作)，排除其他勋章专属配方(女工+巧手专属除外)
			UNWRAP                  = { has_component = { "unwrappable" } },	--快速拆包(拆可拆包包裹，has_handy_medal加速)
			UNWRAPGIFTFRUIT         = { prefabs = { "medal_gift_fruit" } },	--拆包果(本源+巧手批量5个)
			UNWRAPOVERSIZEDGIFTFRUIT = { all_tags = { "oversized_veggie", "waxable" } },	--拆巨型包果(本源+巧手专属)
			DEPLOY                  = { prefabs = { "winona_catapult_item", "winona_spotlight_item", "winona_battery_low_item", "winona_battery_high_item" } },	--部署女工专属建筑(投石机/探照灯/发电机)
			--DISMANTLE             = { prefabs = { "winona_catapult", "winona_spotlight", "winona_battery_low", "winona_battery_high" } },	--拆除女工专属建筑(投石机/探照灯/发电机)【暂时不用】
		},
	},
	--丰收勋章组(单枚，medal_fastpicker快采)
	harvestMedal = {
		name = "丰收勋章",
		action_ids = {
			"MEDAL_QUICK_DRY",			--晾肉架一键晾干
			"MEDAL_FASTPICK_MEATRACK",	--晾肉架快采
			"HARVEST",					--快速收获(无条件)
		},
		action_targets = {
			PICK     = { exclude_tags = { "noquickpick" } },	--快速采摘，排除大垃圾堆(不能快采)
			TAKEITEM = { tags = { "inventoryitemholder_take", "takeshelfitem" } },	--持有器/架子有物可取时快采
		},
	},
	--植物勋章组
	plantMedal = {
		name = "植物勋章",
		action_ids = {
			"MEDALTRANSPLANT",			--月光移植
			"MEDALNORMALTRANSPLANT",	--普通移植
			"GIVEROOTCHESTLIFE",		--树根宝箱复苏
			"MAKEMUSHTREE",				--变成蘑菇树(本源勋章可绕过月光限制)
			"MAKEMANDRAKEPLANT",		--复活曼德拉(本源勋章可绕过月光限制)
			"GRAFTING_TREE",			--嫁接
			"PUT_IN_THE_SEEDS",			--塞入种子
			"MEDAL_FRUIT_TREE_LEVEL_UP",--嫁接树升级
			"MEDALMOONTREEHARVEST",		--采摘月树花(需本源勋章+植物勋章)
			"MEDALTREEROCKSHARVEST",	--采摘巨石枝(需本源勋章+植物勋章)
			"PLANTSOIL",				--种田(需plantkin标签)
		},
		action_targets = {
			BUILD   = { recipe_builder_tag = { "has_plant_medal", "has_transplant_medal" } },	--制作植物专属配方(月光权杖/月光锤/月光网/肥料包等)
			DEPLOY  = { hand_tags = { "deployedfarmplant" } },	--种下农场作物种子(手持物带deployedfarmplant标签)
			PICK    = {
				transplant_certificate = { tags = { "thorny" } },	--采带刺植物(thorny标签)戴植物勋章
				plant_certificate = { props = { is_oversized = true }, exclude_tags = { "farm_plant_killjoy" } },	--采巨型作物(is_oversized)戴虫木勋章，排除腐烂作物
			},
			HARVEST = { prefabs = { "waterplant" } },	--收获藤壶(戴植物勋章带plantkin免被海草攻击)
		},
	},

	--智慧勋章组
	wisdomMedal = {
		name = "智慧勋章",
		action_targets = {
			BUILD = { recipe_builder_tag = { "wisdombuilder", "bookbuilder" } },	--制作陷阱重置册(智慧勋章专属配方)或原版书籍(bookbuilder)
			READ   = { tags = { "bookcabinet_item" }, exclude_tags = { "simplebook" }, exclude_prefabs = { "closed_book" } },	--读书(可放入书桌/书架的书，排除普通就能读的烹饪书simplebook和无字天书closed_book)
		},
	},
	--时空勋章组
	speedMedal = {
		name = "时空勋章",
		action_ids = {
			"MEDAL_GRINDING",		--整组研磨(时空勋章+主厨勋章)
			"MEDALFEEDBIRD",		--整组喂鸟(时空勋章+本源)
			"MEDALDELIVERYTREASURE",--快速挖宝(时空勋章+本源)
		},
		action_targets = {
			BUILD = { recipe_builder_tag = { "spacetime_medal" } },	--制作时空专属配方(琥珀灵石/水晶球/改命药水/时空符文/时空尘蛾窝等)
			READ   = { prefabs = { "unsolved_book" }, season_fish = { oceanfish_small_7_inv = "spring", oceanfish_small_8_inv = "summer", oceanfish_small_6_inv = "autumn", oceanfish_medium_8_inv = "winter" } },	--阅读未解之谜书献祭季节鱼换季(时空勋章)
			ATTACK = { slingshot_ammo = { "medalslingshotammo_sandspike" } },	--弹弓装沙刺弹攻击(佩戴时空勋章无视地形生成时空之刃)
		},
	},
	--童真勋章组(占位，动作待补)
	childMedal = {
		name = "童真勋章",
		action_targets = {
			--TODO: 弹弓射击/组装等动作
		},
	},
}