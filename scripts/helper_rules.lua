--勋章规则配置(纯数据)。新增勋章只改这里。
--  tags            = { "标签" }              拥有勋章(未佩戴)时临时赋予的标签
--  conditional_tags= { 条件标记 = { "标签" } } 满足条件才赋(判断逻辑在helper_tags.lua)
--  components      = { "组件" }              拥有勋章(未佩戴)时临时添加的组件
HelperRules_MEDAL_RULES = {
	--大厨勋章(厨师组已完成)
	chef_certificate = {
		group = "chefMedal",
		tags = { "masterchef", "professionalchef", "expertchef" },
	},
	--主厨勋章(厨师组已完成)
	headchef_certificate = {
		group = "chefMedal",
		tags = { "masterchef", "professionalchef", "expertchef", "seasoningchef" },
	},
	--智慧勋章(智慧组已完成)
	wisdom_certificate = {
		group = "wisdomMedal",
		tags = { "bookbuilder", "wisdombuilder" },
		components = { "reader" },
	},
	--时空勋章(速度组已完成)
	space_time_certificate = {
		group = "speedMedal",
		tags = { "spacetime_medal" },
	},
	--本源勋章(已完成)
	origin_certificate = {
		tags = { "has_origin_medal" },
	},
	--丰收勋章(丰收组已完成)
	harvest_certificate = {
		group = "harvestMedal",
		tags = { "medal_fastpicker" },
	},
	--虫木勋章(植物组已完成)
	plant_certificate = {
		group = "plantMedal",
		tags = { "plantkin", "has_plant_medal" },
	},
	--植物勋章(植物组已完成)
	transplant_certificate = {
		group = "plantMedal",
		tags = { "plantkin", "has_plant_medal", "has_transplant_medal" },
	},
	--童心勋章(童真组已完成)
	childishness_certificate = {
		group = "childMedal",
		tags = { "pebblemaker", "slingshot_sharpshooter", "pinetreepioneer", "troublemaker", "has_childishness" },
		components = { "storyteller" },
	},
	--童真勋章(童真组已完成)
	childlike_certificate = {
		group = "childMedal",
		tags = { "pebblemaker", "slingshot_sharpshooter", "pinetreepioneer", "troublemaker", "has_childishness", "senior_childishness" },
		components = { "storyteller" },
	},
	--暗影勋章(暗影组已完成)
	shadowmagic_certificate = {
		group = "shadowmagicMedal",
		tags = { "shadowmagic", "has_shadowmagic_medal" },
		components = { "magician" },
	},
	--垂钓勋章(钓鱼组已完成)
	mediumfishing_certificate = {
		group = "fishingMedal",
		tags = { "fast_kill_fish" },
	},
	--渔翁勋章(钓鱼组已完成)
	largefishing_certificate = {
		group = "fishingMedal",
		tags = { "fast_kill_fish", "has_largefishing_medal" },
	},
	--巧手勋章(巧手组已完成)
	handy_certificate = {
		group = "handyMedal",
		tags = { "handyperson", "has_handy_medal" },
		conditional_tags = {
			no_portableengineer = { "basicengineer" },
		},
	},
	--女武神勋章(未完成)
	valkyrie_certificate = {
		tags = { "valkyrie" },
	},
	--鱼人勋章(未完成)
	merm_certificate = {
		tags = { "merm_builder", --[[ "merm", "playermerm", "stronggrip", "mermfluent" ]] },
	},
	--浴火勋章(未完成)
	bathingfire_certificate = {
		tags = { "has_bathfire_medal", --[[ "pyromaniac", "bernieowner", "expertchef" ]] },
	},
	--蜘蛛勋章(未完成)
	--注意：spiderwhisperer有作弊风险(解锁韦伯蜘蛛配方+蜘蛛不攻击)，待处理
	spider_certificate = {
		tags = { "spiderwhisperer" },
	},
}
