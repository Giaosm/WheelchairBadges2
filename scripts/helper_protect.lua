--通用勋章保护机制：特定环境下勋章不可被自动装备移走。
--配置见 helper_autoequip_rules.lua 的 PROTECT_MEDALS，每项 = { env = function(player) return boolean end }
--  env(player) 返回 true 表示玩家处于该勋章的保护环境(此时该勋章不可被移走)
--新增保护勋章只需在配置里加一项并写 env 判定，无需改本文件。
local PROTECT_MEDALS = HelperRules_AUTO_EQUIP.PROTECT_MEDALS

local PROTECT_MAP = {}--勋章prefab→是否受保护
local PROTECT_ENV = {}--勋章prefab→环境判定函数
for prefab, cfg in pairs(PROTECT_MEDALS or {}) do
	PROTECT_MAP[prefab] = true
	PROTECT_ENV[prefab] = cfg and cfg.env
end

--取勋章真实prefab(复制勋章返回印刻对象)
local function RealPrefab(medal)
	if medal == nil then return nil end
	return (medal.prefab == "copy_blank_certificate" and medal.medalname) or medal.prefab
end

--某勋章是否登记为受保护勋章(不限当前环境)
local function IsProtectedMedal(medal)
	local prefab = RealPrefab(medal)
	return prefab ~= nil and PROTECT_MAP[prefab] ~= nil
end

--某勋章在当前环境下是否受保护
local function IsMedalProtectedNow(medal, player)
	local prefab = RealPrefab(medal)
	if prefab == nil then return false end
	local env = PROTECT_ENV[prefab]
	return env ~= nil and env(player)
end

--玩家当前处于保护环境的受保护勋章prefab集合；返回 { [prefab]=true, ... }(可为空表)
local function ComputeProtectedSet(player)
	local set = {}
	if player == nil then return set end
	for prefab, env in pairs(PROTECT_ENV) do
		if env(player) then
			set[prefab] = true
		end
	end
	return set
end

--玩家勋章槽当前佩戴的、且在受保护集合中的勋章；无则nil。protectedSet由ComputeProtectedSet生成
local function GetEquippedProtectedMedal(player, protectedSet)
	if protectedSet == nil or next(protectedSet) == nil then return nil end
	local inv = player and player.components and player.components.inventory
	if inv == nil then return nil end
	local eq = inv:GetEquippedItem(GLOBAL.EQUIPSLOTS.MEDAL or GLOBAL.EQUIPSLOTS.NECK or GLOBAL.EQUIPSLOTS.BODY)
	if eq ~= nil then
		local prefab = RealPrefab(eq)
		if prefab ~= nil and protectedSet[prefab] ~= nil then
			return eq
		end
	end
	return nil
end

GLOBAL.IsProtectedMedal = IsProtectedMedal
GLOBAL.IsMedalProtectedNow = IsMedalProtectedNow
GLOBAL.ComputeProtectedSet = ComputeProtectedSet
GLOBAL.GetEquippedProtectedMedal = GetEquippedProtectedMedal
