--攻击拦截：针对女武神勋章组(检验/考验)，攻击目标与佩戴勋章不匹配(不满足升级条件)时，在客户端禁止攻击指令，防止升级失败。
--客户端读勋章不可靠，故佩戴的检验/考验勋章由服务端(helper_tags.lua)加标签同步(medal_block_examine/medal_block_test)，客户端 HasTag 可靠读取。
--目标匹配规则与 helper_autoequip_actions.lua 里女武神组 ATTACK 的条件一致。
local GLOBAL = GLOBAL
local _rawget = rawget--strict下访问动态全局字段会报"未声明"，用rawget安全读取

--------------------------------目标匹配规则(客户端/服务端通用)--------------------------------
--检验勋章：大型怪物(largecreature+monster) 或 epic
local function ExamineMatch(victim)
	if victim == nil or not victim:IsValid() then return false end
	return victim:HasTags({ "largecreature", "monster" }) or victim:HasTag("epic")
end
--考验勋章：epic 或 monster，且非 smallcreature
local function TestMatch(victim)
	if victim == nil or not victim:IsValid() then return false end
	return victim:HasOneOfTags({ "epic", "monster" }) and not victim:HasTag("smallcreature")
end
--女武神勋章(最终级)已满级，攻击不匹配目标不会降级，不拦截

--佩戴标签→匹配规则(客户端通过玩家HasTag判断佩戴了哪个勋章)
local BLOCK_MATCH = {
	["medal_block_examine"] = ExamineMatch,--检验
	["medal_block_test"]    = TestMatch,--考验
}

--客户端：是否应拦截对 target 的攻击。仅"拦截"模式(attackBlock=="block")且佩戴检验/考验勋章且目标不匹配该勋章 → true(拦截)；"脱落"模式放行
local function ShouldBlockAttackClient(player, target)
	if player == nil or target == nil then return false end
	--开关：UI"攻击拦截"(三态：false关/"block"拦截/"detach"脱落)。strict下用rawget避免访问未声明全局报错
	local getcfg = _rawget(GLOBAL, "GetStoredConfig")
	local cfg = getcfg and getcfg()
	if cfg == nil or cfg["attackBlock"] ~= "block" then return false end
	--佩戴的检验/考验勋章(标签由服务端同步，客户端可靠)
	for tag, match in pairs(BLOCK_MATCH) do
		if player:HasTag(tag) and not match(target) then
			return true--目标不匹配该勋章条件，拦截
		end
	end
	return false
end
GLOBAL.ShouldBlockAttackClient = ShouldBlockAttackClient

--客户端：拦截玩家攻击(ATTACK)。参考权威攻击拦截模组的4入口hook：选怪(F键)、动作执行、鼠标动作、战斗副本。
--用 AddClassPostConstruct 纯客户端组件类hook：服务端无playercontroller等类不执行，客户端(含本地主机)有则hook
local ACTIONS = GLOBAL.ACTIONS

--1. playercontroller：F键选怪(GetAttackTarget) + 动作执行(DoAction)
AddClassPostConstruct("components/playercontroller", function(self)
	local oldGetAttackTarget = self.GetAttackTarget
	if oldGetAttackTarget then
		self.GetAttackTarget = function(self, force_attack, ...)
			local target = oldGetAttackTarget(self, force_attack, ...)
			if target and not force_attack and ShouldBlockAttackClient(self.inst, target) then
				HelperDebug("攻击拦截: 选怪拦截 %s", target.prefab or "?")
				return nil--假装没看到
			end
			return target
		end
	end
	local oldDoAction = self.DoAction
	self.DoAction = function(self, buffaction, ...)
		if buffaction and buffaction.action and buffaction.action.id == "ATTACK" and buffaction.target
			and ShouldBlockAttackClient(self.inst, buffaction.target) then
			HelperDebug("攻击拦截: 动作拦截 %s", buffaction.target.prefab or "?")
			return--拒绝执行攻击
		end
		return oldDoAction(self, buffaction, ...)
	end
end)

--2. playeractionpicker：鼠标左键动作文字(GetLeftClickActions)
AddClassPostConstruct("components/playeractionpicker", function(self)
	local oldGetLeftClickActions = self.GetLeftClickActions
	if oldGetLeftClickActions then
		self.GetLeftClickActions = function(self, position, target)
			local actions = oldGetLeftClickActions(self, position, target)
			if target and actions and actions[1] and actions[1].action == ACTIONS.ATTACK
				and ShouldBlockAttackClient(self.inst, target) then
				table.remove(actions, 1)
			end
			return actions
		end
	end
end)

--3. combat_replica：目标能否被攻击(CanBeAttacked)，防其它途径
AddClassPostConstruct("components/combat_replica", function(self)
	local oldCanBeAttacked = self.CanBeAttacked
	if oldCanBeAttacked then
		self.CanBeAttacked = function(self, attacker, ...)
			if attacker and attacker == GLOBAL.ThePlayer and ShouldBlockAttackClient(attacker, self.inst) then
				return false--告诉客户端：此目标现在不能打
			end
			return oldCanBeAttacked(self, attacker, ...)
		end
	end
end)
