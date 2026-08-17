--自动装备规则配置(纯数据)。新增勋章组只改这里。
--  FusionMedals      = { {prefab, level}, ... }   融合勋章等级(level越大越高级)
--  ORIGIN_MEDAL_BONUS= { prefab, ... }            本源可加成勋章：自动装备时强制优先用本源勋章当容器
--  Groups            = { 组名 = {prefab从高到低} } 勋章组(组名与能力勋章grouptag一致)
--复制勋章(copy_blank_certificate)通过medalname识别印刻对象；自动装备时真勋章优先于同级复制勋章
HelperRules_AUTO_EQUIP = {
	--融合勋章等级
	FusionMedals = {
		{ prefab = "multivariate_certificate",        level = 1, },--初级融合勋章(3格)
		{ prefab = "medium_multivariate_certificate", level = 2, },--中级融合勋章(4格)
		{ prefab = "large_multivariate_certificate",  level = 3, },--高级融合勋章(6格)
		{ prefab = "origin_certificate",              level = 4, },--本源勋章(9格)
	},

	--本源勋章可加成的勋章列表(参考轮椅勋章助手)
	--暂时只保留我们当前支持的勋章，其余注释；后续支持哪个组再放开对应勋章
	ORIGIN_MEDAL_BONUS = {
		"largechop_certificate",	--伐木勋章(高级，支持本源加成)
		"largeminer_certificate",	--高级矿工勋章
		"headchef_certificate",		--主厨勋章
		"handy_certificate",		--巧手勋章
		"harvest_certificate",		--丰收勋章
		"wisdom_certificate",		--智慧勋章
		"transplant_certificate",	--植物勋章
		-- "justice_certificate",	--正义勋章
		-- "valkyrie_certificate",	--女武神勋章
		-- "naughty_certificate",	--淘气勋章
		-- "down_filled_coat_certificate",--羽绒服勋章
		-- "blue_crystal_certificate",--蓝晶勋章
		-- "ommateum_certificate",	--复眼勋章
		-- "treadwater_certificate",--踏水勋章
		-- "tentacle_certificate",	--触手勋章
		-- "large_devour_soul_certificate",--高级噬魂勋章
		-- "bee_king_certificate",	--蜂王勋章
		-- "largefishing_certificate",--渔翁勋章(高级)
		"space_time_certificate",	--时空勋章
		-- "silence_certificate",	--沉默勋章
		-- "bathingfire_certificate",--浴火勋章
		-- "shadowmagic_certificate",--暗影勋章
		"childlike_certificate",	--童真勋章
		-- "merm_certificate",		--鱼人勋章
	},

	--跨组优先级(数字越大越优先)。以动作名为key，该动作被多组命中且无融合勋章时，只装备优先级最高的那个。
	--未配置的动作=不需要跨组对比，保持逐组装备逻辑。
	CROSS_GROUP_PRIORITY = {
		HARVEST = {
			["transplant_certificate"] = 40,	--植物勋章(采取藤壶)
			["plant_certificate"]      = 40,	--虫木勋章(采取藤壶)
			["cook_certificate"]     = 30,	--烹饪(收料理升级)
			["chef_certificate"]     = 30,	--大厨(收料理升级)
			["harvest_certificate"]  = 20,	--丰收(快收料理)
			["headchef_certificate"] = 10,	--主厨(收料理兜底)
		},
		PICK = {
			["transplant_certificate"] = 20,	--植物勋章(采摘带刺植物)
			["plant_certificate"]      = 20,	--虫木勋章(收巨大农作物升级)
			["harvest_certificate"]    = 10,	--丰收勋章(快采兜底)
		},
		MEDAL_GRINDING = {
			["headchef_certificate"]   = 30,	--主厨(提供seasoningchef，真正研磨)
			["space_time_certificate"] = 20,	--时空(整组研磨)
			["handy_certificate"]      = 10,	--巧手(加速研磨)
		},
		READ = {
			["wisdom_certificate"]     = 20,	--智慧勋章(阅读能力)
			["space_time_certificate"] = 10,	--时空勋章(变更季节)
		},
	},

	--水上保护勋章：玩家在水面(不在船上)时，自动装备不得把这些勋章从可提供水上行走的位置移走，防止掉水淹死
	WATER_SAFE_MEDALS = {
		"treadwater_certificate",	--踏水勋章
	},

	--勋章组(组名与能力勋章勋章上的grouptag一致)
	Groups = {
		--伐木勋章组
		chopMedal = {
			"largechop_certificate",	--高级(最终)
			"mediumchop_certificate",	--中级
			"smallchop_certificate",	--初级
		},
		--矿工勋章组
		minerMedal = {
			"largeminer_certificate",	--高级(最终)
			"mediumminer_certificate",	--中级
			"smallminer_certificate",	--初级
		},
		--厨师勋章组
		chefMedal = {
			"headchef_certificate",		--主厨(最终)
			"chef_certificate",			--大厨
			"cook_certificate",			--烹饪
		},
		--巧手勋章组(无显式grouptag，考验→巧手为完整升级链)
		handyMedal = {
			"handy_certificate",		--巧手(最终)
			"handy_test_certificate",	--巧手考验(前置)
		},
		--丰收勋章(单枚，无grouptag，视为单勋章组)
		harvestMedal = {
			"harvest_certificate",		--丰收(最终)
		},
		--植物勋章组
		plantMedal = {
			"transplant_certificate",	--植物(最终)
			"plant_certificate",		--虫木(前置)
		},
		--智慧勋章组(只含智慧勋章，蒙昧勋章单独处理不自动装备)
		wisdomMedal = {
			"wisdom_certificate",		--智慧(最终)
		},
		--速度/空间/时空勋章组
		speedMedal = {
			"space_time_certificate",	--时空(最终)
			"space_certificate",		--空间
			"speed_certificate",		--速度
		},
		--童真勋章组
		childMedal = {
			"childlike_certificate",	--童真(最终)
			"childishness_certificate",	--童心(前置)
		},
	},
}
