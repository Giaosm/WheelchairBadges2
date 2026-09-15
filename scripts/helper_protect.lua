--通用勋章保护机制：特定环境下勋章不可被自动装备移走。
--配置见 helper_autoequip_rules.lua 的 PROTECT_MEDALS，每项 = { env = function(player) return boolean end }
--  env(player) 返回 true 表示玩家处于该勋章的保护环境(此时该勋章不可被移走)
--新增保护勋章只需在配置里加一项并写 env 判定，无需改本文件。
local PROTECT_MEDALS = HelperRules_AUTO_EQUIP.PROTECT_MEDALS

local PROTECT_ENV = {}--勋章prefab→环境判定函数
for prefab, cfg in pairs(PROTECT_MEDALS or {}) do
	PROTECT_ENV[prefab] = cfg and cfg.env
end

--取勋章真实prefab(复制勋章返回印刻对象)：复用 helper_globalfn.lua 的公共实现
local RealPrefab = GLOBAL.GetMedalRealPrefab

--玩家当前受保护的勋章prefab集合；返回 { [prefab]=true, ... }(可为空表)
--包括：环境判定的保护勋章(PROTECT_ENV) + 玩家自定义强制保留勋章(medal_forced_keep，恒保护，由UI通过RPC同步)
local function ComputeProtectedSet(player)
	local set = {}
	if player == nil then return set end
	for prefab, env in pairs(PROTECT_ENV) do
		if env(player) then
			set[prefab] = true
		end
	end
	for _, prefab in ipairs(player.medal_forced_keep or {}) do
		set[prefab] = true--强制保留恒受保护
	end
	return set
end

--玩家勋章槽当前佩戴的、且在受保护集合中的勋章；无则nil。protectedSet由ComputeProtectedSet生成
local function GetEquippedProtectedMedal(player, protectedSet)
	if protectedSet == nil or next(protectedSet) == nil then return nil end
	local eq = GLOBAL.GetMedalSlotItem(player)--勋章槽那件(公共实现，见 helper_globalfn.lua)
	if eq ~= nil then
		local prefab = RealPrefab(eq)
		if prefab ~= nil and protectedSet[prefab] ~= nil then
			return eq
		end
	end
	return nil
end

GLOBAL.ComputeProtectedSet = ComputeProtectedSet
GLOBAL.GetEquippedProtectedMedal = GetEquippedProtectedMedal
