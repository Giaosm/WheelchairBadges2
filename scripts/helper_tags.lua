--标签同步：拥有勋章(未佩戴)→临时赋标签/组件；佩戴(含融合勋章内)→临时归能力勋章管，我方不误删。
--规则来自 helper_rules.lua，后续加勋章只改那里。
local MEDAL_RULES = HelperRules_MEDAL_RULES

--通用条件标签：条件标记→判断函数，满足才赋标签
local TAG_CONDITIONS = {
	no_portableengineer = function(player) return not player:HasTag("portableengineer") end,
}

--------------------------------内部工具--------------------------------
--物品是否匹配目标勋章(含空白勋章复制品：prefab为copy_blank_certificate，medalname记录印刻对象)
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
		if medal:HasTag("multivariate_certificate") and medal.components.container then--融合勋章内部
			for _, subitem in pairs(medal.components.container.slots) do
				if IsMedalItem(subitem, prefabname) then return true end
			end
		end
	end
	return false
end

--是否拥有指定勋章。复用 GetPlayerMedalItems(已含背包+装备槽+手持+容器递归扫描)
local function IsMedalOwned(player, prefabname)
	if player == nil then return false end
	for _, item in ipairs(GLOBAL.GetPlayerMedalItems(player)) do
		if IsMedalItem(item, prefabname) then return true end
	end
	return false
end

--------------------------------临时标签管理--------------------------------
--刷新临时标签：拥有且未佩戴→加；佩戴或不再拥有→清我方标记(佩戴时归能力勋章管，不误删)。
--有增减时推送refreshcrafting刷新制作栏。
local function RefreshPlayerMedalTags(player)
	if player == nil or not player:HasTag("player") then return end
	player.helper_medal_tags = player.helper_medal_tags or {}
	player.helper_medal_components = player.helper_medal_components or {}

	--第一步：统计应赋/应清的标签组件，及因佩戴而存在(能力勋章管)的标签组件
	local tag_should, com_should = {}, {}--拥有勋章应赋
	local tag_equipped, com_equipped = {}, {}--因佩戴而存在(能力勋章管)
	for prefab, rule in pairs(MEDAL_RULES) do
		local owned = IsMedalOwned(player, prefab)
		local equipped = IsMedalEquipped(player, prefab)
		if equipped then
			for _, tag in ipairs(rule.tags or {}) do tag_equipped[tag] = true end
			for _, condtags in pairs(rule.conditional_tags or {}) do--条件标签佩戴时也视为存在
				for _, tag in ipairs(condtags) do tag_equipped[tag] = true end
			end
			for _, com in ipairs(rule.components or {}) do com_equipped[com] = true end
		end
		if owned and not equipped then
			for _, tag in ipairs(rule.tags or {}) do tag_should[tag] = true end
			for cond, condtags in pairs(rule.conditional_tags or {}) do--条件满足才赋
				local check = TAG_CONDITIONS[cond]
				if check and check(player) then
					for _, tag in ipairs(condtags) do tag_should[tag] = true end
				end
			end
			for _, com in ipairs(rule.components or {}) do com_should[com] = true end
		end
	end

	local changed = false

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

	--第三步：同步组件(同上逻辑)
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

	if changed then player:PushEvent("refreshcrafting") end
end

--------------------------------合并刷新(防抖)--------------------------------
--一次装备/移动勋章会连发一串equip/itemget等事件，用"下一帧合并"只刷新一次，避免全量扫描卡顿
local ListenAllMedalContainers--前置声明，下面赋值
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
--给容器(勋章盒/融合勋章等)挂itemget/itemlose监听刷新(幂等)
local function ListenMedalContainer(player, item)
	if item == nil or item.helper_medal_listened then return end
	if item.components and item.components.container then
		item.helper_medal_listened = true
		local function onc() QueueMedalRefresh(player) end
		item:ListenForEvent("itemget", onc)
		item:ListenForEvent("itemlose", onc)
	end
end

--递归扫描，给所有容器(含嵌套)挂监听
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

--仅响应勋章相关物品变化；拿不到物品则兜底刷新
local function IsMedalRelatedChange(data)
	local item = GetChangedItem(data)
	if item == nil then return true end
	return item:HasTag("medal")
end

--勋章槽位判断(MEDAL/NECK/BODY)。装备栏变化只触发equip/unequip，不走背包itemslots，须靠它监听
local function IsMedalSlot(eslot)
	return eslot == (EQUIPSLOTS.MEDAL or EQUIPSLOTS.NECK or EQUIPSLOTS.BODY)
end

local function OnPlayerInventoryChanged(player, data)
	if data == nil then return end
	--equip/unequip(有eslot)：只处理勋章槽；itemget/itemlose(无eslot)：勋章相关过滤
	if data.eslot ~= nil then
		if not IsMedalSlot(data.eslot) then return end
	elseif not IsMedalRelatedChange(data) then
		return
	end
	HelperDebug("触发刷新 | 变化物品=%s", (GetChangedItem(data) and GetChangedItem(data).prefab or "nil"))
	QueueMedalRefresh(player)
end

AddPlayerPostInit(function(player)
	player.helper_medal_tags = player.helper_medal_tags or {}
	--itemget/itemlose：物品进出背包；equip/unequip：勋章槽变化(勋章槽到地上时容器没变，只触发这个)
	player:ListenForEvent("itemget", OnPlayerInventoryChanged)
	player:ListenForEvent("itemlose", OnPlayerInventoryChanged)
	player:ListenForEvent("equip", OnPlayerInventoryChanged)
	player:ListenForEvent("unequip", OnPlayerInventoryChanged)
end)

--------------------------------进入世界时初始同步--------------------------------
AddPrefabPostInit("world", function(inst)
	inst:ListenForEvent("ms_playerjoined", function(src, player)--玩家进入时初始同步一次
		if player == nil or not player:HasTag("player") then return end
		ListenAllMedalContainers(player)
		RefreshPlayerMedalTags(player)
	end)
end)

--------------------------------暴露到全局--------------------------------
GLOBAL.RefreshPlayerMedalTags = RefreshPlayerMedalTags
