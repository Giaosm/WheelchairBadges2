--获取角色拥有的勋章物品实例：背包+装备槽+手持+身上容器(递归)，不去重。
--判断标准与能力勋章一致：物品带"medal"标签。
local function IsMedal(item)
	return item ~= nil and item:HasTag("medal")
end

--勋章物品实例数组(用于自动装备等需要item的场景)
local function GetPlayerMedalItems(inst)
	local medals = {}
	if inst == nil then return medals end
	local visited = {}
	local function collect(item)
		if item ~= nil and IsMedal(item) then table.insert(medals, item) end
	end
	--递归扫容器(勋章盒等)，防循环
	local function scan(item, depth)
		if item == nil or depth >= 10 then return end
		local c = item.components and item.components.container
		if c and c.slots then
			if visited[item.GUID] then return end
			visited[item.GUID] = true
			for _, subitem in pairs(c.slots) do
				collect(subitem)
				scan(subitem, depth + 1)
			end
		end
	end

	local inv = inst.components.inventory
	if inv == nil then return medals end
	for _, item in pairs(inv.itemslots or {}) do collect(item) scan(item, 1) end
	for _, item in pairs(inv.equipslots or {}) do collect(item) scan(item, 1) end
	local handitem = inv:GetEquippedItem(GLOBAL.EQUIPSLOTS and GLOBAL.EQUIPSLOTS.HANDS or "hands")
	if handitem ~= nil then collect(handitem) scan(handitem, 1) end

	return medals
end

--勋章prefab名数组(不去重，兼容旧接口)
local function GetPlayerMedals(inst)
	local names = {}
	for _, item in ipairs(GetPlayerMedalItems(inst)) do
		table.insert(names, item.prefab)
	end
	return names
end

GLOBAL.GetPlayerMedalItems = GetPlayerMedalItems
GLOBAL.GetPlayerMedals = GetPlayerMedals
