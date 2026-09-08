--轮椅开关RPC：客户端UI配置同步到服务端
--用json字符串传输：直接发boolean会丢失false(服务端收到nil)，json可完整保留
--
--【UI各开关的同步方式】
-- 1. 勋章组开/关开关(chopMedal/chefMedal/justiceMedal/valkyrieMedal等) → 存 group_enabled → SyncGroupEnabled
--    其中 attackBlock("攻击拦截"，针对女武神组)也存 group_enabled，复用 SyncGroupEnabled 同步，服务端读 player.medal_group_enabled["attackBlock"]
-- 2. 强制保留勋章列表(强制保留UI) → SyncForcedKeep → player.medal_forced_keep
-- 3. 自动补充耐久阈值(自动补充UI，含正义勋章目标选择) → SyncAutoRepair → player.medal_autorepair
-- 4. 正义武神模式(正义/武神切换UI) → SyncJVMode → player.medal_jv_mode
local RPC_NAMESPACE = "Wheelchair_Medal"

--服务端：接收客户端全量组开关配置(json字符串)。含各勋章组开关 + attackBlock(攻击拦截)开关
AddModRPCHandler(RPC_NAMESPACE, "SyncGroupEnabled", function(player, settings_json)
	if player == nil or player.components == nil or type(settings_json) ~= "string" then return end
	local ok, cfg = pcall(GLOBAL.json.decode, settings_json)
	if not ok or type(cfg) ~= "table" then return end
	player.medal_group_enabled = cfg
	GLOBAL.RefreshPlayerMedalTags(player)
end)

--客户端：全量发送组开关配置(含attackBlock)
GLOBAL.SyncGroupEnabled = function(cfg)
	SendModRPCToServer(GetModRPC(RPC_NAMESPACE, "SyncGroupEnabled"), GLOBAL.json.encode(cfg))
end

--服务端：接收客户端强制保留勋章列表(json字符串数组)，存到player.medal_forced_keep供自动装备保护
AddModRPCHandler(RPC_NAMESPACE, "SyncForcedKeep", function(player, list_json)
	if player == nil or player.components == nil or type(list_json) ~= "string" then return end
	local ok, list = pcall(GLOBAL.json.decode, list_json)
	if not ok or type(list) ~= "table" then return end
	--仅保留字符串prefab、去重、限制最多9个
	local seen, result = {}, {}
	for _, p in ipairs(list) do
		if type(p) == "string" and not seen[p] and #result < 9 then
			seen[p] = true
			table.insert(result, p)
		end
	end
	player.medal_forced_keep = result
end)

--客户端：全量发送强制保留勋章列表
GLOBAL.SyncForcedKeep = function(list)
	SendModRPCToServer(GetModRPC(RPC_NAMESPACE, "SyncForcedKeep"), GLOBAL.json.encode(list))
end

--服务端：接收客户端自动补充耐久阈值(json字符串表{prefab=百分比})，存到player.medal_autorepair
AddModRPCHandler(RPC_NAMESPACE, "SyncAutoRepair", function(player, cfg_json)
	if player == nil or player.components == nil or type(cfg_json) ~= "string" then return end
	local ok, cfg = pcall(GLOBAL.json.decode, cfg_json)
	if not ok or type(cfg) ~= "table" then return end
	--仅保留有效阈值：普通勋章0/10/20/30；正义勋章0~#JUSTICE_TARGETS(目标索引含智能)
	local jcount = (GLOBAL.JUSTICE_TARGETS and #GLOBAL.JUSTICE_TARGETS) or 0
	local result = {}
	for prefab, pct in pairs(cfg) do
		if type(prefab) == "string" then
			if prefab == "justice_certificate" then
				if pct == 0 or (pct >= 1 and pct <= jcount) then result[prefab] = pct end
			elseif pct == 0 or pct == 10 or pct == 20 or pct == 30 then
				result[prefab] = pct
			end
		end
	end
	player.medal_autorepair = result
end)

--客户端：全量发送自动补充耐久阈值
GLOBAL.SyncAutoRepair = function(cfg)
	SendModRPCToServer(GetModRPC(RPC_NAMESPACE, "SyncAutoRepair"), GLOBAL.json.encode(cfg))
end

--服务端：接收客户端"正义武神"模式(justice/valkyrie)，存player.medal_jv_mode(影响跨组优先级ATTACK里考验/检验的优先级)
AddModRPCHandler(RPC_NAMESPACE, "SyncJVMode", function(player, mode)
	if player == nil or player.components == nil then return end
	if mode == "justice" or mode == "valkyrie" then
		player.medal_jv_mode = mode
	end
end)

--客户端：全量发送"正义武神"模式
GLOBAL.SyncJVMode = function(mode)
	SendModRPCToServer(GetModRPC(RPC_NAMESPACE, "SyncJVMode"), mode)
end
