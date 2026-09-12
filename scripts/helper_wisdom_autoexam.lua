--蒙昧勋章自动答题：自动寻找新华字典并周期答对，直到字典耗尽。开关读 medal_group_enabled["autoexam"]
local exam_interval = 0.3

local function IsAutoExamEnabled(player)
	local g = player and player.medal_group_enabled
	return g == nil or g["autoexam"] ~= false
end

--加载题目数据(正确答案)；失败禁用
local medal_exams
pcall(function()
	local lang = GLOBAL.TUNING and GLOBAL.TUNING.MEDAL_LANGUAGE or "ch"
	medal_exams = GLOBAL.require("medal_defs/" .. (lang == "ch" and "medal_exam_defs" or "medal_exam_defs_en"))
end)
if type(medal_exams) ~= "table" then
	medal_exams = nil
	if HelperDebug then HelperDebug("蒙昧自动答题: 无法加载题目数据，已禁用") end
end

local function FindDictionary(player)
	local inv = player.components.inventory
	if inv == nil then return nil end
	local dict = inv:GetEquippedItem(GLOBAL.EQUIPSLOTS.HANDS)
	if dict ~= nil and dict.prefab == "xinhua_dictionary" then return dict end
	return inv:FindItem(function(item) return item ~= nil and item.prefab == "xinhua_dictionary" end)
end

local player_tasks = {}
--答题期间置内部标志：helper_tags视智慧组关闭(不赋予临时reader防消耗翻倍)。不碰客户端权威开关值
local function SetExamRunning(player, running)
	local old = player.helper_medal_exam_running
	if old == running then return end
	player.helper_medal_exam_running = running or nil
	if GLOBAL.RefreshPlayerMedalTags then GLOBAL.RefreshPlayerMedalTags(player) end
end
local function StopAutoExam(player)
	local task = player_tasks[player]
	if task ~= nil then task:Cancel() end
	player_tasks[player] = nil
	SetExamRunning(player, false)
end

local function DoAutoExam(player)
	if player == nil or not player:IsValid() then return end
	if not IsAutoExamEnabled(player) or medal_exams == nil then return end
	local inv = player.components.inventory
	if inv == nil or inv.EquipMedalWithName == nil then return end
	local medal = inv:EquipMedalWithName("wisdom_test_certificate")
	if medal == nil or medal.components.medal_examable == nil then StopAutoExam(player) return end
	local hand = inv:GetEquippedItem(GLOBAL.EQUIPSLOTS.HANDS)
	--原版逻辑：字典必须手持才能答题；手上拿别的东西则不顶掉、停止答题
	if hand ~= nil and hand.prefab ~= "xinhua_dictionary" then
		StopAutoExam(player)
		return
	end
	local dict = FindDictionary(player)
	if dict == nil or dict.components.finiteuses == nil then
		medal.used_dictionary = nil--字典没了就清标记，避免残留(换新字典不会少扣一题)
		StopAutoExam(player)
		return
	end
	if dict.components.finiteuses:GetUses() <= 0 then
		medal.used_dictionary = nil
		StopAutoExam(player)
		return
	end
	--手部空则把字典装备到手上(符合官方"手持字典答题"语义)
	if hand == nil then
		inv:Equip(dict)
	end
	local examable = medal.components.medal_examable
	local ex = medal_exams[examable.examid]
	local true_answer = ex and ex.answer
	--未知题仍交MakeChoice自动跳下一题
	--本回合已用字典则不再重复扣
	if not medal.used_dictionary then
		dict.components.finiteuses:Use(1)
		medal.used_dictionary = true
	end
	--1.6.8.0 起答对分支不再调 MedalSay；本路径只传正确答案，无需再全局替换 MedalSay
	local ok2, err = pcall(function() examable:MakeChoice(true_answer, player) end)
	if not ok2 and HelperDebug then HelperDebug("蒙昧自动答题出错: %s", tostring(err)) end
end

local function StartAutoExam(player)
	if player_tasks[player] ~= nil then return end
	SetExamRunning(player, true)
	player_tasks[player] = player:DoPeriodicTask(exam_interval, function() DoAutoExam(player) end)
end

--容器收到蒙昧勋章时启动自动答题
local function ListenAutoExamContainers(player)
	local inv = player.components and player.components.inventory
	if inv == nil then return end
	local scanned = {}
	local function scanContainer(item)
		if item == nil or scanned[item.GUID] then return end
		scanned[item.GUID] = true
		local c = item.components and item.components.container
		if c then
			if not item.helper_autoexam_listened then
				item.helper_autoexam_listened = true
				item:ListenForEvent("itemget", function(_, data)
					local got = data and data.item
					--装进蒙昧勋章且已生效(所在融合勋章已装备)才启动
					if got ~= nil and got.prefab == "wisdom_test_certificate" then
						local inv = player.components and player.components.inventory
						if inv ~= nil and inv.EquipMedalWithName and inv:EquipMedalWithName("wisdom_test_certificate") ~= nil then
							StartAutoExam(player)
						end
					end
				end)
			end
			if c.slots then
				for _, subitem in pairs(c.slots) do
					scanContainer(subitem)
				end
			end
		end
	end
	for _, item in pairs(inv.itemslots or {}) do scanContainer(item) end
	for _, item in pairs(inv.equipslots or {}) do scanContainer(item) end
end

AddPlayerPostInit(function(player)
	if TheWorld ~= nil and not TheWorld.ismastersim then return end
	player:ListenForEvent("equip", function(_, data)
		if data ~= nil and data.item ~= nil
			and (data.item.prefab == "wisdom_test_certificate" or data.item.prefab == "xinhua_dictionary") then
			StartAutoExam(player)
		end
	end)
	local function TryStop()
		local inv = player.components.inventory
		if inv == nil then StopAutoExam(player) return end
		if not (inv.EquipMedalWithName and inv:EquipMedalWithName("wisdom_test_certificate")) then
			StopAutoExam(player)
		end
	end
	player:ListenForEvent("itemlose", TryStop)
	player:ListenForEvent("unequip", TryStop)
	player:ListenForEvent("onremove", function() StopAutoExam(player) end)
end)

--进世界时：挂容器监听；当前已有蒙昧勋章则启动
AddPrefabPostInit("world", function(inst)
	inst:ListenForEvent("ms_playerjoined", function(src, player)
		if player == nil or not player:HasTag("player") then return end
		ListenAutoExamContainers(player)
		local inv = player.components and player.components.inventory
		if inv ~= nil and inv.EquipMedalWithName and inv:EquipMedalWithName("wisdom_test_certificate") ~= nil then
			StartAutoExam(player)
		end
	end)
end)
