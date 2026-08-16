--标签同步：拥有勋章(未佩戴)→临时赋标签/组件；佩戴→临时归能力勋章管，我方不误删。
--规则来自 helper_rules.lua，加勋章只改那里。
local MEDAL_RULES = HelperRules_MEDAL_RULES

--条件标签：条件标记→判断函数
local TAG_CONDITIONS = {
	no_portableengineer = function(player) return not player:HasTag("portableengineer") end,
}

--------------------------------内部工具--------------------------------
--物品是否匹配目标勋章(含空白勋章复制品)
local function IsMedalItem(item, prefabname)
	if item == nil then return false end
	if item.prefab == prefabname then return true end
	if item.prefab == "copy_blank_certificate" and item.medalname == prefabname then return true end
	return false
end

--是否佩戴指定勋章(含融合勋章内部)
local function IsMedalEquipped(player, prefabname)
	if player == nil then return false end
	local medal = player.components.inventory and player.components.inventory:GetEquippedItem(EQUIPSLOTS.MEDAL or EQUIPSLOTS.NECK or EQUIPSLOTS.BODY)
	if medal then
		if IsMedalItem(medal, prefabname) then return true end
		if medal:HasTag("multivariate_certificate") and medal.components.container then
			for _, subitem in pairs(medal.components.container.slots) do
				if IsMedalItem(subitem, prefabname) then return true end
			end
		end
	end
	return false
end

--是否拥有指定勋章(复用GetPlayerMedalItems全量扫描)
local function IsMedalOwned(player, prefabname)
	if player == nil then return false end
	for _, item in ipairs(GLOBAL.GetPlayerMedalItems(player)) do
		if IsMedalItem(item, prefabname) then return true end
	end
	return false
end

--------------------------------临时标签管理--------------------------------
local function RefreshPlayerMedalTags(player)
	if player == nil or not player:HasTag("player") then return end
	player.helper_medal_tags = player.helper_medal_tags or {}
	player.helper_medal_components = player.helper_medal_components or {}

	--第一步：统计应赋/应清/佩戴中的标签组件；并检测佩戴/卸下状态变化(覆盖两个方向的漏刷)
	local tag_should, com_should = {}, {}--拥有应赋
	local tag_equipped, com_equipped = {}, {}--佩戴中(能力勋章管)
	local prev_equip = player.helper_medal_equip_state or {}
	player.helper_medal_equip_state = {}
	local equip_changed = false
	for prefab, rule in pairs(MEDAL_RULES) do
		--该勋章所属组被UI关闭时，不赋予临时标签(视为未拥有，已赋的会在第二步清理)
		local group_enabled = true
		if rule.group ~= nil and player.medal_group_enabled ~= nil and player.medal_group_enabled[rule.group] == false then
			group_enabled = false
		end
		local owned = group_enabled and IsMedalOwned(player, prefab)
		local equipped = group_enabled and IsMedalEquipped(player, prefab)
		player.helper_medal_equip_state[prefab] = equipped
		if equipped then
			for _, tag in ipairs(rule.tags or {}) do tag_equipped[tag] = true end
			for _, condtags in pairs(rule.conditional_tags or {}) do
				for _, tag in ipairs(condtags) do tag_equipped[tag] = true end
			end
			for _, com in ipairs(rule.components or {}) do com_equipped[com] = true end
		end
		--带制作效果勋章且佩戴状态有变化(佩戴/卸下)→强制刷新；首次调用不强制
		local has_crafting_effect = (rule.tags and #rule.tags > 0) or (rule.components and #rule.components > 0)
		if has_crafting_effect and prev_equip[prefab] ~= nil and prev_equip[prefab] ~= equipped then
			equip_changed = true
		end
		if owned and not equipped then
			for _, tag in ipairs(rule.tags or {}) do tag_should[tag] = true end
			for cond, condtags in pairs(rule.conditional_tags or {}) do
				local check = TAG_CONDITIONS[cond]
				if check and check(player) then
					for _, tag in ipairs(condtags) do tag_should[tag] = true end
				end
			end
			for _, com in ipairs(rule.components or {}) do com_should[com] = true end
		end
	end

	local changed = equip_changed

	--第二步：同步标签。佩戴中的只清标记不RemoveTag(避免误删能力勋章真标签)
	for tag in pairs(tag_should) do
		local had = player.helper_medal_tags[tag] or false
		if not had then
			if not player:HasTag(tag) then player:AddTag(tag) end
			player.helper_medal_tags[tag] = true
			HelperDebug("赋予临时标签: %s", tag)
			changed = true
		end
	end
	for tag in pairs(player.helper_medal_tags) do
		if not tag_should[tag] and not tag_equipped[tag] then
			player.helper_medal_tags[tag] = nil
			if player:HasTag(tag) then
				player:RemoveTag(tag)
				HelperDebug("移除临时标签: %s", tag)
				changed = true
			end
		end
	end

	--第三步：同步组件(同标签逻辑)
	for com in pairs(com_should) do
		local had = player.helper_medal_components[com] or false
		if not had then
			if player.components[com] == nil then player:AddComponent(com) end
			player.helper_medal_components[com] = true
			HelperDebug("赋予临时组件: %s", com)
			changed = true
		end
	end
	for com in pairs(player.helper_medal_components) do
		if not com_should[com] and not com_equipped[com] then
			player.helper_medal_components[com] = nil
			if player.components[com] ~= nil then
				player:RemoveComponent(com)
				HelperDebug("移除临时组件: %s", com)
				changed = true
			end
		end
	end

	--状态变化时发refreshcrafting，重建卡顿由helper_crafting_patch处理
	if changed then
		player:PushEvent("refreshcrafting")
	end
end

--------------------------------合并刷新(防抖)--------------------------------
--连发一串事件时"下一帧合并"只刷一次
local ListenAllMedalContainers--前置声明
local function QueueMedalRefresh(player)
	if player == nil or player.helper_medal_refresh_pending then return end
	player.helper_medal_refresh_pending = true
	player:DoTaskInTime(0, function()
		player.helper_medal_refresh_pending = false
		if player.components and player.components.inventory then
			ListenAllMedalContainers(player)
			RefreshPlayerMedalTags(player)
		end
	end)
end

--------------------------------勋章容器监听--------------------------------
--给容器(勋章盒/融合勋章等)挂监听(幂等)
local function ListenMedalContainer(player, item)
	if item == nil or item.helper_medal_listened then return end
	if item.components and item.components.container then
		item.helper_medal_listened = true
		local function onc() QueueMedalRefresh(player) end
		item:ListenForEvent("itemget", onc)
		item:ListenForEvent("itemlose", onc)
	end
end

--递归扫描所有容器(含嵌套)挂监听
ListenAllMedalContainers = function(player)
	local inv = player and player.components and player.components.inventory
	if inv == nil then return end
	local scanned = {}
	local function scanContainer(item)
		if item == nil or scanned[item.GUID] then return end
		scanned[item.GUID] = true
		ListenMedalContainer(player, item)
		local c = item.components and item.components.container
		if c and c.slots then
			for _, subitem in pairs(c.slots) do
				scanContainer(subitem)
			end
		end
	end
	for _, item in pairs(inv.itemslots or {}) do scanContainer(item) end
	for _, item in pairs(inv.equipslots or {}) do scanContainer(item) end
end

--------------------------------事件驱动--------------------------------
local function GetChangedItem(data)
	return data and (data.item or data.prev_item)
end

--仅响应勋章相关变化；拿不到物品则兜底刷新
local function IsMedalRelatedChange(data)
	local item = GetChangedItem(data)
	if item == nil then return true end
	return item:HasTag("medal")
end

--勋章槽位判断(装备栏变化只走equip/unequip，不走背包itemslots)
local function IsMedalSlot(eslot)
	return eslot == (EQUIPSLOTS.MEDAL or EQUIPSLOTS.NECK or EQUIPSLOTS.BODY)
end

local function OnPlayerInventoryChanged(player, data)
	if data == nil then return end
	--equip/unequip只处理勋章槽；itemget/itemlose过滤勋章相关
	if data.eslot ~= nil then
		if not IsMedalSlot(data.eslot) then return end
	elseif not IsMedalRelatedChange(data) then
		return
	end
	local changed_item = GetChangedItem(data)
	HelperDebug("触发刷新 | 变化物品=%s", changed_item and changed_item.prefab or "nil")
	QueueMedalRefresh(player)
end

AddPlayerPostInit(function(player)
	player.helper_medal_tags = player.helper_medal_tags or {}
	player:ListenForEvent("itemget", OnPlayerInventoryChanged)
	player:ListenForEvent("itemlose", OnPlayerInventoryChanged)
	player:ListenForEvent("equip", OnPlayerInventoryChanged)
	player:ListenForEvent("unequip", OnPlayerInventoryChanged)
end)

--------------------------------进入世界时初始同步--------------------------------
AddPrefabPostInit("world", function(inst)
	inst:ListenForEvent("ms_playerjoined", function(src, player)
		if player == nil or not player:HasTag("player") then return end
		ListenAllMedalContainers(player)
		RefreshPlayerMedalTags(player)
	end)
end)

--------------------------------暴露到全局--------------------------------
GLOBAL.RefreshPlayerMedalTags = RefreshPlayerMedalTags
