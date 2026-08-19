--攻击拦截(服务端)：针对女武神勋章组，攻击的目标与装备的勋章不匹配(不满足升级条件)时禁止攻击，防止升级失败。
--开关：UI"攻击拦截"(默认关)，读 player.medal_group_enabled["attackBlock"]==true 才开启。
--目标匹配规则与 helper_autoequip_actions.lua 里女武神组 ATTACK 的条件保持一致。
if not GLOBAL.TheNet:GetIsServer() then return end

--是否开启攻击拦截(默认关，需显式true才开)
local function IsAttackBlockEnabled(player)
	local g = player and player.medal_group_enabled
	return g ~= nil and g["attackBlock"] == true
end
GLOBAL.IsAttackBlockEnabled = IsAttackBlockEnabled

--------------------------------女武神组各勋章的目标匹配判定--------------------------------
--检验勋章(valkyrie_examine_certificate)：大型怪物(largecreature+monster) 或 epic
local function ExamineMatch(victim)
	if victim == nil or not victim:IsValid() then return false end
	return victim:HasTags({"largecreature", "monster"}) or victim:HasTag("epic")
end
--考验勋章(valkyrie_test_certificate)：epic 或 monster，且非 smallcreature
local function TestMatch(victim)
	if victim == nil or not victim:IsValid() then return false end
	return victim:HasOneOfTags({"epic", "monster"}) and not victim:HasTag("smallcreature")
end
--女武神勋章(valkyrie_certificate)已满级，攻击不匹配目标不会降级，无需拦截，不在此列

--当前装备/融合内的女武神组勋章→匹配规则(仅检验/考验需拦截，女武神最终级不拦截)
local MEDAL_MATCH = {
	["valkyrie_examine_certificate"] = ExamineMatch,--检验
	["valkyrie_test_certificate"]    = TestMatch,--考验
}

--判定攻击是否应被拦截：开关开启 且 装备了女武神组勋章 且 目标不匹配该勋章 → 返回true(拦截)
--(TODO: 具体拦截逻辑待补充——需读取玩家当前佩戴/融合内女武神组勋章，取对应匹配规则判断，不匹配则阻止ATTACK动作)
local function ShouldBlockAttack(player, target)
	if not IsAttackBlockEnabled(player) then return false end
	if target == nil then return false end
	--TODO: 读取玩家当前装备的女武神组勋章(prefab)，用 MEDAL_MATCH[prefab] 判断 target 是否匹配；不匹配返回true
	--     未装备女武神组勋章时不拦截(无勋章则无升级失败问题)
	return false
end
GLOBAL.ShouldBlockAttack = ShouldBlockAttack

--(TODO: 在此 hook 攻击动作(playercontroller.DoAction / combat:DoAttack)，调用 ShouldBlockAttack 决定是否拦截攻击)
