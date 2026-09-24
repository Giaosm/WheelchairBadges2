--自动装备对齐(配合 helper_tags.lua)：决策要戴的勋章实际没戴上(缺佩)时，动作期间剥掉它提供的临时能力(标签/组件，按能力剥：
--同组其它只是"拥有未佩戴"的勋章不再顶上)、动作后恢复。
--剥离方式：设 player.helper_medal_align_exclude(缺佩勋章prefab集合)交给 RefreshPlayerMedalTags 处理，
--避免与物品变化触发的刷新互相覆盖(同 helper_medal_exam_running 思路)。
--边界两处：StartAction(选状态，官方快采 testfn 在内) 与 BufferedAction:Do(执行fn)，各"剥离→执行→恢复"一轮。
local FindEquippedMedal = GLOBAL.FindEquippedMedal--helper_tags.lua 导出

--开始：收集缺佩勋章、设排除表并刷新剥离
local function BeginAlign(player, expected, action_id, phase)
	if player == nil or not player:IsValid() then return false end
	local exclude = {}
	for _, prefab in ipairs(expected) do
		if prefab ~= nil and FindEquippedMedal(player, prefab) == nil then exclude[prefab] = true end
	end
	if TUNING.HELPER_DEBUG_SWITCH then
		local ctx = (action_id ~= nil and tostring(action_id) or "-") .. (phase ~= nil and ("·" .. phase) or "")
		local parts = {}
		for _, prefab in ipairs(expected) do
			table.insert(parts, prefab .. (exclude[prefab] and "(缺佩)" or "(已戴)"))
		end
		HelperDebug("对齐[%s] 应佩戴: %s", ctx, table.concat(parts, " "))
	end
	if next(exclude) == nil then return false end
	player.helper_medal_align_exclude = exclude
	if GLOBAL.RefreshPlayerMedalTags ~= nil then GLOBAL.RefreshPlayerMedalTags(player) end
	return true
end

--结束：清排除表并刷新恢复
local function EndAlign(player)
	if player == nil or not player:IsValid() then return end
	if player.helper_medal_align_exclude == nil then return end
	player.helper_medal_align_exclude = nil
	if GLOBAL.RefreshPlayerMedalTags ~= nil then GLOBAL.RefreshPlayerMedalTags(player) end
end

--动作边界：剥离→执行→恢复
local function RunAlignWindow(player, expected, action_id, phase, fn, ...)
	if expected == nil then return fn(...) end
	local active = BeginAlign(player, expected, action_id, phase)
	local results = {}
	local n = GLOBAL.CollectResults(results, pcall(fn, ...))--完整保留被包函数返回值(含尾部 nil)
	if active then EndAlign(player) end
	if not results[1] then error(results[2]) end
	return unpack(results, 2, n)
end

--选状态(先于 Do)：StartAction 内部调 sg.actionhandlers[action].deststate，官方快采/动作劫持的 testfn 就在里面，
--必须在此之前剥离；只挂 Do 来不及(状态已选完)。
local sgi = StateGraphInstance
if sgi ~= nil and sgi.StartAction ~= nil then
	local oldStartAction = sgi.StartAction
	sgi.StartAction = function(self, bufferedaction, ...)
		if bufferedaction == nil then return oldStartAction(self, bufferedaction, ...) end
		return RunAlignWindow(bufferedaction.doer, bufferedaction.helper_expected_medals,
			bufferedaction.action ~= nil and bufferedaction.action.id or nil, "选状态",
			oldStartAction, self, bufferedaction, ...)
	end
end

--执行fn
local oldBufferedActionDo = BufferedAction ~= nil and BufferedAction.Do or nil
if oldBufferedActionDo ~= nil then
	BufferedAction.Do = function(self, ...)
		return RunAlignWindow(self.doer, self.helper_expected_medals,
			self.action ~= nil and self.action.id or nil, "执行",
			oldBufferedActionDo, self, ...)
	end
end

GLOBAL.RunWithEquipAlign = RunAlignWindow--供 helper_autoequip 的动作fn层捕获复用(按钮直接执行路径)
