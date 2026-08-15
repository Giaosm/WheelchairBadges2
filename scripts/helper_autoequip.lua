--自动装备：执行指定动作时自动佩戴"该动作对应勋章组"的最优组合。
--组内选最优勋章→选最优融合勋章(本源>高>中>初，同分含目标者优先)→组合装备；无融合勋章则直装。
--本源加成：选中勋章在本源加成名单时强制用本源勋章当容器。带决策缓存避免重复计算。
--数据来自 helper_autoequip_rules/actions.lua；扫描复用 helper_globalfn.GetPlayerMedalItems。
local AUTO_EQUIP_RULES = HelperRules_AUTO_EQUIP
local AUTO_EQUIP_ACTIONS = HelperRules_AUTO_EQUIP_ACTIONS
local DECISION_CACHE_TIME = 0.3--缓存期内已戴最优组合则静默

--------------------------------数据预处理--------------------------------
local MEDAL_LEVELS = {}--勋章prefab→等级(组内列表越靠前越高)
local MEDAL_GROUP = {}--勋章prefab→所属组
for group, levels in pairs(AUTO_EQUIP_RULES.Groups or {}) do
	for idx, prefab in ipairs(levels) do
		MEDAL_LEVELS[prefab] = #levels - idx + 1
		MEDAL_GROUP[prefab] = group
	end
end
local FUSION_LEVELS = {}--融合勋章prefab→等级
for _, f in ipairs(AUTO_EQUIP_RULES.FusionMedals or {}) do
	FUSION_LEVELS[f.prefab] = f.level
end
local ORIGIN_BONUS_MAP = {}--本源加成勋章集合
for _, prefab in ipairs(AUTO_EQUIP_RULES.ORIGIN_MEDAL_BONUS or {}) do
	ORIGIN_BONUS_MAP[prefab] = true
end
local COPY_PENALTY = 0.5--复制勋章比同级真勋章差一档
local ORIGIN_BONUS_BOOST = 0.1--本源加成提权

--------------------------------工具--------------------------------
--获取勋章栏当前物品
local function GetEquippedMedal(player)
	local inv = player and player.components and player.components.inventory
	if inv == nil then return nil end
	return inv:GetEquippedItem(EQUIPSLOTS.MEDAL or EQUIPSLOTS.NECK or EQUIPSLOTS.BODY)
end

--物品是否被某个融合勋章持有(在容器内部)
local function IsHeldBy(medal, carrier)
	return medal ~= nil and medal.components and medal.components.inventoryitem
		and medal.components.inventoryitem:IsHeldBy(carrier)
end

--某物品作为指定组勋章的质量分；非该组返回nil。真勋章按等级；复制勋章按同级-惩罚；本源加成名单内+提权
local function GetGroupScore(item, group)
	if item == nil then return nil end
	local prefab = item.prefab
	local level = MEDAL_LEVELS[prefab]
	local effective_prefab = prefab
	if level == nil and prefab == "copy_blank_certificate" and MEDAL_LEVELS[item.medalname] ~= nil and MEDAL_GROUP[item.medalname] == group then
		level = MEDAL_LEVELS[item.medalname] - COPY_PENALTY
		effective_prefab = item.medalname
	end
	if level == nil or MEDAL_GROUP[effective_prefab] ~= group then
		return nil
	end
	if ORIGIN_BONUS_MAP[effective_prefab] then
		level = level + ORIGIN_BONUS_BOOST
	end
	return level
end

--找玩家拥有的本源勋章(强制本源容器用)；无则nil
local function GetOriginMedal(player)
	for _, item in ipairs(GLOBAL.GetPlayerMedalItems(player)) do
		if item.prefab == "origin_certificate" then
			return item
		end
	end
	return nil
end

--找组内质量分最高的勋章。preferredFusion为优先容器：同分时优先选已在其内的勋章，避免反复换位
local function FindBestGroupMedal(player, group, preferredFusion)
	local best, bestScore, bestInPreferred = nil, nil, false
	for _, item in ipairs(GLOBAL.GetPlayerMedalItems(player)) do
		local score = GetGroupScore(item, group)
		if score ~= nil then
			local inPreferred = preferredFusion ~= nil and IsHeldBy(item, preferredFusion)
			if best == nil
				or score > bestScore
				or (score == bestScore and inPreferred and not bestInPreferred) then
				best, bestScore, bestInPreferred = item, score, inPreferred
			end
		end
	end
	return best, bestScore
end

--找最优融合勋章：等级高者优先，同分含目标勋章者优先。本源加成时强制本源勋章当容器
local function FindBestFusionMedal(player, bestMedal)
	--本源加成：优先选已含目标勋章的本源勋章，否则回退到第一个本源勋章
	if bestMedal ~= nil and ORIGIN_BONUS_MAP[(bestMedal.prefab == "copy_blank_certificate" and bestMedal.medalname) or bestMedal.prefab] then
		for _, item in ipairs(GLOBAL.GetPlayerMedalItems(player)) do
			if item.prefab == "origin_certificate" and IsHeldBy(bestMedal, item) then
				return item, FUSION_LEVELS[item.prefab] or 0
			end
		end
		local origin = GetOriginMedal(player)
		if origin ~= nil then
			return origin, FUSION_LEVELS[origin.prefab] or 0
		end
	end
	local best, bestLevel, bestHasTarget = nil, 0, false
	for _, item in ipairs(GLOBAL.GetPlayerMedalItems(player)) do
		local lvl = FUSION_LEVELS[item.prefab]
		if lvl ~= nil then
			local hasTarget = bestMedal ~= nil and IsHeldBy(bestMedal, item)
			if best == nil
				or lvl > bestLevel
				or (lvl == bestLevel and hasTarget and not bestHasTarget) then
				best, bestLevel, bestHasTarget = item, lvl, hasTarget
			end
		end
	end
	return best, bestLevel
end

--把勋章放入融合勋章：已在内则不动；融合勋章内已有同组旧勋章则替换，旧勋章顶替新勋章原位置(保持布局)
local function PutMedalIntoFusion(player, fusion, medal)
	if medal == nil or fusion == nil or not fusion.components.container then return end
	if IsHeldBy(medal, fusion) then return end--已在内

	local container = fusion.components.container
	local targetslot = container:GetSpecificMedalSlotForItem(medal)
	if targetslot == nil then return end

	--从原位置取出新勋章(记录原位置到prevcontainer/prevslot)
	local item = medal.components.inventoryitem and medal.components.inventoryitem:RemoveFromOwner(container.acceptsstacks)
	if item == nil then return end
	local oldslot = item.prevslot
	local oldcontainer = item.prevcontainer

	--融合勋章内已有同组旧勋章，先取出(待会儿顶替新勋章原位置)
	local cur = container:GetItemInSlot(targetslot)
	local old = (cur ~= nil and cur ~= item) and container:RemoveItemBySlot(targetslot) or nil

	--放入融合勋章；失败则新勋章和旧勋章都归还背包
	if not container:GiveItem(item, targetslot, nil, false) then
		player.components.inventory:GiveItem(item)
		if old ~= nil then
			old.prevcontainer = nil
			old.prevslot = nil
			player.components.inventory:GiveItem(old)
		end
		return
	end

	--旧勋章放回"新勋章原来的位置"(顶替其位置)，失败则放回背包
	if old ~= nil then
		if oldcontainer ~= nil and oldcontainer.inst and oldcontainer.inst:IsValid() then
			if not oldcontainer:GiveItem(old, oldslot) then
				old.prevcontainer = nil
				old.prevslot = nil
				player.components.inventory:GiveItem(old)
			end
		else
			old.prevcontainer = nil
			old.prevslot = nil
			player.components.inventory:GiveItem(old, oldslot)
		end
	end
end

--------------------------------决策缓存--------------------------------
local player_decision_caches = {}

--------------------------------组合装备--------------------------------
--自动装备指定组的最优组合(带决策缓存)。action用于取目标(prefab)作为缓存维度，可为nil
local function AutoEquipMedalForGroup(player, group, action)
	if player == nil or not player:HasTag("player") then return end
	local inv = player.components.inventory
	if inv == nil then return end

	local action_id = action and action.action and action.action.id or group
	local target = action and (action.target or action.invobject)
	local target_prefab = target and target.prefab or "none"
	local current_time = GLOBAL.GetTime()
	local player_id = player.userid or player.guid or 0

	local current_equipped = GetEquippedMedal(player)

	--缓存命中：动作+目标相同且未过期，且当前戴的正是缓存里的最优组合，则静默
	local decision_cache = player_decision_caches[player_id]
	if decision_cache
		and decision_cache.action_id == action_id
		and decision_cache.target_prefab == target_prefab
		and current_time - decision_cache.last_time < DECISION_CACHE_TIME then
		if current_equipped ~= nil and (
			current_equipped.prefab == decision_cache.container_prefab
			or current_equipped.prefab == decision_cache.medal_prefab) then
			return
		end
	end

	--第一轮：先定最优融合勋章；第二轮：同分时优先选已在其内的勋章，避免反复换位
	local bestMedal, bestScore = FindBestGroupMedal(player, group)
	if bestMedal == nil then return end--该组无可装备勋章
	local bestFusion = FindBestFusionMedal(player, bestMedal)
	bestMedal, bestScore = FindBestGroupMedal(player, group, bestFusion)

	--方案一：有融合勋章 → 组合装备(最优融合勋章 + 最优目标勋章)
	if bestFusion ~= nil then
		--已是"最优融合勋章"且最优目标勋章已在其内 → 无需操作
		if current_equipped == bestFusion and IsHeldBy(bestMedal, bestFusion) then
			return
		end
		--把最优目标勋章放入最优融合勋章，再装备融合勋章
		PutMedalIntoFusion(player, bestFusion, bestMedal)
		if current_equipped ~= bestFusion then
			inv:Equip(bestFusion)
			HelperDebug("自动装备组合[%s]: 融合%s + %s%s", group, bestFusion.prefab, bestMedal.prefab,
				(bestMedal.prefab == "copy_blank_certificate" and "("..tostring(bestMedal.medalname)..")" or ""))
		end
		--记录决策缓存
		player_decision_caches[player_id] = {
			action_id = action_id,
			target_prefab = target_prefab,
			medal_prefab = bestMedal.prefab,
			container_prefab = bestFusion.prefab,
			last_time = current_time,
		}
		return
	end

	--方案二：无融合勋章 → 直接装备最优目标勋章
	local equippedScore = GetGroupScore(current_equipped, group)
	if current_equipped ~= nil and equippedScore ~= nil and equippedScore >= bestScore then
		return--已佩戴本组最优勋章
	end
	--inv:Equip会自动把物品从原位置取出(背包/装备槽/容器)，并把勋章槽旧物品放回背包
	inv:Equip(bestMedal)
	HelperDebug("自动装备勋章[%s]: %s%s", group, bestMedal.prefab,
		(bestMedal.prefab == "copy_blank_certificate" and "("..tostring(bestMedal.medalname)..")" or ""))
	--记录决策缓存
	player_decision_caches[player_id] = {
		action_id = action_id,
		target_prefab = target_prefab,
		medal_prefab = bestMedal.prefab,
		container_prefab = nil,
		last_time = current_time,
	}
end

--------------------------------动作触发--------------------------------
--参考轮椅勋章助手的监听方式：hook玩家动作执行，动作开始前自动装备对应组。
--构建"动作ID → 组条目数组"。一个动作可对应多个勋章组(不同条件)，如BUILD/DISMANTLE/DEPLOY被厨师/巧手共用
--组配置结构(见helper_autoequip_actions.lua)：
--  action_ids     = { "CHOP", ... }                    => 无条件动作，条件为nil
--  action_targets = { DIG = {tags/all_tags/prefabs} }  => 带条件动作，条件为对应表
local ACTION_TO_GROUP = {}
local function AddActionEntry(actionName, group, cond)
	local action = ACTIONS[actionName]
	if action == nil then
		HelperDebug("自动装备: 未找到动作 %s(组%s)，跳过", tostring(actionName), group)
		return
	end
	local list = ACTION_TO_GROUP[actionName]
	if list == nil then
		list = {}
		ACTION_TO_GROUP[actionName] = list
	end
	table.insert(list, { group = group, cond = cond })
end
for group, groupCfg in pairs(AUTO_EQUIP_ACTIONS) do
	--1. 无条件动作
	if groupCfg.action_ids then
		for _, actionName in ipairs(groupCfg.action_ids) do
			AddActionEntry(actionName, group, nil)
		end
	end
	--2. 带条件动作
	if groupCfg.action_targets then
		for actionName, cond in pairs(groupCfg.action_targets) do
			AddActionEntry(actionName, group, cond)
		end
	end
end

AddPlayerPostInit(function(inst)
	--仅服务端执行自动装备逻辑(装备需要服务端权限)
	if not GLOBAL.TheNet:GetIsServer() then return end

	--动作调试：显示当前动作+目标，防抖与自动装备一致(同动作+同目标prefab 0.3秒记一次)
	local last_action_log = {}
	local ACTION_LOG_TIME = 0.3
	local ACTION_LOG_MAX = 64--防抖表容量上限，超限整体清空，防止长期运行只增不减
	local function LogActionDebug(bufferedaction)
		if bufferedaction == nil or bufferedaction.action == nil or bufferedaction.action.id == nil then return end
		local target = bufferedaction.target or bufferedaction.invobject
		local target_prefab = target and target.prefab or "none"
		local key = bufferedaction.action.id .. "|" .. target_prefab
		local now = GLOBAL.GetTime()
		local last = last_action_log[key]
		if last ~= nil and now - last < ACTION_LOG_TIME then return end--防抖：同动作同目标0.3秒记一次
		last_action_log[key] = now
		--容量控制：条目数超限时原地清空(调试表无需精确淘汰)
		local n = 0
		for _ in pairs(last_action_log) do n = n + 1 end
		if n > ACTION_LOG_MAX then
			for k in pairs(last_action_log) do last_action_log[k] = nil end
		end
		HelperDebug("执行动作 %s 目标 %s", bufferedaction.action.id, target_prefab)
	end

	--校验目标条件：cond为nil则无条件命中。排除字段(任一命中即不触发)优先，要求字段须同时满足
	--字段：exclude_tags(任一标签)/exclude_all_tags(全部标签)/exclude_prefabs(任一预制件)，
	--      tags(任一标签)/all_tags(全部标签)/prefabs(任一预制件)
	local function MatchActionTarget(bufferedaction, cond)
		if cond == nil then return true end
		local target = bufferedaction.target or bufferedaction.invobject

		--排除字段(命中任一即不触发)。仅在有目标时判断
		if target ~= nil then
			if cond.exclude_tags and #cond.exclude_tags > 0 then--带任一排除标签则不触发
				for _, tag in ipairs(cond.exclude_tags) do
					if target:HasTag(tag) then return false end
				end
			end
			if cond.exclude_all_tags and #cond.exclude_all_tags > 0 then--带全部这些标签才排除
				local allHit = true
				for _, tag in ipairs(cond.exclude_all_tags) do
					if not target:HasTag(tag) then allHit = false break end
				end
				if allHit then return false end
			end
			if cond.exclude_prefabs and #cond.exclude_prefabs > 0 then--为任一指定预制件则排除
				for _, p in ipairs(cond.exclude_prefabs) do
					if target.prefab == p then return false end
				end
			end
		end

		--要求字段：目标相关判断需有目标才执行(无目标时跳过，避免HasTag nil报错)
		if target ~= nil then
			if cond.tags and #cond.tags > 0 then--带任一指定标签即通过
				local hit = false
				for _, tag in ipairs(cond.tags) do
					if target:HasTag(tag) then hit = true break end
				end
				if not hit then return false end
			end
			if cond.all_tags and #cond.all_tags > 0 then--须带全部指定标签
				for _, tag in ipairs(cond.all_tags) do
					if not target:HasTag(tag) then return false end
				end
			end
			if cond.prefabs and #cond.prefabs > 0 then--须为指定预制件之一
				local hit = false
				for _, p in ipairs(cond.prefabs) do
					if target.prefab == p then hit = true break end
				end
				if not hit then return false end
			end
			if cond.has_component and #cond.has_component > 0 then--须带指定组件之一(如stewer)
				local hit = false
				for _, c in ipairs(cond.has_component) do
					if target.components and target.components[c] ~= nil then hit = true break end
				end
				if not hit then return false end
			end
		else
			--无目标时：除非条件依赖配方判断(recipe_builder_tag/exclude_recipe_props/keep_recipe_builder_tag)，否则不触发
			local hasRecipeCond = (cond.recipe_builder_tag and #cond.recipe_builder_tag > 0)
				or (cond.exclude_recipe_props and #cond.exclude_recipe_props > 0)
				or (cond.keep_recipe_builder_tag and #cond.keep_recipe_builder_tag > 0)
			if not hasRecipeCond then
				return false
			end
		end

		if cond.recipe_builder_tag and #cond.recipe_builder_tag > 0 then--制作配方的builder_tag命中才触发(区分勋章专属配方)
			--bufferedaction.recipe是配方名字符串，用AllRecipes查表后再取builder_tag
			local recipe = bufferedaction.recipe
			local hit = false
			if type(recipe) == "string" then
				local rec = GLOBAL.AllRecipes and GLOBAL.AllRecipes[recipe]
				if rec and rec.builder_tag then
					for _, tag in ipairs(cond.recipe_builder_tag) do
						if rec.builder_tag == tag then hit = true break end
					end
				end
			end
			if not hit then return false end
		end
		if cond.exclude_recipe_props and #cond.exclude_recipe_props > 0 then--排除带指定属性的配方(如builder_tag)，但keep_recipe_builder_tag命中的保留
			local recipe = bufferedaction.recipe
			if type(recipe) == "string" then
				local rec = GLOBAL.AllRecipes and GLOBAL.AllRecipes[recipe]
				if rec then
					local excluded = false
					for _, prop in ipairs(cond.exclude_recipe_props) do
						if rec[prop] ~= nil then excluded = true break end
					end
					if excluded then
						local kept = false
						if cond.keep_recipe_builder_tag and #cond.keep_recipe_builder_tag > 0 then
							for _, tag in ipairs(cond.keep_recipe_builder_tag) do
								if rec.builder_tag == tag then kept = true break end
							end
						end
						if not kept then return false end
					end
				end
			end
		end
		return true
	end

	--统一入口：按动作ID找对应组条目(可能多个)，条件命中的都自动装备对应组
	local function TryAutoEquip(bufferedaction)
		if bufferedaction == nil or bufferedaction.action == nil or bufferedaction.action.id == nil then return end
		LogActionDebug(bufferedaction)--调试：打印当前动作+目标(带防抖)
		local entries = ACTION_TO_GROUP[bufferedaction.action.id]
		if entries == nil then return end
		for _, entry in ipairs(entries) do
			if MatchActionTarget(bufferedaction, entry.cond) then
				AutoEquipMedalForGroup(inst, entry.group, bufferedaction)
			end
		end
	end

	--1. 监听动作入队事件
	inst:ListenForEvent("actionqueued", function(src, data)
		if data and data.action then
			TryAutoEquip(data.action)
		end
	end)

	--2. hook locomotor.PushAction(动作入队底层入口)
	inst:DoTaskInTime(0, function()
		if inst.components.locomotor then
			local oldPushAction = inst.components.locomotor.PushAction
			inst.components.locomotor.PushAction = function(self, bufferedaction, ...)
				if bufferedaction then
					TryAutoEquip(bufferedaction)
				end
				return oldPushAction(self, bufferedaction, ...)
			end
		end

		--3. hook playercontroller.DoAction(动作执行入口)
		if inst.components.playercontroller then
			local oldDoAction = inst.components.playercontroller.DoAction
			inst.components.playercontroller.DoAction = function(self, bufferedaction, ...)
				if bufferedaction then
					TryAutoEquip(bufferedaction)
				end
				return oldDoAction(self, bufferedaction, ...)
			end
		end
	end)
end)

--暴露到全局(供调试/手动调用)
GLOBAL.AutoEquipMedalForGroup = AutoEquipMedalForGroup
