--自动装备核心：执行动作时佩戴"对应勋章组"最优组合。
--三层固定对比：①组内对比(MEDAL_LEVELS选组内优胜者)②同prefab对比(FindSpecificMedal)③跨组对比(CROSS_GROUP_PRIORITY取最高)。
--工具层见 helper_autoequip_util.lua(GLOBAL.AutoEquipUtil)。
local AUTO_EQUIP_ACTIONS = HelperRules_AUTO_EQUIP_ACTIONS
local DECISION_CACHE_TIME = 0.3
local U = GLOBAL.AutoEquipUtil

--------------------------------动作映射构建--------------------------------
local ACTION_TO_GROUP = {}
local COND_FIELDS = {
	tags = true, all_tags = true, prefabs = true, has_component = true, props = true,
	exclude_tags = true, exclude_all_tags = true, exclude_prefabs = true, hand_tags = true,
	recipe_builder_tag = true, exclude_recipe_props = true, keep_recipe_builder_tag = true,
	season_fish = true, slingshot_ammo = true,
}
local SPECIAL_ACTIONS = { REINCARNATION = true }
local SPECIAL_ACTION_ENTRIES = {}
for kind in pairs(SPECIAL_ACTIONS) do SPECIAL_ACTION_ENTRIES[kind] = {} end

local REINCARNATION_CONSUME = (GLOBAL.MedalAPI and GLOBAL.MedalAPI.TUNING_MEDAL
	and GLOBAL.MedalAPI.TUNING_MEDAL.SPEED_MEDAL
	and GLOBAL.MedalAPI.TUNING_MEDAL.SPEED_MEDAL.REINCARNATION_CONSUME) or 300

local function AddActionEntry(actionName, group, cond, medal)
	if SPECIAL_ACTIONS[actionName] then
		table.insert(SPECIAL_ACTION_ENTRIES[actionName], { group = group, cond = cond, medal = medal })
		return
	end
	if ACTIONS[actionName] == nil then
		HelperDebug("自动装备: 未找到动作 %s(组%s)，跳过", tostring(actionName), group)
		return
	end
	local list = ACTION_TO_GROUP[actionName]
	if list == nil then list = {}; ACTION_TO_GROUP[actionName] = list end
	table.insert(list, { group = group, cond = cond, medal = medal })
end
for group, groupCfg in pairs(AUTO_EQUIP_ACTIONS) do
	if groupCfg.action_ids then
		for _, actionName in ipairs(groupCfg.action_ids) do
			AddActionEntry(actionName, group, nil)
		end
	end
	if groupCfg.action_targets then
		for actionName, cond in pairs(groupCfg.action_targets) do
			if type(cond) == "table" then
				--key全为勋章prefab(不含条件字段)时，每条子条件带medal指定勋章
				local grouped = true
				for k in pairs(cond) do
					if COND_FIELDS[k] then grouped = false break end
				end
				if grouped and next(cond) ~= nil then
					for prefab, subcond in pairs(cond) do
						AddActionEntry(actionName, group, subcond, prefab)
					end
				else
					AddActionEntry(actionName, group, cond)
				end
			else
				AddActionEntry(actionName, group, cond)
			end
		end
	end
end

AddPlayerPostInit(function(inst)
	if not GLOBAL.TheNet:GetIsServer() then return end

	--动作调试(防抖)
	local last_action_log = {}
	local ACTION_LOG_TIME = 0.3
	local ACTION_LOG_MAX = 64
	local function LogActionDebug(bufferedaction)
		if bufferedaction == nil or bufferedaction.action == nil or bufferedaction.action.id == nil then return end
		local target = bufferedaction.target or bufferedaction.invobject
		local target_prefab = target and target.prefab or "none"
		local key = bufferedaction.action.id .. "|" .. target_prefab
		local now = GLOBAL.GetTime()
		local last = last_action_log[key]
		if last ~= nil and now - last < ACTION_LOG_TIME then return end
		last_action_log[key] = now
		local n = 0
		for _ in pairs(last_action_log) do n = n + 1 end
		if n > ACTION_LOG_MAX then
			for k in pairs(last_action_log) do last_action_log[k] = nil end
		end
		HelperDebug("执行动作 %s 目标 %s", bufferedaction.action.id, target_prefab)
	end

	local function IsGroupEnabled(player, group)
		if player == nil then return true end
		local cfg = player.medal_group_enabled
		if cfg == nil then return true end
		return cfg[group] ~= false
	end

	--从勋章槽卸下勋章放回背包(直接佩戴场景)
	local function UnequipSlotMedal(player, equipped)
		local owner = equipped.components.inventoryitem and equipped.components.inventoryitem.owner
		if owner ~= nil and owner.components.inventory ~= nil and equipped.components.equippable ~= nil
			and equipped.components.equippable:IsEquipped() then
			local item = owner.components.inventory:Unequip(equipped.components.equippable.equipslot)
			if item ~= nil then
				owner.components.inventory:GiveItem(item, nil, owner:GetPosition())
				HelperDebug("自动装备脱落: 卸下%s(目标不匹配)", equipped.prefab)
			end
		end
	end
	--从融合勋章容器移除勋章放回背包(融合勋章内场景)，复用能力勋章TAKEOFFMEDAL逻辑
	local function RemoveMedalFromFusion(player, medal, fusion)
		if medal == nil or fusion == nil or fusion.components.container == nil then return end
		if not medal.components.inventoryitem:IsHeldBy(fusion) then return end
		local item = fusion.components.container:RemoveItem(medal)
		if item ~= nil then
			item.prevcontainer = nil
			item.prevslot = nil
			player.components.inventory:GiveItem(item)
			HelperDebug("自动装备脱落: 从融合勋章移除%s(目标不匹配)", medal.prefab)
		end
	end
	--脱落模式：攻击目标不匹配佩戴(含融合勋章内)的检验/考验勋章时自动卸下(放行攻击)。复用ACTION_TO_GROUP+MatchActionTarget，与自动装备同逻辑
	local function TryDetachMedal(bufferedaction)
		if inst.medal_group_enabled == nil or inst.medal_group_enabled["attackBlock"] ~= "detach" then return end
		local entries = ACTION_TO_GROUP["ATTACK"]
		if entries == nil then return end
		local medal_slot = inst.components.inventory and inst.components.inventory:GetEquippedItem(GLOBAL.EQUIPSLOTS.MEDAL or GLOBAL.EQUIPSLOTS.NECK or GLOBAL.EQUIPSLOTS.BODY)
		for _, entry in ipairs(entries) do
			if entry.group == "valkyrieMedal" and entry.medal ~= nil
				and entry.medal ~= "valkyrie_certificate" then--只处理检验/考验，最终女武神不脱落
				local cond = entry.cond
				local matched = cond ~= nil and U.MatchActionTarget(bufferedaction, cond)
				--直接在勋章槽
				if medal_slot ~= nil and medal_slot.prefab == entry.medal and not matched then
					UnequipSlotMedal(inst, medal_slot)
				end
				--在融合勋章容器内
				if medal_slot ~= nil and medal_slot.components and medal_slot.components.container then
					for _, subitem in pairs(medal_slot.components.container.slots) do
						if subitem ~= nil and subitem.prefab == entry.medal and not matched then
							RemoveMedalFromFusion(inst, subitem, medal_slot)
						end
					end
				end
			end
		end
	end

	local function TryAutoEquip(bufferedaction)
		if bufferedaction == nil or bufferedaction.action == nil or bufferedaction.action.id == nil then return end
		LogActionDebug(bufferedaction)
		if bufferedaction.action.id == "ATTACK" then
			TryDetachMedal(bufferedaction)--脱落：复用与自动装备相同的ACTION_TO_GROUP+MatchActionTarget判断
		end
		local entries = ACTION_TO_GROUP[bufferedaction.action.id]
		if entries == nil then return end
		local usedSlots = {}

		--保护勋章(水面等环境不可移走)：把受保护勋章移入融合勋章后，须把融合勋章装备回勋章槽，避免勋章槽空
		local protectedSet = GLOBAL.ComputeProtectedSet(inst)
		if next(protectedSet) ~= nil then
			local protectedEquipped = GLOBAL.GetEquippedProtectedMedal(inst, protectedSet)
			if protectedEquipped ~= nil then
				local fusion = U.FindAnyFusion(inst)
				if fusion == nil then return end--无融合可收纳，保住不动
				U.PutMedalIntoFusion(inst, fusion, protectedEquipped, usedSlots, protectedSet)
				if inst.components.inventory then
					inst.components.inventory:Equip(fusion)--装备融合勋章回勋章槽，确保勋章槽不空
				end
			end
		end

		--第一层(组内对比)：每组选组内最优勋章prefab(指定medal，未指定则用FindBestGroupMedal取组内最优)，剔除未持有，每组留一个优胜者
		local group_best = {}
		for _, entry in ipairs(entries) do
			if IsGroupEnabled(inst, entry.group) and U.MatchActionTarget(bufferedaction, entry.cond) then
				local medal = entry.medal
				local entry_rank = medal and U.MEDAL_LEVELS[medal] or nil
				if medal == nil then
					local best = U.FindBestGroupMedal(inst, entry.group)
					if best ~= nil then
						medal = (best.prefab == "copy_blank_certificate" and best.medalname) or best.prefab
						entry_rank = U.MEDAL_LEVELS[medal]
					end
				end
				--剔除未持有/组内无可装勋章
				if medal ~= nil and U.FindSpecificMedal(inst, entry.group, medal) ~= nil then
					local cur = group_best[entry.group]
					if cur == nil or (entry_rank ~= nil and (cur.rank == nil or entry_rank > cur.rank)) then
						group_best[entry.group] = { entry = entry, medal = medal, rank = entry_rank }
					end
				end
			end
		end

		--第三层(跨组对比)：配置了跨组优先级的动作，收集进入决赛的组(在优先级表内)，按优先级降序逐个装备(能装几个装几个)
		local cross_priority = U.CROSS_GROUP_PRIORITY[bufferedaction.action.id]
		if cross_priority ~= nil then
			--正义武神模式：UI选"正义"时考验/检验降为20
			if inst.medal_jv_mode == "justice" then
				local cp = {}
				for k, v in pairs(cross_priority) do cp[k] = v end
				cp["valkyrie_test_certificate"] = 20
				cp["valkyrie_examine_certificate"] = 20
				cross_priority = cp
			end
			--收集决赛选手(在跨组优先级表内的组)并按优先级降序
			local finalists = {}
			for group, info in pairs(group_best) do
				local bestMedal = U.FindSpecificMedal(inst, group, info.medal)
				if bestMedal ~= nil then
					local prefab = (bestMedal.prefab == "copy_blank_certificate" and bestMedal.medalname) or bestMedal.prefab
					local prio = cross_priority[prefab]
					if prio ~= nil then
						table.insert(finalists, { group = group, info = info, prio = prio })
					end
				end
			end
			table.sort(finalists, function(a, b) return a.prio > b.prio end)
			--有决赛选手则装备：有融合勋章时按优先级逐个装(能装几个装几个)；无融合勋章时勋章槽只有一个，只装冠军
			if #finalists > 0 then
				if U.FindAnyFusion(inst) ~= nil then
					for _, f in ipairs(finalists) do
						AutoEquipMedalForGroup(inst, f.group, bufferedaction, usedSlots, protectedSet, f.info.medal)
					end
				else
					AutoEquipMedalForGroup(inst, finalists[1].group, bufferedaction, usedSlots, protectedSet, finalists[1].info.medal)
				end
				return
			end
			--无决赛选手(命中的组都不在优先级表) → 回退逐组装备
		end

		--逐组装备
		for group, info in pairs(group_best) do
			AutoEquipMedalForGroup(inst, group, bufferedaction, usedSlots, protectedSet, info.medal)
		end
	end

	inst:ListenForEvent("actionqueued", function(src, data)
		if data and data.action then TryAutoEquip(data.action) end
	end)

	inst:DoTaskInTime(0, function()
		if inst.components.locomotor then
			local oldPushAction = inst.components.locomotor.PushAction
			inst.components.locomotor.PushAction = function(self, bufferedaction, ...)
				if bufferedaction then TryAutoEquip(bufferedaction) end
				return oldPushAction(self, bufferedaction, ...)
			end
		end
		if inst.components.playercontroller then
			local oldDoAction = inst.components.playercontroller.DoAction
			inst.components.playercontroller.DoAction = function(self, bufferedaction, ...)
				if bufferedaction then TryAutoEquip(bufferedaction) end
				return oldDoAction(self, bufferedaction, ...)
			end
		end
	end)
end)

--------------------------------组合装备--------------------------------
local player_decision_caches = {}
local function AutoEquipMedalForGroup(player, group, action, usedSlots, protectedSet, medalPrefab)
	if player == nil or not player:HasTag("player") then return end
	local inv = player.components.inventory
	if inv == nil then return end

	local action_id = action and action.action and action.action.id or group
	local target = action and (action.target or action.invobject)
	local target_prefab = target and target.prefab or "none"
	local current_time = GLOBAL.GetTime()
	local player_id = player.userid or player.guid or 0
	local current_equipped = U.GetEquippedMedal(player)

	--先选最优融合勋章(按等级)，再带它选指定勋章：优先返回已在融合勋章内的，避免同prefab多个勋章来回换装
	local bestFusion = U.FindBestFusionMedal(player)
	local bestMedal
	if medalPrefab ~= nil then
		bestMedal = U.FindSpecificMedal(player, group, medalPrefab, bestFusion)
	end
	if bestMedal == nil then return end--指定勋章找不到就放弃，不回退组内其它勋章

	--缓存命中则静默
	local decision_cache = player_decision_caches[player_id]
	if decision_cache
		and decision_cache.action_id == action_id
		and decision_cache.target_prefab == target_prefab
		and current_time - decision_cache.last_time < DECISION_CACHE_TIME then
		local already = false
		if current_equipped ~= nil then
			if current_equipped == bestMedal then
				already = true
			elseif current_equipped.components and current_equipped.components.container
				and U.IsHeldBy(bestMedal, current_equipped) then
				already = true
			end
		end
		if already then return end
	end

	--方案一：有融合勋章 → 组合装备
	if bestFusion ~= nil then
		if current_equipped == bestFusion and U.IsHeldBy(bestMedal, bestFusion) then return end
		U.PutMedalIntoFusion(player, bestFusion, bestMedal, usedSlots, protectedSet)
		if current_equipped ~= bestFusion then
			inv:Equip(bestFusion)
			HelperDebug("自动装备组合[%s]: 融合%s + %s%s", group, bestFusion.prefab, bestMedal.prefab,
				(bestMedal.prefab == "copy_blank_certificate" and "("..tostring(bestMedal.medalname)..")" or ""))
		end
		player_decision_caches[player_id] = { action_id = action_id, target_prefab = target_prefab,
			medal_prefab = bestMedal.prefab, container_prefab = bestFusion.prefab, last_time = current_time }
		return
	end

	--方案二：无融合勋章 → 直接装备。当前已戴目标勋章则跳过，否则强制换装
	if current_equipped == bestMedal then return end
	inv:Equip(bestMedal)
	HelperDebug("自动装备勋章[%s]: %s%s", group, bestMedal.prefab,
		(bestMedal.prefab == "copy_blank_certificate" and "("..tostring(bestMedal.medalname)..")" or ""))
	player_decision_caches[player_id] = { action_id = action_id, target_prefab = target_prefab,
		medal_prefab = bestMedal.prefab, container_prefab = nil, last_time = current_time }
end

--------------------------------时空守护(致命伤保命)--------------------------------
local function TryFatalDamageAutoEquip(inst)
	if inst == nil or not inst:HasTag("player") or inst:HasTag("playerghost") then return end
	local entries = SPECIAL_ACTION_ENTRIES["REINCARNATION"]
	if entries == nil or U.GetOriginMedal(inst) == nil then return end
	for _, entry in ipairs(entries) do
		local group = entry.group
		local cfg = inst.medal_group_enabled
		if cfg == nil or cfg[group] ~= false then
			local best = U.FindBestGroupMedal(inst, group)
			local prefab = best and ((best.prefab == "copy_blank_certificate" and best.medalname) or best.prefab) or nil
			if prefab ~= nil and U.ORIGIN_BONUS_MAP[prefab] ~= nil
				and best.components.finiteuses
				and best.components.finiteuses:GetUses() >= REINCARNATION_CONSUME then
				AutoEquipMedalForGroup(inst, group, { action = { id = "REINCARNATION" } })
				HelperDebug("时空守护: 致命伤自动装备组%s(本源+%s)", group, prefab)
			end
		end
	end
end

AddComponentPostInit("health", function(self)
	local inst = self.inst
	if inst == nil or not inst:HasTag("player") or inst.helper_fataldamage_hooked then return end
	inst.helper_fataldamage_hooked = true
	local oldSetVal = self.SetVal
	self.SetVal = function(self, val, cause, afflicter, ...)
		local old_health, min_health = self.currenthealth, self.minhealth or 0
		if val <= min_health and old_health > min_health then
			TryFatalDamageAutoEquip(self.inst)
		end
		return oldSetVal and oldSetVal(self, val, cause, afflicter, ...) or nil
	end
end)

GLOBAL.AutoEquipMedalForGroup = AutoEquipMedalForGroup
GLOBAL.TryFatalDamageAutoEquip = TryFatalDamageAutoEquip
