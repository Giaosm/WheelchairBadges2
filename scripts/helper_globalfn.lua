--获取角色拥有的勋章物品实例：背包+装备槽+手持+身上容器(递归)。
--判断标准与能力勋章一致：物品带"medal"标签。
local function IsMedal(item)
	return item ~= nil and item:HasTag("medal")
end

--勋章槽(各版本槽位名可能不同：MEDAL/NECK/BODY)，单一定义处，其余模块统一引用
GLOBAL.EQUIPSLOT_MEDAL = GLOBAL.EQUIPSLOTS
	and (GLOBAL.EQUIPSLOTS.MEDAL or GLOBAL.EQUIPSLOTS.NECK or GLOBAL.EQUIPSLOTS.BODY) or nil

--通用遍历：背包+装备槽(+手持)及其身上容器(递归，GUID去重防循环)。visit(item, depth)返回true即提前结束。
--opts.max_depth  深度上限(默认不限)；opts.include_hand 是否含手持(默认含)。
--各调用方的历史差异(深度上限/是否含手持)用opts保留，避免统一后改变行为。
local function TraversePlayerItems(player, visit, opts)
	local inv = player and player.components and player.components.inventory
	if inv == nil then return end
	local include_hand = opts == nil or opts.include_hand ~= false
	local max_depth = opts ~= nil and opts.max_depth or nil
	local visited = {}
	local function scan(item, depth)
		if item == nil or visited[item.GUID] then return false end
		visited[item.GUID] = true
		if visit(item, depth) then return true end
		if max_depth ~= nil and depth >= max_depth then return false end
		local c = item.components and item.components.container
		if c and c.slots then
			for _, sub in pairs(c.slots) do
				if scan(sub, depth + 1) then return true end
			end
		end
		return false
	end
	for _, item in pairs(inv.itemslots or {}) do
		if scan(item, 1) then return end
	end
	for _, item in pairs(inv.equipslots or {}) do
		if scan(item, 1) then return end
	end
	if include_hand then
		local handitem = inv:GetEquippedItem(GLOBAL.EQUIPSLOTS and GLOBAL.EQUIPSLOTS.HANDS or "hands")
		if handitem ~= nil then scan(handitem, 1) end
	end
end

--勋章物品实例数组(用于自动装备等需要item的场景)
local function GetPlayerMedalItems(inst)
	local medals = {}
	TraversePlayerItems(inst, function(item)
		if IsMedal(item) then table.insert(medals, item) end
	end, { max_depth = 10 })
	return medals
end

--物品的真实prefab：复制勋章返回其印刻对象(未印刻则返回 copy_blank_certificate 自身)
local function GetMedalRealPrefab(item)
	if item == nil then return nil end
	return (item.prefab == "copy_blank_certificate" and item.medalname) or item.prefab
end

--玩家勋章槽当前佩戴的那一件(可能是融合勋章本身)，无则nil
local function GetMedalSlotItem(player)
	local inv = player and player.components and player.components.inventory
	if inv == nil or GLOBAL.EQUIPSLOT_MEDAL == nil then return nil end
	return inv:GetEquippedItem(GLOBAL.EQUIPSLOT_MEDAL)
end

--物品最终归属的玩家(GetGrandOwner 沿 owner 链向上取最外层持有者，含融合勋章等嵌套容器)；不在玩家身上返回nil
local function GetItemPlayerOwner(item)
	--注意 or nil：item 为 nil 时 "and 链"求值结果是 false，会绕过下面的 == nil 判断
	local ii = item ~= nil and item.components and item.components.inventoryitem or nil
	if ii == nil then return nil end
	local owner = ii:GetGrandOwner()
	if owner ~= nil and owner:HasTag("player") then return owner end
	return nil
end

--把 vararg 收进 results 表(保留中间/尾部 nil)并返回"实际个数"；
--配合 unpack(results, 2, n) 可完整回传被 pcall 包住的函数返回值(直接用 {pcall(...)} + unpack(t,2) 会丢尾部 nil)
local function CollectResults(results, ...)
	local n = select("#", ...)
	for i = 1, n do results[i] = select(i, ...) end
	return n
end

--取官方勋章调参：裸 TUNING_MEDAL 不保证存在；嵌套项仍直接读 MedalAPI.TUNING_MEDAL
local function GetMedalTuning(name, default)
	local tuning = GLOBAL.MedalAPI and GLOBAL.MedalAPI.TUNING_MEDAL
	local value = tuning ~= nil and tuning[name] or nil
	return value ~= nil and value or default
end

GLOBAL.GetPlayerMedalItems = GetPlayerMedalItems
GLOBAL.GetMedalTuning = GetMedalTuning
GLOBAL.TraversePlayerItems = TraversePlayerItems
GLOBAL.GetMedalRealPrefab = GetMedalRealPrefab
GLOBAL.GetMedalSlotItem = GetMedalSlotItem
GLOBAL.GetItemPlayerOwner = GetItemPlayerOwner
GLOBAL.CollectResults = CollectResults
