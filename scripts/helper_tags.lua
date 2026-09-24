--拥有(未佩戴)临时赋标签/组件；佩戴归勋章管不干预；原生已有不登记不误删
local MEDAL_RULES = HelperRules_MEDAL_RULES
local GetRealPrefab = GLOBAL.GetMedalRealPrefab--取真名(复制勋章→印刻对象)，定义见 helper_globalfn.lua
local MEDAL_SLOT = GLOBAL.EQUIPSLOT_MEDAL--勋章槽，定义见 helper_globalfn.lua
local TAG_CONDITIONS = {
	no_portableengineer = function(player) return not player:HasTag("portableengineer") end,
}

local function IsMedalItem(item, prefabname)
	return GetRealPrefab(item) == prefabname
end

--装备槽命中目标勋章的实例(含融合勋章内部，多枚取等级最高)，未佩戴返回nil
local function FindEquippedMedal(player, prefabname)
	local medal = GLOBAL.GetMedalSlotItem(player)
	if medal == nil then return nil end
	if IsMedalItem(medal, prefabname) then return medal end
	if medal:HasTag("multivariate_certificate") and medal.components.container then
		local best
		for _, sub in pairs(medal.components.container.slots) do
			if IsMedalItem(sub, prefabname)
				and (best == nil or (sub.medal_level or 0) > (best.medal_level or 0)) then
				best = sub
			end
		end
		return best
	end
	return nil
end
local function IsMedalEquipped(player, prefabname) return FindEquippedMedal(player, prefabname) ~= nil end
local function GetEquippedMedalLevel(player, prefabname)
	local medal = FindEquippedMedal(player, prefabname)
	return medal ~= nil and (medal.medal_level or 0) or nil
end

--标签是否为佩戴勋章的真来源(剥临时标签前判定：真佩戴一律不干预)
local function IsMedalTagGenuine(player, tag)
	if player == nil or tag == nil then return false end
	for prefab, rule in pairs(MEDAL_RULES) do
		if IsMedalEquipped(player, prefab) then
			for _, t in ipairs(rule.tags or {}) do
				if t == tag then return true end
			end
			for cond, condtags in pairs(rule.conditional_tags or {}) do
				local check = TAG_CONDITIONS[cond]
				if check and check(player) then
					for _, t in ipairs(condtags) do
						if t == tag then return true end
					end
				end
			end
			if rule.level_tag_base ~= nil then
				local num = tag:match("^" .. rule.level_tag_base .. "(%d+)$")
				if num and tonumber(num) <= (GetEquippedMedalLevel(player, prefab) or 0) then
					return true
				end
			end
		end
	end
	return false
end

----------------------------------------临时项同步----------------------------------------
local function RefreshPlayerMedalTags(player)
	if player == nil or not player:HasTag("player") then return end
	player.helper_medal_tags = player.helper_medal_tags or {}
	player.helper_medal_components = player.helper_medal_components or {}

	local tag_should, com_should = {}, {}
	local tag_equipped, com_equipped = {}, {}
	--单次扫描建映射：真prefab→是否持有 / 持有最高等级(复制勋章按印刻对象算)。原来每条规则各扫一次(18~19次)
	local owned_map, owned_max_level = {}, {}
	for _, item in ipairs(GLOBAL.GetPlayerMedalItems(player)) do
		local real = GetRealPrefab(item)
		if real ~= nil then
			owned_map[real] = true
			local lv = item.medal_level or 0
			if lv > (owned_max_level[real] or 0) then owned_max_level[real] = lv end
		end
	end
	--佩戴状态表两张交替复用(不每帧新建)，旧表留作prev_equip比较
	local prev_equip = player.helper_medal_equip_state or {}
	local cur_equip = player.helper_medal_equip_state_spare or {}
	for prefab in pairs(cur_equip) do cur_equip[prefab] = nil end
	player.helper_medal_equip_state = cur_equip
	player.helper_medal_equip_state_spare = prev_equip
	local equip_changed = false

	for prefab, rule in pairs(MEDAL_RULES) do
		local group_enabled = true
		if rule.group ~= nil and player.medal_group_enabled ~= nil and player.medal_group_enabled[rule.group] == false then
			group_enabled = false
		end
		if rule.group == "wisdomMedal" and player.helper_medal_exam_running then
			group_enabled = false--答题防reader消耗翻倍
		end
		if rule.group == "chefMedal" and player.helper_medal_eat_masterchef then
			group_enabled = false--进食时剥厨师组防wisecracker误报
		end
		local owned = group_enabled and owned_map[prefab] == true
		local equipped = group_enabled and IsMedalEquipped(player, prefab)
		cur_equip[prefab] = equipped
		if equipped then
			for _, tag in ipairs(rule.tags or {}) do tag_equipped[tag] = true end
			for _, condtags in pairs(rule.conditional_tags or {}) do
				for _, tag in ipairs(condtags) do tag_equipped[tag] = true end
			end
			for _, com in ipairs(rule.components or {}) do com_equipped[com] = true end
			--等级标签归勋章管，防第三步误删真标签
			if rule.level_tag_base ~= nil then
				local max_level = GetEquippedMedalLevel(player, prefab) or 0
				for i = 1, max_level do tag_equipped[rule.level_tag_base .. i] = true end
			end
		end
		--佩戴状态变化强制刷新
		if ((rule.tags and #rule.tags > 0) or (rule.components and #rule.components > 0) or rule.level_tag_base ~= nil)
			and prev_equip[prefab] ~= nil and prev_equip[prefab] ~= equipped then
			equip_changed = true
		end
		--对齐排除(helper_equip_align.lua)：本次动作缺佩的勋章，整条规则不赋临时项(标签/组件/等级标签)
		local align_exclude = player.helper_medal_align_exclude
		if owned and not equipped and not (align_exclude ~= nil and align_exclude[prefab]) then
			for _, tag in ipairs(rule.tags or {}) do
				tag_should[tag] = true
			end
			for cond, condtags in pairs(rule.conditional_tags or {}) do
				local check = TAG_CONDITIONS[cond]
				if check and check(player) then
					for _, tag in ipairs(condtags) do tag_should[tag] = true end
				end
			end
			for _, com in ipairs(rule.components or {}) do com_should[com] = true end
			--按持有最高等级赋等级标签(等级取自上面的单次扫描)
			if rule.level_tag_base ~= nil then
				local max_level = owned_max_level[prefab] or 0
				for i = 1, max_level do tag_should[rule.level_tag_base .. i] = true end
			end
		end
	end

	local changed = equip_changed
	--标签：应赋则建并记录；不再需要且非佩戴真来源则清
	for tag in pairs(tag_should) do
		if not player:HasTag(tag) then
			GLOBAL.AddMedalTag(player, tag)
			player.helper_medal_tags[tag] = true
			HelperDebug("赋临时标签:%s", tag)
			changed = true
		end
	end
	for tag in pairs(player.helper_medal_tags) do
		if not tag_should[tag] and not tag_equipped[tag] then
			player.helper_medal_tags[tag] = nil
			if player.medal_tag ~= nil and player.medal_tag[tag] ~= nil then--无计数(原生/未登记)不裸删
				GLOBAL.RemoveMedalTag(player, tag)
				HelperDebug("删临时标签:%s", tag)
				changed = true
			end
		end
	end
	--组件：同上
	for com in pairs(com_should) do
		if player.components[com] == nil then
			GLOBAL.AddMedalComponent(player, com)
			player.helper_medal_components[com] = true
			HelperDebug("赋临时组件:%s", com)
			changed = true
		end
	end
	for com in pairs(player.helper_medal_components) do
		if not com_should[com] and not com_equipped[com] then
			player.helper_medal_components[com] = nil
			if player.medal_com ~= nil and player.medal_com[com] ~= nil then--同理防误删原生(如薇克巴顿reader)
				GLOBAL.RemoveMedalComponent(player, com)
				HelperDebug("删临时组件:%s", com)
				changed = true
			end
		end
	end

	--◆先知◆：纯作弊开关，直接管理 infinite_prophecy 标签(无时效性，不走Buff系统)
	--注意：与预言水晶球的真预知Buff共用同一底层标签 infinite_prophecy
	local seer_on = player.medal_group_enabled ~= nil and player.medal_group_enabled["seer"] == true
	local real_prophesy = player.components.debuffable ~= nil
		and player.components.debuffable:HasDebuff("buff_medal_prophesy") == true
	if seer_on then
		if not player:HasTag("infinite_prophecy") then
			player:AddTag("infinite_prophecy"); changed = true
		end
	elseif player:HasTag("infinite_prophecy") and not real_prophesy then
		--先知关闭即摘掉预知标签；但若预言水晶球的真Buff仍生效则保留，避免误杀真Buff的预知效果
		player:RemoveTag("infinite_prophecy"); changed = true
	end

	if changed then
		player:PushEvent("refreshcrafting")
	end
	if TUNING.HELPER_DEBUG_SWITCH then--汇总残留(关调试不做无用拼接)
		local parts = {}
		for tag in pairs(player.helper_medal_tags or {}) do
			local cnt = player.medal_tag and player.medal_tag[tag]
			table.insert(parts, string.format("%s(%s)", tag, cnt == nil and "?" or tostring(cnt)))
		end
		for com in pairs(player.helper_medal_components or {}) do
			local cnt = player.medal_com and player.medal_com[com]
			table.insert(parts, string.format("%s(%s)", com, cnt == nil and "?" or tostring(cnt)))
		end
		HelperDebug("临时项=%s", table.concat(parts, " "))
	end
end

--防抖：同帧连发事件只刷一次
local ListenAllMedalContainers
local function QueueMedalRefresh(player)
	if player == nil or not player:IsValid() or player.helper_medal_refresh_pending then return end
	player.helper_medal_refresh_pending = true
	player:DoTaskInTime(0, function()
		player.helper_medal_refresh_pending = false
		if player.components and player.components.inventory then
			ListenAllMedalContainers(player)
			RefreshPlayerMedalTags(player)
		end
	end)
end

--给容器(勋章盒/融合勋章等)挂监听(幂等)；持有者回调时现读，物品换手后刷的是"当前拿着它的人"
local function ListenMedalContainer(item)
	if item == nil or item.helper_medal_listened or not (item.components and item.components.container) then return end
	item.helper_medal_listened = true
	local function onc()
		local owner = GLOBAL.GetItemPlayerOwner(item)
		if owner ~= nil then QueueMedalRefresh(owner) end
	end
	item:ListenForEvent("itemget", onc)
	item:ListenForEvent("itemlose", onc)
end
--递归扫描容器挂监听
ListenAllMedalContainers = function(player)
	--沿用原行为：不含手持、深度不限(GUID去重已防循环)
	GLOBAL.TraversePlayerItems(player, function(item)
		ListenMedalContainer(item)
	end, { include_hand = false })
end

----------------------------------------事件驱动----------------------------------------
local function GetChangedItem(data)
	return data and (data.item or data.prev_item)
end
local function IsMedalRelatedChange(data)
	local item = GetChangedItem(data)
	if item == nil then return true end
	return item:HasTag("medal") or (item.components and item.components.container)
end
local function OnPlayerInventoryChanged(player, data)
	if data == nil then return end
	if data.eslot ~= nil then--装备事件仅处理勋章槽/容器物品
		if data.eslot ~= MEDAL_SLOT then
			local item = GetChangedItem(data)
			if item == nil or not (item.components and item.components.container) then return end
		end
	elseif not IsMedalRelatedChange(data) then
		return
	end
	QueueMedalRefresh(player)
end

AddPlayerPostInit(function(player)
	if not GLOBAL.TheNet:GetIsServer() then return end--标签由服务端权威下发(net_bool)，客户端本地刷新会用不完整信息(如复制勋章medalname)覆盖网络值
	player:ListenForEvent("itemget", OnPlayerInventoryChanged)
	player:ListenForEvent("itemlose", OnPlayerInventoryChanged)
	player:ListenForEvent("equip", OnPlayerInventoryChanged)
	player:ListenForEvent("unequip", OnPlayerInventoryChanged)
end)
--◆先知◆：预言水晶球的预知Buff到期/被移除时，若先知开启则立刻补回 infinite_prophecy 标签，消除空窗
if GLOBAL.TheNet:GetIsServer() then
	AddComponentPostInit("debuffable", function(self)
		local oldRemoveDebuff = self.RemoveDebuff
		self.RemoveDebuff = function(self, name, ...)
			local r = oldRemoveDebuff and oldRemoveDebuff(self, name, ...) or nil
			if name == "buff_medal_prophesy" and self.inst ~= nil then
				local p = self.inst
				if p.medal_group_enabled ~= nil and p.medal_group_enabled["seer"] == true
					and not p:HasTag("infinite_prophecy") then
					p:AddTag("infinite_prophecy")
					p:PushEvent("refreshcrafting")
				end
			end
			return r
		end
	end)
end
AddPrefabPostInit("world", function(inst)
	inst:ListenForEvent("ms_playerjoined", function(src, player)
		if player == nil or not player:HasTag("player") then return end
		ListenAllMedalContainers(player)
		RefreshPlayerMedalTags(player)
	end)
end)
GLOBAL.RefreshPlayerMedalTags = RefreshPlayerMedalTags
GLOBAL.FindEquippedMedal = FindEquippedMedal--供 helper_equip_align 判断勋章是否真佩戴

----------------------------------------临时标签动作剥离----------------------------------------
--剥临时标签执行fn再恢复；仅mod临时标签且非真佩戴才剥
local function WithTempTag(player, tag, fn, ...)
	if player ~= nil and player.helper_medal_tags ~= nil and player.helper_medal_tags[tag]
		and not IsMedalTagGenuine(player, tag) then
		GLOBAL.RemoveMedalTag(player, tag)
		local results = {}
		local n = GLOBAL.CollectResults(results, pcall(fn, ...))--完整保留被包函数返回值(含尾部 nil)
		GLOBAL.AddMedalTag(player, tag)
		if not results[1] then error(results[2]) end
		return unpack(results, 2, n)
	end
	return fn(...)
end

--吃东西剥临时masterchef(防wisecracker播报only_used_by_warly)
AddComponentPostInit("eater", function(self)
	local oldEat = self.Eat
	if oldEat then
		self.Eat = function(self, food, feeder, ...)
			local inst = self.inst
			if inst ~= nil and not inst.helper_medal_eat_masterchef and GLOBAL.RefreshPlayerMedalTags ~= nil
				and inst.helper_medal_tags ~= nil and inst.helper_medal_tags["masterchef"]
				and not IsMedalTagGenuine(inst, "masterchef") then
				inst.helper_medal_eat_masterchef = true
				GLOBAL.RefreshPlayerMedalTags(inst)
				local result = { oldEat(self, food, feeder, ...) }
				inst.helper_medal_eat_masterchef = nil
				GLOBAL.RefreshPlayerMedalTags(inst)
				return unpack(result)
			end
			return oldEat(self, food, feeder, ...)
		end
	end
end)
--临时plantkin触电不点燃(真佩戴不拦)
AddComponentPostInit("burnable", function(self)
	if self.inst == nil or not self.inst:HasTag("player") then return end
	local oldIgnite = self.Ignite
	self.Ignite = function(self, ...)
		local inst = self.inst
		if inst.helper_medal_tags ~= nil and inst.helper_medal_tags["plantkin"]
			and not IsMedalTagGenuine(inst, "plantkin")
			and inst.sg ~= nil and inst.sg:HasAnyStateTag("electrocute", "electrocute_l") then
			return false
		end
		return oldIgnite(self, ...)
	end
end)
--采花剥临时plantkin：原版flower.lua仅非plantkin才+5san，未真佩戴(临时标签)不该被抑制
AddComponentPostInit("pickable", function(self)
	local inst = self.inst
	if inst == nil or not inst:HasTag("flower") then return end
	local oldPick = self.Pick
	if oldPick == nil then return end
	self.Pick = function(self, picker, ...)
		return WithTempTag(picker, "plantkin", oldPick, self, picker, ...)
	end
end)

--开包果读开包者标签：临时traditionalbearer3剥掉(未真佩戴不享3级免空白)
local function HookGiftFruitGift(prefab, method)
	AddPrefabPostInit(prefab, function(inst)
		local old = inst[method]
		if old then
			inst[method] = function(self, doer, ...)
				return WithTempTag(doer, "traditionalbearer3", old, self, doer, ...)
			end
		end
	end)
end
HookGiftFruitGift("medal_gift_fruit", "GetGift")
HookGiftFruitGift("medal_gift_fruit_oversized", "DropGift")
--遗失包裹实际入口DropLossBundle(DropBundle只是其内部局部函数)
local oldDropLossBundle = GLOBAL.DropLossBundle
if oldDropLossBundle then
	GLOBAL.DropLossBundle = function(target, player, num)
		return WithTempTag(player, "traditionalbearer3", oldDropLossBundle, target, player, num)
	end
	HelperDebug("已Hook遗失包裹掉落")
end
