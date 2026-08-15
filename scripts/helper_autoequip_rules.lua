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
		-- "handy_certificate",		--巧手勋章
		-- "wisdom_certificate",	--智慧勋章
		-- "transplant_certificate",--植物勋章
		-- "harvest_certificate",	--丰收勋章
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
		-- "space_time_certificate",--时空勋章
		-- "silence_certificate",	--沉默勋章
		-- "bathingfire_certificate",--浴火勋章
		-- "shadowmagic_certificate",--暗影勋章
		-- "childlike_certificate",	--童真勋章
		-- "merm_certificate",		--鱼人勋章
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
	},
}
