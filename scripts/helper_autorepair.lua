--自动补充耐久：已装备勋章低于设定阈值时自动用背包材料补(能力勋章MedalAddUse)，仅服务端。
--阈值存 player.medal_autorepair={[prefab]=百分比}，0/nil=关，默认20%。材料从勋章 medal_repair_common 动态取。
local AUTOREPAIR_MEDALS = {
	treadwater_certificate = true,--踏水
	down_filled_coat_certificate = true,--羽绒
	blue_crystal_certificate = true,--蓝晶
	ommateum_certificate = true,--复眼
}

--读取勋章耐久(当前,上限)，兼容armor/finiteuses/fueled
local function GetMedalDurability(medal)
	if medal == nil then return nil, nil end
	local com = medal.components
	if com.armor ~= nil then
		return com.armor.condition, com.armor.maxcondition
	elseif com.finiteuses ~= nil then
		return com.finiteuses:GetUses(), com.finiteuses.total
	elseif com.fueled ~= nil then
		return com.fueled.currentfuel, com.fueled.maxfuel
	end
	return nil, nil
end

--是否已装备
local function IsEquippedSafe(inst)
	if inst == nil then return false end
	local eq = inst.components and inst.components.equippable
	return eq ~= nil and eq:IsEquipped() == true
end

--是否在用(直接佩戴或处于已装备的融合勋章内)。注意DST的inventoryitem无container字段，物品在容器里时owner指向容器物品。
local function IsMedalInUse(player, medal)
	if medal == nil or player == nil then return false end
	if IsEquippedSafe(medal) then
		return true--直接佩戴
	end
	local ii = medal.components and medal.components.inventoryitem
	local owner = ii and ii.owner
	if owner ~= nil and owner ~= player and IsEquippedSafe(owner) then
		return true--在已装备的融合勋章内
	end
	return false
end

--递归找玩家拥有的某prefab物品(物品栏+装备槽+容器+手持)，防循环
local function FindPlayerItem(player, prefab)
	if player == nil then return nil end
	local inv = player.components and player.components.inventory
	if inv == nil then return nil end
	local visited = {}
	local function scan(item, depth)
		if item == nil or depth >= 10 then return nil end
		if item.prefab == prefab then return item end
		local c = item.components and item.components.container
		if c and c.slots then
			if visited[item.GUID] then return nil end
			visited[item.GUID] = true
			for _, subitem in pairs(c.slots) do
				local found = scan(subitem, depth + 1)
				if found ~= nil then return found end
			end
		end
		return nil
	end
	for _, item in pairs(inv.itemslots or {}) do
		local found = scan(item, 1)
		if found ~= nil then return found end
	end
	for _, item in pairs(inv.equipslots or {}) do
		local found = scan(item, 1)
		if found ~= nil then return found end
	end
	local handitem = inv:GetEquippedItem(GLOBAL.EQUIPSLOTS and GLOBAL.EQUIPSLOTS.HANDS or "hands")
	if handitem ~= nil then
		local found = scan(handitem, 1)
		if found ~= nil then return found end
	end
	return nil
end

--动态取材料(玩家拥有的一种)，返回material,adduse
local function GetRepairMaterial(player, medal)
	if medal.medal_repair_common == nil then return nil, nil end
	for mat_prefab, adduse in pairs(medal.medal_repair_common) do
		local material = FindPlayerItem(player, mat_prefab)
		if material ~= nil then
			return material, adduse
		end
	end
	return nil, nil
end

local function TryAutoRepair(player, medal)
	if medal == nil then return end
	local current, total = GetMedalDurability(medal)
	if current == nil or total == nil or total <= 0 then return end
	local threshold = (player.medal_autorepair and player.medal_autorepair[medal.prefab])
	if threshold == nil then threshold = 20 end--默认20%
	if threshold <= 0 then return end--关闭
	if current / total >= threshold / 100 then return end--未低于阈值
	local material, adduse = GetRepairMaterial(player, medal)
	if material ~= nil and adduse ~= nil and adduse > 0 then
		if total - current < adduse then return end--缺口小于单材料补量则不补(不浪费)
		GLOBAL.MedalAddUse(material, medal, adduse)--补充并消耗材料
	end
end

--反查勋章所在玩家(DST原生GetGrandOwner沿owner链向上，含融合勋章场景)
local function GetOwnerPlayer(inst)
	if inst == nil then return nil end
	local ii = inst.components and inst.components.inventoryitem
	if ii == nil then return nil end
	local owner = ii:GetGrandOwner()
	if owner ~= nil and owner:HasTag("player") then return owner end
	return nil
end

--事件驱动：监听percentusedchange(耐久变化)即检查补充，带2秒冷却
for prefab in pairs(AUTOREPAIR_MEDALS) do
	AddPrefabPostInit(prefab, function(inst)
		if not GLOBAL.TheNet:GetIsServer() then return end
		if inst._autorepair_hooked then return end
		inst._autorepair_hooked = true
		inst:ListenForEvent("percentusedchange", function(inst, data)
			local player = GetOwnerPlayer(inst)
			if player == nil or not player:IsValid() or player:HasTag("playerghost") then return end
			if not IsMedalInUse(player, inst) then return end
			local threshold = (player.medal_autorepair and player.medal_autorepair[inst.prefab])
			if threshold == nil then threshold = 20 end--默认20%
			if threshold <= 0 then return end--关闭
			if data == nil or data.percent == nil then return end
			if data.percent >= threshold / 100 then return end--未低于阈值
			local now = GLOBAL.GetTime()
			if player._autorepair_cooldown ~= nil and now < player._autorepair_cooldown then return end
			player._autorepair_cooldown = now + 2--2秒冷却
			TryAutoRepair(player, inst)
		end)
	end)
end

GLOBAL.AUTOREPAIR_MEDALS = AUTOREPAIR_MEDALS
