--自动补充耐久(服务端)：已装备勋章低于阈值时用背包材料补(MedalAddUse)。阈值存player.medal_autorepair={[prefab]=数值}，0=关。
--普通勋章存百分比(默认20%)；正义勋章存目标索引(见下，默认智能)。
local AUTOREPAIR_MEDALS = {
	treadwater_certificate = true,--踏水
	down_filled_coat_certificate = true,--羽绒
	blue_crystal_certificate = true,--蓝晶
	ommateum_certificate = true,--复眼
	justice_certificate = true,--正义(补正义值)
}
--正义勋章补充目标：索引1起，value对齐能力勋章消耗(consume)；本源勋章减耗×0.4，凋零之蜂防控制固定5不看本源；"智能"按攻击目标动态算
JUSTICE_TARGETS = {
	{ name = "坎普斯",     prefab = "krampus",              value = 5  },
	{ name = "复仇坎普斯", prefab = "medal_naughty_krampus", value = 5  },
	{ name = "克劳斯",     prefab = "klaus",                value = 50 },
	{ name = "蝙蝠",       prefab = "bat",                  value = 1  },
	{ name = "闪电羊",     prefab = "lightninggoat",        value = 5  },
	{ name = "触手",       prefab = "tentacle",             value = 5  },
	{ name = "巨型触手",   prefab = "tentacle_pillar",      value = 5  },
	{ name = "暗夜坎普斯", prefab = "medal_rage_krampus",   value = 50 },
	{ name = "洞穴蠕虫",   prefab = "worm",                 value = 5  },
	{ name = "巨大蠕虫",   prefab = "worm_boss",            value = 20 },
	{ name = "蚁狮",       prefab = "antlion",              value = 50 },
	{ name = "毒菌蟾蜍",   prefab = "toadstool",            value = 50 },
	{ name = "悲惨蟾蜍",   prefab = "toadstool_dark",       value = 50 },
	{ name = "凋零之蜂",   prefab = "medal_beequeen",       value = 5,  no_origin_discount = true },
	{ name = "智能",       smart = true },
}
--prefab→所需正义值映射(智能模式用)，排除凋零之蜂/暗影生物(特殊处理)
JUSTICE_PREFAB_VALUE = {}
for _, t in ipairs(JUSTICE_TARGETS) do
	if t.prefab and not t.smart then JUSTICE_PREFAB_VALUE[t.prefab] = t.value end
end
JUSTICE_SMART_INDEX = #JUSTICE_TARGETS--智能项索引

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

--是否在用(直接佩戴或在已装备融合勋章内；DST物品在容器时owner指向容器物品)
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

--找玩家当前在用的指定prefab勋章(直接佩戴或在已装备融合勋章内)。多个勋章时只看在用的那个，避免补到背包里不需要补的
local function FindInUseMedal(player, prefab)
	if player == nil then return nil end
	local inv = player.components and player.components.inventory
	if inv == nil then return nil end
	local visited = {}
	local found
	local function scan(item, depth)
		if item == nil or depth >= 10 or found ~= nil then return end
		if item.prefab == prefab and IsMedalInUse(player, item) then
			found = item
			return
		end
		local c = item.components and item.components.container
		if c and c.slots then
			if visited[item.GUID] then return end
			visited[item.GUID] = true
			for _, subitem in pairs(c.slots) do
				scan(subitem, depth + 1)
			end
		end
	end
	for _, item in pairs(inv.itemslots or {}) do scan(item, 1) end
	for _, item in pairs(inv.equipslots or {}) do scan(item, 1) end
	local handitem = inv:GetEquippedItem(GLOBAL.EQUIPSLOTS and GLOBAL.EQUIPSLOTS.HANDS or "hands")
	if handitem ~= nil then scan(handitem, 1) end
	return found
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

--智能模式：按攻击目标算所需正义值(对齐能力勋章)。0=无需补充
local function GetNeedJustice(player, target)
	if target == nil or not target:IsValid() then return 0 end
	local has_origin = GLOBAL.HasOriginMedal(player)
	if target.prefab == "medal_beequeen" then return 5 end--凋零之蜂防控制，固定5不看本源
	if target.gift_value ~= nil and target:HasTag("norewardtoiler") then--暗影生物gift_value*5
		local need = target.gift_value * 5
		if has_origin then need = math.ceil(need * 0.4) end
		return need
	end
	local val = JUSTICE_PREFAB_VALUE[target.prefab]--justice_targetlist目标
	if val ~= nil then
		if has_origin then val = math.ceil(val * 0.4) end
		return val
	end
	return 0--普通怪物击杀增加正义值，无需补充
end

--补充当前佩戴的勋章(target可选，智能模式用)
local function TryAutoRepair(player, medal, target)
	if medal == nil then return end
	local current, total = GetMedalDurability(medal)
	if current == nil or total == nil or total <= 0 then return end
	local threshold = (player.medal_autorepair and player.medal_autorepair[medal.prefab])
	if medal.prefab == "justice_certificate" then
		if threshold == nil then threshold = JUSTICE_SMART_INDEX end
		if threshold <= 0 then return end
		local need
		if threshold == JUSTICE_SMART_INDEX then
			need = GetNeedJustice(player, target)
			if need <= 0 then return end
		else
			local t = JUSTICE_TARGETS[threshold]
			if t == nil then return end
			need = t.value
			if not t.no_origin_discount and GLOBAL.HasOriginMedal(player) then
				need = math.ceil(need * 0.4)
			end
		end
		if current >= need then return end
	else
		if threshold == nil then threshold = 20 end
		if threshold <= 0 then return end
		if current / total >= threshold / 100 then return end
	end
	local material, adduse = GetRepairMaterial(player, medal)
	if material ~= nil and adduse ~= nil and adduse > 0 then
		if medal.prefab ~= "justice_certificate" and total - current < adduse then return end--普通勋章缺口<单材料补量则不补
		GLOBAL.MedalAddUse(material, medal, adduse)
	end
end

--反查勋章所在玩家(GetGrandOwner沿owner链向上，含融合勋章)
local function GetOwnerPlayer(inst)
	if inst == nil then return nil end
	local ii = inst.components and inst.components.inventoryitem
	if ii == nil then return nil end
	local owner = ii:GetGrandOwner()
	if owner ~= nil and owner:HasTag("player") then return owner end
	return nil
end

--补耐久公共入口(合法性/冷却判断)，普通勋章由percentusedchange触发，正义勋章由helper_autoequip在ATTACK动作时调用
local function DoAutoRepair(player, medal, target)
	if player == nil or medal == nil or not player:IsValid() or player:HasTag("playerghost") then return end
	if not IsMedalInUse(player, medal) then return end
	local now = GLOBAL.GetTime()
	if player._autorepair_cooldown ~= nil and now < player._autorepair_cooldown then return end
	player._autorepair_cooldown = now + 2--2秒冷却
	TryAutoRepair(player, medal, target)
end
for prefab in pairs(AUTOREPAIR_MEDALS) do
	AddPrefabPostInit(prefab, function(inst)
		if not GLOBAL.TheNet:GetIsServer() or inst._autorepair_hooked then return end
		inst._autorepair_hooked = true
		if inst.prefab ~= "justice_certificate" then
			inst:ListenForEvent("percentusedchange", function(src, data)
				DoAutoRepair(GetOwnerPlayer(inst), inst, data and data.target)
			end)
		end
	end)
end
--正义勋章：攻击前补正义值(复用helper_autoequip的ATTACK时机，避免命中后才补致首次攻击漏掉落)
GLOBAL.TryAutoRepairJustice = function(player, bufferedaction)
	if player == nil or bufferedaction == nil or bufferedaction.action == nil or bufferedaction.action.id ~= "ATTACK" then return end
	DoAutoRepair(player, FindInUseMedal(player, "justice_certificate"), bufferedaction.target)
end

GLOBAL.AUTOREPAIR_MEDALS = AUTOREPAIR_MEDALS
GLOBAL.JUSTICE_TARGETS = JUSTICE_TARGETS
GLOBAL.JUSTICE_PREFAB_VALUE = JUSTICE_PREFAB_VALUE
GLOBAL.JUSTICE_SMART_INDEX = JUSTICE_SMART_INDEX
