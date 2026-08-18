--轮椅开关RPC：客户端组开关同步到服务端
--用json字符串传输：直接发boolean会丢失false(服务端收到nil)，json可完整保留
local RPC_NAMESPACE = "Wheelchair_Medal"

--服务端：接收客户端全量组开关配置(json字符串)
AddModRPCHandler(RPC_NAMESPACE, "SyncGroupEnabled", function(player, settings_json)
	if player == nil or player.components == nil or type(settings_json) ~= "string" then return end
	local ok, cfg = pcall(GLOBAL.json.decode, settings_json)
	if not ok or type(cfg) ~= "table" then return end
	player.medal_group_enabled = cfg
	GLOBAL.RefreshPlayerMedalTags(player)
end)

--客户端：全量发送组开关配置
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
