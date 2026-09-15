--自动装备核心：执行动作时佩戴"对应勋章组"最优组合。
--三层固定对比：①组内对比(MEDAL_LEVELS选组内优胜者)②同prefab对比(FindSpecificMedal)③跨组对比(CROSS_GROUP_PRIORITY取最高)。
--工具层见 helper_autoequip_util.lua(GLOBAL.AutoEquipUtil)。
local AUTO_EQUIP_ACTIONS = HelperRules_AUTO_EQUIP_ACTIONS
local DECISION_CACHE_TIME = 0.3
local U = GLOBAL.AutoEquipUtil
local GetRealPrefab = GLOBAL.GetMedalRealPrefab--取真名(复制勋章→印刻对象)，定义见 helper_globalfn.lua
--前向声明：AutoEquipMedalForGroup 定义在文件后半(组合装备段)，而 TryAutoEquip 在前半就会调用它。
--不声明的话 Lua 会把它当全局名解析(靠 mod env 兜底读 GLOBAL)，一旦 GLOBAL 上没有就直接 nil 报错。
local AutoEquipMedalForGroup

--------------------------------动作映射构建--------------------------------
local ACTION_TO_GROUP = {}
local COND_FIELDS = {
	tags = true, all_tags = true, prefabs = true, has_component = true, props = true,
	exclude_tags = true, exclude_all_tags = true, exclude_prefabs = true, hand_tags = true,
	recipe_builder_tag = true, exclude_recipe_props = true, keep_recipe_builder_tag = true,
	season_fish = true, slingshot_ammo = true, actor_prefabs = true,
}
local SPECIAL_ACTIONS = { REINCARNATION = true }
local SPECIAL_ACTION_ENTRIES = {}
for kind in pairs(SPECIAL_ACTIONS) do SPECIAL_ACTION_ENTRIES[kind] = {} end

local REINCARNATION_CONSUME = (GLOBAL.MedalAPI and GLOBAL.MedalAPI.TUNING_MEDAL
	and GLOBAL.MedalAPI.TUNING_MEDAL.SPEED_MEDAL
	and GLOBAL.MedalAPI.TUNING_MEDAL.SPEED_MEDAL.REINCARNATION_CONSUME) or 300

--配置自检(载入时只跑一次，只告警不改行为)：条件表的 key 只允许两种——①条件字段(见 COND_FIELDS)；②"按勋章分组"写法里的勋章prefab。
--两种都不是时该条目会"静默失效"(不报错也不装勋章)，最常见原因是新增条件字段却漏加进 COND_FIELDS。
local function ValidateCondKeys(actionName, group, cond, depth)
	if depth > 4 then return end--条件数组不会这么深，防配置写成自引用表时无限递归
	for k, v in pairs(cond) do
		if type(k) == "number" then
			if type(v) == "table" then ValidateCondKeys(actionName, group, v, depth + 1) end--条件数组("或")：递归子条件
		elseif COND_FIELDS[k] then
			--条件字段：其参数表(如 props={is_oversized=true})的key不是条件字段，不递归
		elseif U.MEDAL_LEVELS[k] ~= nil then
			--分组写法 动作={勋章prefab=条件表}：须是本组勋章(FindSpecificMedal 按同组判定)
			if U.MEDAL_GROUP[k] ~= group then
				HelperDebug("自动装备配置自检: %s 的 %s 指定勋章 %s 不属于本组(属 %s)，该条永不命中",
					tostring(group), tostring(actionName), tostring(k), tostring(U.MEDAL_GROUP[k]))
			end
			if type(v) == "table" then ValidateCondKeys(actionName, group, v, depth + 1) end
		else
			HelperDebug("自动装备配置自检: %s 的 %s 里 %s 既不是条件字段也不是本模组勋章prefab"
				.."(新条件字段请加进 helper_autoequip.lua 的 COND_FIELDS)，该条会静默失效",
				tostring(group), tostring(actionName), tostring(k))
		end
	end
end

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
				ValidateCondKeys(actionName, group, cond, 1)--自检：漏加COND_FIELDS/勋章名写错时告警
				--数组写法(cond[1]为子条件表，见配置文件头"条件数组")按条件表处理，不算分组
				--key全为勋章prefab(不含条件字段)时，每条子条件带medal指定勋章
				local grouped = cond[1] == nil
				if grouped then
					for k in pairs(cond) do
						if COND_FIELDS[k] then grouped = false break end
					end
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

--------------------------------动作fn层捕获--------------------------------
--部分动作是"按钮直接执行"(如红晶锅烹饪 BufferedAction:Do())，不经 actionqueued/PushAction/DoAction。
--给已配置动作的 fn 包一层：任何执行路径都先换装再跑原函数(红晶锅整组烹饪资格 CanStackCook 就在 fn 里判定)。
local function InstallActionFnHook()
	for action_id in pairs(ACTION_TO_GROUP) do
		local action = ACTIONS[action_id]
		local old_fn = action ~= nil and action.fn or nil
		if old_fn ~= nil and not action.helper_fn_hooked then
			action.helper_fn_hooked = true
			action.fn = function(act, ...)
				local player = act ~= nil and act.doer or nil
				local try = player ~= nil and player.helper_autoequip_fn or nil
				local was = act ~= nil and act.helper_expected_medals or nil
				if try ~= nil then try(act) end
				--应佩戴本就已知(前面捕获点已处理)走原函数；本入口才拿到就就地覆盖fn(按钮直接执行路径)
				if was == nil and act ~= nil and act.helper_expected_medals ~= nil and GLOBAL.RunWithEquipAlign ~= nil then
					return GLOBAL.RunWithEquipAlign(player, act.helper_expected_medals,
						act.action ~= nil and act.action.id or nil, "fn", old_fn, act, ...)
				end
				return old_fn(act, ...)
			end
		end
	end
end
InstallActionFnHook()

AddPlayerPostInit(function(inst)
	if not GLOBAL.TheNet:GetIsServer() then return end

	--动作调试(防抖)
	local last_action_log = {}
	local ACTION_LOG_TIME = 0.3
	local ACTION_LOG_MAX = 64
	local function LogActionDebug(bufferedaction)
		if not TUNING.HELPER_DEBUG_SWITCH then return end--关调试直接返回(省拼串/GetTime/计数遍历)
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

	--记录本次"应佩戴"(=全部决赛勋章)供helper_equip_align对齐检查；同一动作多触发点会重复进来，只在首次打日志
	local function RecordExpected(bufferedaction, expected)
		local first = bufferedaction.helper_expected_medals == nil
		bufferedaction.helper_expected_medals = expected
		if first and TUNING.HELPER_DEBUG_SWITCH then
			HelperDebug("自动装备决策[%s] 应佩戴: %s", bufferedaction.action.id, table.concat(expected, " "))
		end
	end

	local function TryAutoEquip(bufferedaction)
		if bufferedaction == nil or bufferedaction.action == nil or bufferedaction.action.id == nil then return end
		if bufferedaction.helper_autoequip_done then return end--同一动作只在最早捕获点处理一次
		bufferedaction.helper_autoequip_done = true
		LogActionDebug(bufferedaction)
		if bufferedaction.action.id == "ATTACK" then
			if GLOBAL.TryAutoRepairJustice ~= nil then
				GLOBAL.TryAutoRepairJustice(inst, bufferedaction)--正义勋章攻击前补正义值(复用本hook时机)
			end
		end
		local entries = ACTION_TO_GROUP[bufferedaction.action.id]
		if entries == nil then return end
		local usedSlots = {}

		--保护勋章(水面等环境不可移走)：把受保护勋章移入融合勋章后，须把融合勋章装备回勋章槽，避免勋章槽空
		local protectedSet = GLOBAL.ComputeProtectedSet(inst)
		if next(protectedSet) ~= nil then
			local protectedEquipped = GLOBAL.GetEquippedProtectedMedal(inst, protectedSet)
			if protectedEquipped ~= nil then
				--玩家手动把某物装备进勋章槽(右击融合勋章/单勋章)时，受保护勋章会被原生换装正常卸到背包，
				--不要再把它塞进融合勋章并重复装备，否则两次 Equip + 嵌套容器搬运冲突导致勋章丢失
				local medalSlot = GLOBAL.EQUIPSLOT_MEDAL--勋章槽(定义见 helper_globalfn.lua)
				local equipItem = bufferedaction.invobject or bufferedaction.target
				local isMedalSlotEquip = bufferedaction.action.id == "EQUIP"
					and equipItem ~= nil and equipItem.components
					and equipItem.components.equippable ~= nil
					and equipItem.components.equippable.equipslot == medalSlot
				if not isMedalSlotEquip then
					local fusion = U.FindAnyFusion(inst)
					if fusion == nil then return end--无融合可收纳，保住不动
					U.PutMedalIntoFusion(inst, fusion, protectedEquipped, usedSlots, protectedSet)
					if inst.components.inventory then
						inst.components.inventory:Equip(fusion)--装备融合勋章回勋章槽，确保勋章槽不空
					end
				end
			end
		end

		--最优融合勋章本动作只求一次：装备的始终是同一枚，装备后重算结果不变；避免每个匹配组各扫一遍全量
		local action_fusion, action_fusion_ready = nil, false
		local function GetActionFusion()
			if not action_fusion_ready then
				action_fusion_ready = true
				action_fusion = U.FindBestFusionMedal(inst)
			end
			return action_fusion
		end

		--第一层(组内对比)：每组选组内最优勋章prefab(指定medal，未指定则用FindBestGroupMedal取组内最优)，剔除未持有，每组留一个优胜者
		local group_best = {}
		for _, entry in ipairs(entries) do
			if IsGroupEnabled(inst, entry.group) and U.MatchActionTarget(bufferedaction, entry.cond) then
				local medal = entry.medal
				local entry_rank = medal and U.MEDAL_LEVELS[medal]
				if medal == nil then
					local best = U.FindBestGroupMedal(inst, entry.group)
					if best ~= nil then
						medal = GetRealPrefab(best)
						entry_rank = U.MEDAL_LEVELS[medal]
					end
				end
				--剔除未持有/组内无可装勋章(实例一并存下，后续决赛与装备复用，不再重复全量查找)
				local medal_item = medal ~= nil and U.FindSpecificMedal(inst, entry.group, medal) or nil
				if medal_item ~= nil then
					local cur = group_best[entry.group]
					if cur == nil or (entry_rank ~= nil and (cur.rank == nil or entry_rank > cur.rank)) then
						group_best[entry.group] = { entry = entry, medal = medal, rank = entry_rank, item = medal_item }
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
				local bestMedal = info.item--复用第一层已找到的实例
				if bestMedal ~= nil then
					local prefab = GetRealPrefab(bestMedal)
					local prio = cross_priority[prefab]
					if prio ~= nil then
						table.insert(finalists, { group = group, info = info, prio = prio })
					end
				end
			end
			table.sort(finalists, function(a, b) return a.prio > b.prio end)
			--有决赛选手则装备：有融合勋章时按优先级逐个装(能装几个装几个)；无融合勋章时勋章槽只有一个，只装冠军
			if #finalists > 0 then
				--应佩戴=全部决赛勋章(装不下的也算，供helper_equip_align判缺佩)
				local expected = {}
				for _, f in ipairs(finalists) do
					table.insert(expected, f.info.medal)
				end
				if GetActionFusion() ~= nil then--"有无融合勋章"与FindAnyFusion判据相同，复用同一次查找
					for _, f in ipairs(finalists) do
						AutoEquipMedalForGroup(inst, f.group, bufferedaction, usedSlots, protectedSet, f.info.medal, nil, GetActionFusion())
						--标记已处理勋章不可移走：防后续低优先级勋章把它挤出融合勋章(缓存/已在内提前返回也拦得住)
						protectedSet[f.info.medal] = true
					end
				else
					AutoEquipMedalForGroup(inst, finalists[1].group, bufferedaction, usedSlots, protectedSet, finalists[1].info.medal, nil, GetActionFusion())
				end
				RecordExpected(bufferedaction, expected)
				return
			end
			--无决赛选手(命中的组都不在优先级表) → 回退逐组装备
		end

		--逐组装备
		local expected = {}
		for group, info in pairs(group_best) do
			AutoEquipMedalForGroup(inst, group, bufferedaction, usedSlots, protectedSet, info.medal, nil, GetActionFusion())
			table.insert(expected, info.medal)
			protectedSet[info.medal] = true--同上：防止被后续勋章挤出融合勋章
		end
		RecordExpected(bufferedaction, expected)
	end

	inst.helper_autoequip_fn = TryAutoEquip--供动作fn层捕获复用

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
--玩家离开清掉决策缓存(key 与下面 AutoEquipMedalForGroup 内的算法保持一致)，避免残留小表
AddPlayerPostInit(function(player)
	if not GLOBAL.TheNet:GetIsServer() then return end
	player:ListenForEvent("onremove", function()
		player_decision_caches[player.userid or player.guid or 0] = nil
	end)
end)
AutoEquipMedalForGroup = function(player, group, action, usedSlots, protectedSet, medalPrefab, forcedMedalItem, action_fusion)
	if player == nil or not player:HasTag("player") then return end
	local inv = player.components.inventory
	if inv == nil then return end

	local action_id = action and action.action and action.action.id or group
	local target = action and (action.target or action.invobject)
	local target_prefab = target and target.prefab or "none"
	local current_time = GLOBAL.GetTime()
	local player_id = player.userid or player.guid or 0
	local current_equipped = U.GetEquippedMedal(player)
	if current_equipped ~= nil and not current_equipped:IsValid() then
		current_equipped = nil
		player_decision_caches[player_id] = nil
	end

	--先选最优融合勋章(按等级)，再带它选指定勋章：优先返回已在融合勋章内的，避免同prefab多个勋章来回换装
	--forcedMedalItem：调用方直接指定实例(致命伤保命用)，保证"耐久判定"与"实际装备/被扣耐久"是同一枚
	local bestFusion = action_fusion--调用方已在本动作内求过一次则复用(见GetActionFusion)，未传则自行查找
	if bestFusion == nil then bestFusion = U.FindBestFusionMedal(player) end
	if bestFusion ~= nil and not bestFusion:IsValid() then
		bestFusion = nil
		player_decision_caches[player_id] = nil
	end
	local bestMedal
	if forcedMedalItem ~= nil and forcedMedalItem:IsValid() then
		bestMedal = forcedMedalItem
	elseif medalPrefab ~= nil then
		bestMedal = U.FindSpecificMedal(player, group, medalPrefab, bestFusion)
	end
	if bestMedal == nil or not bestMedal:IsValid() then return end--指定勋章找不到或已失效就放弃，不回退组内其它勋章

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
			if TUNING.HELPER_DEBUG_SWITCH then--关调试时不拼串
				HelperDebug("自动装备组合[%s]: 融合%s + %s%s", group, bestFusion.prefab, bestMedal.prefab,
					(bestMedal.prefab == "copy_blank_certificate" and "("..tostring(bestMedal.medalname)..")" or ""))
			end
		end
		player_decision_caches[player_id] = { action_id = action_id, target_prefab = target_prefab,
			medal_prefab = bestMedal.prefab, container_prefab = bestFusion.prefab, last_time = current_time }
		return
	end

	--方案二：无融合勋章 → 直接装备。当前已戴目标勋章则跳过，否则强制换装
	if current_equipped == bestMedal then return end
	inv:Equip(bestMedal)
	if TUNING.HELPER_DEBUG_SWITCH then--关调试时不拼串
		HelperDebug("自动装备勋章[%s]: %s%s", group, bestMedal.prefab,
			(bestMedal.prefab == "copy_blank_certificate" and "("..tostring(bestMedal.medalname)..")" or ""))
	end
	player_decision_caches[player_id] = { action_id = action_id, target_prefab = target_prefab,
		medal_prefab = bestMedal.prefab, container_prefab = nil, last_time = current_time }
end

--------------------------------时空守护(致命伤保命)--------------------------------
--选保命用勋章实例：组内、本源可加成，取"耐久最高"的一枚
--(FindBestGroupMedal 同分时取的是遍历到的第一枚，可能是低耐久那枚，导致"判断够用、实际扣不够")
local function FindReincarnationMedal(player, group)
	local best, best_uses
	for _, item in ipairs(GLOBAL.GetPlayerMedalItems(player)) do
		local prefab = GetRealPrefab(item)
		local fu = item.components and item.components.finiteuses
		if prefab ~= nil and fu ~= nil and U.MEDAL_GROUP[prefab] == group and U.ORIGIN_BONUS_MAP[prefab] ~= nil then
			local uses = fu:GetUses()
			if best_uses == nil or uses > best_uses then
				best, best_uses = item, uses
			end
		end
	end
	return best, best_uses
end

local function TryFatalDamageAutoEquip(inst)
	if inst == nil or not inst:HasTag("player") or inst:HasTag("playerghost") then return end
	--与官方一致的状态守卫：官方在这些状态下不消耗耐久，避免无谓换装
	if inst.sg ~= nil and (inst.sg:HasStateTag("fallhole") or inst.sg:HasStateTag("dead")) then return end
	local entries = SPECIAL_ACTION_ENTRIES["REINCARNATION"]
	if entries == nil or U.GetOriginMedal(inst) == nil then return end
	for _, entry in ipairs(entries) do
		local group = entry.group
		local cfg = inst.medal_group_enabled
		if cfg == nil or cfg[group] ~= false then
			local best, uses = FindReincarnationMedal(inst, group)
			local prefab = best ~= nil and GetRealPrefab(best) or nil
			if prefab ~= nil and uses ~= nil and uses >= REINCARNATION_CONSUME then
				--透传best实例：避免内部再次查找时换成另一枚(导致"检查够用、实际扣不够")
				AutoEquipMedalForGroup(inst, group, { action = { id = "REINCARNATION" } }, nil, nil, prefab, best)
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

