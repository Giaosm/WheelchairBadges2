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
local CROSS_GROUP_PRIORITY = AUTO_EQUIP_RULES.CROSS_GROUP_PRIORITY or {}--动作名→{勋章prefab→优先级}，跨组选最优用
--保护勋章机制见 helper_protect.lua(配置在 AUTO_EQUIP_RULES.PROTECT_MEDALS)，接口：GLOBAL.ComputeProtectedSet 等
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

--玩家是否拥有任何融合勋章(含本源勋章)
local function HasAnyFusion(player)
	for _, item in ipairs(GLOBAL.GetPlayerMedalItems(player)) do
		if FUSION_LEVELS[item.prefab] ~= nil then
			return true
		end
	end
	return false
end

--找玩家拥有的任意一个融合勋章(含本源勋章)；无则nil
local function FindAnyFusion(player)
	for _, item in ipairs(GLOBAL.GetPlayerMedalItems(player)) do
		if FUSION_LEVELS[item.prefab] ~= nil then
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

--找玩家拥有的组内指定prefab的勋章(真勋章或复制勋章)；无则nil。用于"按勋章分组"条件指定装某枚勋章(如PICK采巨型→虫木、采带刺→植物)
local function FindSpecificMedal(player, group, prefab)
	if prefab == nil then return nil end
	for _, item in ipairs(GLOBAL.GetPlayerMedalItems(player)) do
		local eff = (item.prefab == "copy_blank_certificate" and item.medalname) or item.prefab
		if eff == prefab and MEDAL_GROUP[eff] == group then
			return item
		end
	end
	return nil
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

--某勋章(含复制勋章)是否在受保护集合中；protectedSet为真实prefab→true的集合(见helper_protect.lua)
local function IsInProtectedSet(item, protectedSet)
	if item == nil or protectedSet == nil then return false end
	local prefab = (item.prefab == "copy_blank_certificate" and item.medalname) or item.prefab
	return protectedSet[prefab] ~= nil
end

--找融合勋章里放medal的格子：优先空格/最后一格/同组替换；满格且最后一格已被本次占用时，从后往前兜底替换一个可放的格子。
--usedSlots[fusion]={slot=true}为本次自动装备已占用的格子，避免多枚勋章满格时竞争同一格。
local function FindFusionSlot(fusion, medal, usedSlots, protectedSet)
	local container = fusion.components.container
	local numSlots = container:GetNumSlots()
	local used = usedSlots and usedSlots[fusion] or nil
	--第一遍：空格/最后一格/同组替换
	for i = 1, numSlots do
		if used == nil or not used[i] then
			local cur = container:GetItemInSlot(i)
			if IsInProtectedSet(cur, protectedSet) then
				--保护中：不替换该受保护勋章
			elseif container:itemtestfn(medal, i) then--能放
				if i >= numSlots then return i end--最后一格
				if cur == nil then return i end--空格
			elseif medal.grouptag then
				if cur ~= nil and cur.grouptag ~= nil and cur.grouptag == medal.grouptag then
					return i--同组替换优先
				end
			end
		end
	end
	--满格兜底：从后往前找可放的格子(避开本次已占用和受保护勋章)
	for i = numSlots, 1, -1 do
		if used == nil or not used[i] then
			local cur = container:GetItemInSlot(i)
			if not IsInProtectedSet(cur, protectedSet)
				and container:itemtestfn(medal, i) then
				return i
			end
		end
	end
	return nil
end

--把勋章放入融合勋章：已在内则不动；融合勋章内已有同组旧勋章则替换，旧勋章顶替新勋章原位置(保持布局)
--usedSlots为本次自动装备流程已占用格子表(满格装多枚避让用)，可为nil；protectedSet保护中不替换受保护勋章(见helper_protect.lua)
local function PutMedalIntoFusion(player, fusion, medal, usedSlots, protectedSet)
	if medal == nil or fusion == nil or not fusion.components.container then return end
	if IsHeldBy(medal, fusion) then return end--已在内

	local container = fusion.components.container
	local targetslot = FindFusionSlot(fusion, medal, usedSlots, protectedSet)
	if targetslot == nil then return end
	if usedSlots ~= nil then--登记本次已占用格子(按融合勋章区分)，供后续勋章避让
		usedSlots[fusion] = usedSlots[fusion] or {}
		usedSlots[fusion][targetslot] = true
	end

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
--usedSlots：本次自动装备流程已占用的融合勋章格子表(满格装多枚时避让用)，可为nil；protectedSet保护中不替换受保护勋章(见helper_protect.lua)
local function AutoEquipMedalForGroup(player, group, action, usedSlots, protectedSet, medalPrefab)
	if player == nil or not player:HasTag("player") then return end
	local inv = player.components.inventory
	if inv == nil then return end

	local action_id = action and action.action and action.action.id or group
	local target = action and (action.target or action.invobject)
	local target_prefab = target and target.prefab or "none"
	local current_time = GLOBAL.GetTime()
	local player_id = player.userid or player.guid or 0

	local current_equipped = GetEquippedMedal(player)

	--第一轮：条件指定勋章(medalPrefab)时用指定prefab，否则组内最优(提前算，用于缓存精确判断与后续复用)
	local bestMedal, bestScore
	if medalPrefab ~= nil then
		bestMedal = FindSpecificMedal(player, group, medalPrefab)
		if bestMedal ~= nil then
			bestScore = GetGroupScore(bestMedal, group)
		end
	end
	if bestMedal == nil then
		bestMedal, bestScore = FindBestGroupMedal(player, group)
	end
	if bestMedal == nil then return end--该组无可装备勋章

	--缓存命中：动作+目标相同且未过期，且本组最优勋章已真正装备(直接佩戴或在当前融合勋章内)则静默
	--(不能用"当前戴的==缓存里的勋章"判断，否则多组命中同一动作时会误拦截后续组塞入融合勋章)
	local decision_cache = player_decision_caches[player_id]
	if decision_cache
		and decision_cache.action_id == action_id
		and decision_cache.target_prefab == target_prefab
		and current_time - decision_cache.last_time < DECISION_CACHE_TIME then
		local already = false
		if current_equipped ~= nil then
			if current_equipped == bestMedal then
				already = true--直接佩戴本组最优
			elseif current_equipped.components and current_equipped.components.container
				and IsHeldBy(bestMedal, current_equipped) then
				already = true--本组最优已在当前融合勋章内
			end
		end
		if already then return end
	end

	--第二轮：有融合勋章时同分优先选已在其内的勋章，避免反复换位；条件指定勋章时不重新选(保持指定勋章)
	local bestFusion = FindBestFusionMedal(player, bestMedal)
	if medalPrefab == nil then
		bestMedal, bestScore = FindBestGroupMedal(player, group, bestFusion)
	end

	--方案一：有融合勋章 → 组合装备(最优融合勋章 + 最优目标勋章)
	if bestFusion ~= nil then
		--已是"最优融合勋章"且最优目标勋章已在其内 → 无需操作
		if current_equipped == bestFusion and IsHeldBy(bestMedal, bestFusion) then
			return
		end
		--把最优目标勋章放入最优融合勋章，再装备融合勋章
		PutMedalIntoFusion(player, bestFusion, bestMedal, usedSlots, protectedSet)
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
	--条件指定勋章时：当前已戴指定勋章则跳过，否则强制装指定勋章(不能因当前戴本组更高分勋章如植物而跳过)
	local equippedScore = GetGroupScore(current_equipped, group)
	if medalPrefab ~= nil then
		if current_equipped == bestMedal then return end
	elseif current_equipped ~= nil and equippedScore ~= nil and equippedScore >= bestScore then
		return--未指定勋章时才按"已佩戴本组最优"跳过
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
--条件字段名集合：用于识别 action_targets 的值是"单个条件表"还是"按勋章分组"(key为勋章prefab)
local COND_FIELDS = {
	tags = true, all_tags = true, prefabs = true, has_component = true, props = true,
	exclude_tags = true, exclude_all_tags = true, exclude_prefabs = true, hand_tags = true,
	recipe_builder_tag = true, exclude_recipe_props = true, keep_recipe_builder_tag = true,
	season_fish = true, slingshot_ammo = true,
}
--cond可为单个条件表，也可为"按勋章分组"表({勋章prefab = 条件表,...})，后者每条指定装组内哪枚勋章(medal)
--特殊动作：非ACTIONS动作，走独立监听(如致命伤)
local SPECIAL_ACTIONS = { REINCARNATION = true }
local SPECIAL_ACTION_ENTRIES = {}
for kind in pairs(SPECIAL_ACTIONS) do SPECIAL_ACTION_ENTRIES[kind] = {} end

--时空守护阈值：对齐能力勋章 SPEED_MEDAL.REINCARNATION_CONSUME(正常300/简易200)
local REINCARNATION_CONSUME = (GLOBAL.MedalAPI and GLOBAL.MedalAPI.TUNING_MEDAL
	and GLOBAL.MedalAPI.TUNING_MEDAL.SPEED_MEDAL
	and GLOBAL.MedalAPI.TUNING_MEDAL.SPEED_MEDAL.REINCARNATION_CONSUME) or 300

local function AddActionEntry(actionName, group, cond, medal)
	if SPECIAL_ACTIONS[actionName] then
		table.insert(SPECIAL_ACTION_ENTRIES[actionName], { group = group, cond = cond, medal = medal })
		return
	end
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
	table.insert(list, { group = group, cond = cond, medal = medal })
end
for group, groupCfg in pairs(AUTO_EQUIP_ACTIONS) do
	--1. 无条件动作
	if groupCfg.action_ids then
		for _, actionName in ipairs(groupCfg.action_ids) do
			AddActionEntry(actionName, group, nil)
		end
	end
	--2. 带条件动作：值为"按勋章分组"表时，每条子条件带medal指定勋章；否则为单个条件表
	if groupCfg.action_targets then
		for actionName, cond in pairs(groupCfg.action_targets) do
			if type(cond) == "table" then
				--判断是否按勋章分组：不含任何条件字段名 → key全是勋章prefab；空表视为单个空条件
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

		--hand_tags：判断"手持物品(invobject)"带任一指定标签即整体通过(短路)，用于DEPLOY等目标为地面/空的动作判断手持物(如种下农场作物种子)
		--与下方目标条件(target的tags/prefabs)为"或"关系：hand_tags命中 或 目标条件命中 都算通过
		if cond.hand_tags and #cond.hand_tags > 0 then
			local handobj = bufferedaction.invobject
			if handobj ~= nil then
				for _, tag in ipairs(cond.hand_tags) do
					if handobj:HasTag(tag) then return true end
				end
			end
		end

		--season_fish：必要条件(与目标判断为"与"关系)。未解之谜献祭范围内(玩家周围)有季节鱼且当前季节≠该鱼对应季节才可触发(换季献祭需时空勋章)
		--注：与hand_tags不同，这里不短路通过，只作前置校验；目标是否未解之谜书由下方prefabs判断
		if cond.season_fish then
			local found = false
			local doer = bufferedaction.doer
			if doer ~= nil then
				local x, y, z = doer.Transform:GetWorldPosition()
				local radius = (TUNING_MEDAL and TUNING_MEDAL.BOOK_SACRIFICE_RADIUS) or 4
				local ents = TheSim:FindEntities(x, y, z, radius, nil, { "INLIMBO", "player", "fx" })
				for _, v in ipairs(ents) do
					local fishSeason = cond.season_fish[v.prefab]
					if fishSeason ~= nil and TheWorld and TheWorld.state and TheWorld.state.season ~= fishSeason then
						found = true
						break
					end
				end
			end
			if not found then return false end
		end

		--slingshot_ammo：[必要条件]玩家手持弹弓(HANDS槽)当前装填弹药(weapon.projectile=ammo.."_proj")是任一指定prefab才触发。未命中return false，与目标判断为"与"关系
		if cond.slingshot_ammo and #cond.slingshot_ammo > 0 then
			local doer = bufferedaction.doer
			local slingshot = doer and doer.components.inventory and doer.components.inventory:GetEquippedItem(GLOBAL.EQUIPSLOTS.HANDS)
			local proj_prefab = slingshot and slingshot.components and slingshot.components.weapon and slingshot.components.weapon.projectile
			local match = false
			if proj_prefab ~= nil then
				for _, ap in ipairs(cond.slingshot_ammo) do
					if proj_prefab == (ap .. "_proj") then match = true break end
				end
			end
			HelperDebug("slingshot弹药判断: 弹弓=%s 弹药投射物=%s 命中=%s", slingshot and slingshot.prefab or "nil", tostring(proj_prefab), tostring(match))
			if not match then return false end
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
			if cond.props then--须满足指定属性(如is_oversized)：属性值为true表示目标须有此属性且为真，false表示须无/为假
				for prop, val in pairs(cond.props) do
					if (val and not target[prop]) or (not val and target[prop]) then
						return false
					end
				end
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

	--该勋章组是否已开启自动装备(玩家可通过UI开关关闭)。默认全开；未设置=开
	local function IsGroupEnabled(player, group)
		if player == nil then return true end
		local cfg = player.medal_group_enabled
		if cfg == nil then return true end
		return cfg[group] ~= false
	end

	--统一入口：按动作ID找对应组条目(可能多个)，条件命中的都自动装备对应组
	local function TryAutoEquip(bufferedaction)
		if bufferedaction == nil or bufferedaction.action == nil or bufferedaction.action.id == nil then return end
		LogActionDebug(bufferedaction)--调试：打印当前动作+目标(带防抖)
		local entries = ACTION_TO_GROUP[bufferedaction.action.id]
		if entries == nil then return end
		--本次自动装备流程已占用的融合勋章格子(按融合勋章区分)，供满格装多枚时避让
		local usedSlots = {}

		--保护机制：特定环境(如踏水在水面)下勋章不可被移走，防掉水/失去能力(见helper_protect.lua)
		local protectedSet = GLOBAL.ComputeProtectedSet(inst)
		if next(protectedSet) ~= nil then
			local protectedEquipped = GLOBAL.GetEquippedProtectedMedal(inst, protectedSet)--勋章槽直接戴的受保护勋章
			if protectedEquipped ~= nil then
				local fusion = FindAnyFusion(inst)--找一个可收纳受保护勋章的融合勋章
				if fusion == nil then
					--受保护勋章直接戴在勋章槽，且无融合勋章可收纳 → 不换装，保住它
					return
				end
				--有融合勋章：把受保护勋章移入融合勋章(同帧连续)，再走正常自动装备
				PutMedalIntoFusion(inst, fusion, protectedEquipped, usedSlots, protectedSet)
			end
			--若受保护勋章已在融合勋章内(protectedEquipped==nil)：正常自动装备，FindFusionSlot会跳过受保护格子
		end

		--跨组优先级：该动作配置了优先级表 且 玩家无融合勋章 → 只装备优先级最高的组
		--(有融合勋章时现有逐组逻辑会把各组勋章都塞进融合勋章，跨组并存，无需优先级)
		local cross_priority = CROSS_GROUP_PRIORITY[bufferedaction.action.id]
		if cross_priority ~= nil and not HasAnyFusion(inst) then
			local bestEntry, bestPriority = nil, nil
			for _, entry in ipairs(entries) do
				if IsGroupEnabled(inst, entry.group) and MatchActionTarget(bufferedaction, entry.cond) then
					--指定勋章(entry.medal)优先用其查优先级；否则用组内最优勋章查
					local bestMedal = nil
					if entry.medal ~= nil then
						bestMedal = FindSpecificMedal(inst, entry.group, entry.medal)
					end
					if bestMedal == nil then
						bestMedal = FindBestGroupMedal(inst, entry.group)
					end
					if bestMedal ~= nil then
						local prefab = (bestMedal.prefab == "copy_blank_certificate" and bestMedal.medalname) or bestMedal.prefab
						local prio = cross_priority[prefab]
						if prio ~= nil and (bestPriority == nil or prio > bestPriority) then
							bestPriority, bestEntry = prio, entry
						end
					end
				end
			end
			--命中的组里有勋章在优先级表内 → 只装备优先级最高的组
			if bestEntry ~= nil then
				AutoEquipMedalForGroup(inst, bestEntry.group, bufferedaction, usedSlots, protectedSet, bestEntry.medal)
				return
			end
			--否则(命中组的勋章都不在优先级表)回退到逐组装备
		end

		for _, entry in ipairs(entries) do
			if IsGroupEnabled(inst, entry.group) and MatchActionTarget(bufferedaction, entry.cond) then
				AutoEquipMedalForGroup(inst, entry.group, bufferedaction, usedSlots, protectedSet, entry.medal)
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

--------------------------------时空守护(致命伤保命)--------------------------------
--致命伤时自动装备本源+时空勋章，让能力勋章"轮回"触发保命(本源自动作容器装时空)。
local function TryFatalDamageAutoEquip(inst)
	if inst == nil or not inst:HasTag("player") or inst:HasTag("playerghost") then return end
	local entries = SPECIAL_ACTION_ENTRIES["REINCARNATION"]
	if entries == nil or GetOriginMedal(inst) == nil then return end--须有本源勋章作容器
	for _, entry in ipairs(entries) do
		local group = entry.group
		local cfg = inst.medal_group_enabled
		if cfg == nil or cfg[group] ~= false then--组开关开启
			local best = FindBestGroupMedal(inst, group)
			local prefab = best and ((best.prefab == "copy_blank_certificate" and best.medalname) or best.prefab) or nil
			--仅本源加成勋章且耐久足够才保命
			if prefab ~= nil and ORIGIN_BONUS_MAP[prefab] ~= nil
				and best.components.finiteuses
				and best.components.finiteuses:GetUses() >= REINCARNATION_CONSUME then
				AutoEquipMedalForGroup(inst, group, { action = { id = "REINCARNATION" } })
				HelperDebug("时空守护: 致命伤自动装备组%s(本源+%s)", group, prefab)
			end
		end
	end
end

--hook玩家health.SetVal，致命伤时先自动装备(先于能力勋章轮回执行)
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

--暴露到全局(供调试/手动调用)
GLOBAL.AutoEquipMedalForGroup = AutoEquipMedalForGroup
GLOBAL.TryFatalDamageAutoEquip = TryFatalDamageAutoEquip
