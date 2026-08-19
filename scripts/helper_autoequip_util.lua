--自动装备工具层：勋章查找/评分/融合勋章操作 + 目标条件匹配(无闭包依赖的纯工具)。
--数据来自 helper_autoequip_rules.lua，经 GLOBAL.AutoEquipUtil 导出供 helper_autoequip.lua 消费。
local AUTO_EQUIP_RULES = HelperRules_AUTO_EQUIP
local COPY_PENALTY = 0.5
local ORIGIN_BONUS_BOOST = 0.1
local LOW_DURATION_PREFERRED = { arrest_certificate = true }

--------------------------------数据预处理--------------------------------
local MEDAL_LEVELS = {}
local MEDAL_GROUP = {}
for group, levels in pairs(AUTO_EQUIP_RULES.Groups or {}) do
	for idx, prefab in ipairs(levels) do
		MEDAL_LEVELS[prefab] = #levels - idx + 1
		MEDAL_GROUP[prefab] = group
	end
end
local FUSION_LEVELS = {}
for _, f in ipairs(AUTO_EQUIP_RULES.FusionMedals or {}) do
	FUSION_LEVELS[f.prefab] = f.level
end
local ORIGIN_BONUS_MAP = {}
for _, prefab in ipairs(AUTO_EQUIP_RULES.ORIGIN_MEDAL_BONUS or {}) do
	ORIGIN_BONUS_MAP[prefab] = true
end
local CROSS_GROUP_PRIORITY = AUTO_EQUIP_RULES.CROSS_GROUP_PRIORITY or {}

--------------------------------工具--------------------------------
local function GetEquippedMedal(player)
	local inv = player and player.components and player.components.inventory
	if inv == nil then return nil end
	return inv:GetEquippedItem(EQUIPSLOTS.MEDAL or EQUIPSLOTS.NECK or EQUIPSLOTS.BODY)
end

local function IsHeldBy(medal, carrier)
	return medal ~= nil and medal.components and medal.components.inventoryitem
		and medal.components.inventoryitem:IsHeldBy(carrier)
end

--组内质量分；真勋章按等级，复制勋章按同级-惩罚，本源加成+提权
local function GetGroupScore(item, group)
	if item == nil then return nil end
	local prefab = item.prefab
	local level = MEDAL_LEVELS[prefab]
	local effective_prefab = prefab
	if level == nil and prefab == "copy_blank_certificate" and MEDAL_LEVELS[item.medalname] ~= nil and MEDAL_GROUP[item.medalname] == group then
		level = MEDAL_LEVELS[item.medalname] - COPY_PENALTY
		effective_prefab = item.medalname
	end
	if level == nil or MEDAL_GROUP[effective_prefab] ~= group then return nil end
	if ORIGIN_BONUS_MAP[effective_prefab] then level = level + ORIGIN_BONUS_BOOST end
	return level
end

local function GetOriginMedal(player)
	for _, item in ipairs(GLOBAL.GetPlayerMedalItems(player)) do
		if item.prefab == "origin_certificate" then return item end
	end
	return nil
end

local function FindAnyFusion(player)
	for _, item in ipairs(GLOBAL.GetPlayerMedalItems(player)) do
		if FUSION_LEVELS[item.prefab] ~= nil then return item end
	end
	return nil
end

--低耐久偏好勋章(逮捕)同分时选耐久更低(快升级)
local function PreferLowerDuration(item, best)
	if best == nil then return true end
	if LOW_DURATION_PREFERRED[item.prefab] and LOW_DURATION_PREFERRED[best.prefab] then
		local fi, fb = item.components.finiteuses, best.components.finiteuses
		if fi ~= nil and fb ~= nil then return fi:GetPercent() < fb:GetPercent() end
	end
	return false
end

local function FindBestGroupMedal(player, group, preferredFusion)
	local best, bestScore, bestInPreferred = nil, nil, false
	for _, item in ipairs(GLOBAL.GetPlayerMedalItems(player)) do
		local score = GetGroupScore(item, group)
		if score ~= nil then
			local inPreferred = preferredFusion ~= nil and IsHeldBy(item, preferredFusion)
			if best == nil
				or score > bestScore
				or (score == bestScore and inPreferred and not bestInPreferred)
				or (score == bestScore and not inPreferred and not bestInPreferred and PreferLowerDuration(item, best)) then
				best, bestScore, bestInPreferred = item, score, inPreferred
			end
		end
	end
	return best, bestScore
end

--组内指定prefab勋章(真/复制)；preferredFusion传入时优先返回已在该融合勋章内的(避免同prefab多个勋章来回换装)；否则优先已装备，低耐久偏好勋章选耐久最低
local function FindSpecificMedal(player, group, prefab, preferredFusion)
	if prefab == nil then return nil end
	local current_equipped = GetEquippedMedal(player)
	local low_dur_pref = LOW_DURATION_PREFERRED[prefab]
	local fallback, fallback_low = nil, nil
	for _, item in ipairs(GLOBAL.GetPlayerMedalItems(player)) do
		local eff = (item.prefab == "copy_blank_certificate" and item.medalname) or item.prefab
		if eff == prefab and MEDAL_GROUP[eff] == group then
			if preferredFusion ~= nil and IsHeldBy(item, preferredFusion) then
				return item--已在最优融合勋章内，直接返回避免换装
			end
			if low_dur_pref then
				local pct = (item.components.finiteuses and item.components.finiteuses:GetPercent()) or 1
				if fallback == nil or pct < fallback_low then fallback, fallback_low = item, pct end
			else
				if item == current_equipped then return item end
				if fallback == nil then fallback = item end
			end
		end
	end
	return fallback
end

--最优融合勋章：等级高者优先，同分含目标勋章者优先。本源勋章(origin_certificate)为最高级融合勋章(level4)，有它时自然被选中当容器，无需额外强制
local function FindBestFusionMedal(player, bestMedal)
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

local function IsInProtectedSet(item, protectedSet)
	if item == nil or protectedSet == nil then return false end
	local prefab = (item.prefab == "copy_blank_certificate" and item.medalname) or item.prefab
	return protectedSet[prefab] ~= nil
end

--找融合勋章放medal的格子：空格/最后一格/同组替换优先；满格时从后往前兜底。usedSlots避让本次已占格子
local function FindFusionSlot(fusion, medal, usedSlots, protectedSet)
	local container = fusion.components.container
	local numSlots = container:GetNumSlots()
	local used = usedSlots and usedSlots[fusion] or nil
	for i = 1, numSlots do
		if used == nil or not used[i] then
			local cur = container:GetItemInSlot(i)
			if IsInProtectedSet(cur, protectedSet) then
			elseif container:itemtestfn(medal, i) then
				if i >= numSlots then return i end
				if cur == nil then return i end
			elseif medal.grouptag then
				if cur ~= nil and cur.grouptag ~= nil and cur.grouptag == medal.grouptag then return i end
			end
		end
	end
	for i = numSlots, 1, -1 do
		if used == nil or not used[i] then
			local cur = container:GetItemInSlot(i)
			if not IsInProtectedSet(cur, protectedSet) and container:itemtestfn(medal, i) then return i end
		end
	end
	return nil
end

--把勋章放入融合勋章：已在内则不动；内有同组旧勋章则替换，旧勋章顶替新勋章原位置
local function PutMedalIntoFusion(player, fusion, medal, usedSlots, protectedSet)
	if medal == nil or fusion == nil or not fusion.components.container then return end
	if IsHeldBy(medal, fusion) then return end

	local container = fusion.components.container
	local targetslot = FindFusionSlot(fusion, medal, usedSlots, protectedSet)
	if targetslot == nil then return end
	if usedSlots ~= nil then
		usedSlots[fusion] = usedSlots[fusion] or {}
		usedSlots[fusion][targetslot] = true
	end

	local item = medal.components.inventoryitem and medal.components.inventoryitem:RemoveFromOwner(container.acceptsstacks)
	if item == nil then return end
	local oldslot = item.prevslot
	local oldcontainer = item.prevcontainer

	local cur = container:GetItemInSlot(targetslot)
	local old = (cur ~= nil and cur ~= item) and container:RemoveItemBySlot(targetslot) or nil

	if not container:GiveItem(item, targetslot, nil, false) then
		player.components.inventory:GiveItem(item)
		if old ~= nil then
			old.prevcontainer = nil
			old.prevslot = nil
			player.components.inventory:GiveItem(old)
		end
		return
	end

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

--------------------------------目标条件匹配(纯函数)--------------------------------
local function MatchActionTarget(bufferedaction, cond)
	if cond == nil then return true end
	--条件数组("或")：任一子条件满足即触发(递归)
	if type(cond) == "table" and cond[1] ~= nil then
		for _, subcond in ipairs(cond) do
			if MatchActionTarget(bufferedaction, subcond) then return true end
		end
		return false
	end
	local target = bufferedaction.target or bufferedaction.invobject

	if target ~= nil then
		if cond.exclude_tags and #cond.exclude_tags > 0 then
			for _, tag in ipairs(cond.exclude_tags) do
				if target:HasTag(tag) then return false end
			end
		end
		if cond.exclude_all_tags and #cond.exclude_all_tags > 0 then
			local allHit = true
			for _, tag in ipairs(cond.exclude_all_tags) do
				if not target:HasTag(tag) then allHit = false break end
			end
			if allHit then return false end
		end
		if cond.exclude_prefabs and #cond.exclude_prefabs > 0 then
			for _, p in ipairs(cond.exclude_prefabs) do
				if target.prefab == p then return false end
			end
		end
	end

	--hand_tags：手持物带任一指定标签即通过
	if cond.hand_tags and #cond.hand_tags > 0 then
		local handobj = bufferedaction.invobject
		if handobj ~= nil then
			for _, tag in ipairs(cond.hand_tags) do
				if handobj:HasTag(tag) then return true end
			end
		end
	end

	--season_fish：范围内有季节鱼且季节不符才可触发
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

	--slingshot_ammo：手持弹弓装填指定弹药
	if cond.slingshot_ammo and #cond.slingshot_ammo > 0 then
		local doer = bufferedaction.doer
		local slingshot = doer and doer.components.inventory and doer.components.inventory:GetEquippedItem(GLOBAL.EQUIPSLOTS.HANDS)
		local match = false
		if slingshot ~= nil then
			local proj_prefab = slingshot.components and slingshot.components.weapon and slingshot.components.weapon.projectile
			local ammo_item = slingshot.components and slingshot.components.container and slingshot.components.container:GetItemInSlot(slingshot.overrideammoslot or 1)
			for _, ap in ipairs(cond.slingshot_ammo) do
				local tag_name = string.match(ap, "^tag:(.+)$")
				if tag_name ~= nil then
					if ammo_item ~= nil and ammo_item:HasTag(tag_name) then match = true break end
				elseif proj_prefab ~= nil and proj_prefab == (ap .. "_proj") then
					match = true break
				end
			end
		end
		if not match then return false end
	end

	if target ~= nil then
		if cond.tags and #cond.tags > 0 then
			local hit = false
			for _, tag in ipairs(cond.tags) do
				local prefab_name = string.match(tag, "^prefab:(.+)$")
				if prefab_name ~= nil then
					if target.prefab == prefab_name then hit = true break end
				elseif target:HasTag(tag) then hit = true break end
			end
			if not hit then return false end
		end
		if cond.all_tags and #cond.all_tags > 0 then
			for _, tag in ipairs(cond.all_tags) do
				if not target:HasTag(tag) then return false end
			end
		end
		if cond.prefabs and #cond.prefabs > 0 then
			local hit = false
			for _, p in ipairs(cond.prefabs) do
				if target.prefab == p then hit = true break end
			end
			if not hit then return false end
		end
		if cond.has_component and #cond.has_component > 0 then
			local hit = false
			for _, c in ipairs(cond.has_component) do
				if target.components and target.components[c] ~= nil then hit = true break end
			end
			if not hit then return false end
		end
		if cond.props then
			for prop, val in pairs(cond.props) do
				if (val and not target[prop]) or (not val and target[prop]) then return false end
			end
		end
	else
		local hasRecipeCond = (cond.recipe_builder_tag and #cond.recipe_builder_tag > 0)
			or (cond.exclude_recipe_props and #cond.exclude_recipe_props > 0)
			or (cond.keep_recipe_builder_tag and #cond.keep_recipe_builder_tag > 0)
		if not hasRecipeCond then return false end
	end

	if cond.recipe_builder_tag and #cond.recipe_builder_tag > 0 then
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
	if cond.exclude_recipe_props and #cond.exclude_recipe_props > 0 then
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

--------------------------------导出--------------------------------
local util = {}
util.MEDAL_LEVELS = MEDAL_LEVELS
util.MEDAL_GROUP = MEDAL_GROUP
util.FUSION_LEVELS = FUSION_LEVELS
util.ORIGIN_BONUS_MAP = ORIGIN_BONUS_MAP
util.CROSS_GROUP_PRIORITY = CROSS_GROUP_PRIORITY
util.GetEquippedMedal = GetEquippedMedal
util.IsHeldBy = IsHeldBy
util.GetGroupScore = GetGroupScore
util.GetOriginMedal = GetOriginMedal
util.FindAnyFusion = FindAnyFusion
util.PreferLowerDuration = PreferLowerDuration
util.FindBestGroupMedal = FindBestGroupMedal
util.FindSpecificMedal = FindSpecificMedal
util.FindBestFusionMedal = FindBestFusionMedal
util.IsInProtectedSet = IsInProtectedSet
util.FindFusionSlot = FindFusionSlot
util.PutMedalIntoFusion = PutMedalIntoFusion
util.MatchActionTarget = MatchActionTarget
GLOBAL.AutoEquipUtil = util
