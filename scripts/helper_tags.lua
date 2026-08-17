--标签同步：拥有(未佩戴)→临时赋；佩戴→归能力勋章管，不误删。规则见helper_rules.lua
local MEDAL_RULES = HelperRules_MEDAL_RULES

--条件标签：条件标记→判断函数
local TAG_CONDITIONS = {
	no_portableengineer = function(player) return not player:HasTag("portableengineer") end,
}

--匹配目标勋章(含空白勋章复制品)
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

	--第一步：统计应赋/应清/佩戴中的项，并检测佩戴状态变化
	local tag_should, com_should = {}, {}--拥有应赋
	local tag_equipped, com_equipped = {}, {}--佩戴中(能力勋章管)
	local prev_equip = player.helper_medal_equip_state or {}
	player.helper_medal_equip_state = {}
	local equip_changed = false
	for prefab, rule in pairs(MEDAL_RULES) do
		--UI关闭或答题进行中(智慧组)→视为未拥有
		local group_enabled = true
		if rule.group ~= nil and player.medal_group_enabled ~= nil and player.medal_group_enabled[rule.group] == false then
			group_enabled = false
		end
		if rule.group == "wisdomMedal" and player.helper_medal_exam_running then
			group_enabled = false--答题防reader消耗翻倍，不碰客户端权威开关值
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
		--带效果且佩戴状态变化→强制刷新(首次不强制)
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

	--第二步：同步标签。只在mod新建时记录管理；标签已存在(原生/能力勋章)不干预不记录，避免误删原生
	for tag in pairs(tag_should) do
		if not player:HasTag(tag) then
			GLOBAL.AddMedalTag(player, tag)
			player.helper_medal_tags[tag] = true
			HelperDebug("赋予临时标签: %s", tag)
			changed = true
		end
	end
	for tag in pairs(player.helper_medal_tags) do
		if not tag_should[tag] and not tag_equipped[tag] then
			player.helper_medal_tags[tag] = nil
			--仅在有计数时按计数减；无计数(可能是原生标签/未被mod登记)绝不裸删
			if player.medal_tag ~= nil and player.medal_tag[tag] ~= nil then
				GLOBAL.RemoveMedalTag(player, tag)
				HelperDebug("移除临时标签: %s", tag)
				changed = true
			end
		end
	end

	--第三步：同步组件。只在mod新建时记录管理；组件已存在(原生/能力勋章)不干预不记录，避免误删原生
	for com in pairs(com_should) do
		if player.components[com] == nil then
			GLOBAL.AddMedalComponent(player, com)
			player.helper_medal_components[com] = true
			HelperDebug("赋予临时组件: %s", com)
			changed = true
		end
	end
	for com in pairs(player.helper_medal_components) do
		if not com_should[com] and not com_equipped[com] then
			player.helper_medal_components[com] = nil
			--仅在有计数时按计数减；无计数(可能是原生组件/未被mod登记)绝不RemoveComponent，避免误删原生(如薇克巴顿reader)
			if player.medal_com ~= nil and player.medal_com[com] ~= nil then
				GLOBAL.RemoveMedalComponent(player, com)
				HelperDebug("移除临时组件: %s", com)
				changed = true
			end
		end
	end

	if changed then
		player:PushEvent("refreshcrafting")
	end

	--汇总日志：核对最终状态与计数残留
	if HelperDebug then
		local parts = {}
		for tag in pairs(player.helper_medal_tags or {}) do
			local cnt = player.medal_tag and player.medal_tag[tag]
			table.insert(parts, string.format("%s(计数%s)", tag, cnt == nil and "?" or tostring(cnt)))
		end
		for com in pairs(player.helper_medal_components or {}) do
			local cnt = player.medal_com and player.medal_com[com]
			table.insert(parts, string.format("%s(计数%s)", com, cnt == nil and "?" or tostring(cnt)))
		end
		HelperDebug("最终临时项=%s", table.concat(parts, " "))
	end
end

--合并刷新(防抖)：连发事件时下一帧只刷一次
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
	--勋章 或 带容器的物品(可能装着勋章，如背包/箱子)都算相关
	return item:HasTag("medal") or (item.components and item.components.container)
end

--勋章槽(装备栏只走equip/unequip)
local function IsMedalSlot(eslot)
	return eslot == (EQUIPSLOTS.MEDAL or EQUIPSLOTS.NECK or EQUIPSLOTS.BODY)
end

local function OnPlayerInventoryChanged(player, data)
	if data == nil then return end
	if data.eslot ~= nil then--equip/unequip只处理勋章槽或容器物品
		if not IsMedalSlot(data.eslot) then
			local item = GetChangedItem(data)
			if item == nil or not (item.components and item.components.container) then return end
		end
	elseif not IsMedalRelatedChange(data) then--itemget/itemlose过滤勋章/容器相关
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

--进世界时初始同步
AddPrefabPostInit("world", function(inst)
	inst:ListenForEvent("ms_playerjoined", function(src, player)
		if player == nil or not player:HasTag("player") then return end
		ListenAllMedalContainers(player)
		RefreshPlayerMedalTags(player)
	end)
end)

GLOBAL.RefreshPlayerMedalTags = RefreshPlayerMedalTags
