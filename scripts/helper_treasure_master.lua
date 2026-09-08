--寻宝大师：部署探测仪后，地图标出宝藏位置并生成半透明投影，不用再靠箭头反复定位。
--开关在游戏内"轮椅开关"UI(组treasureMaster)，经RPC同步到服务端player.medal_group_enabled。

local function IsTreasureMasterOn(doer)
	return doer
		and doer.medal_group_enabled ~= nil
		and doer.medal_group_enabled["treasureMaster"] == true
end

local SIGN_TIME = (TUNING_MEDAL and TUNING_MEDAL.MEDAL_TREASURE_SIGN_TIME) or 60--标记/投影存在时长

--藏宝点半透明投影(通用helper_projection，调用方设置外观)
local function SpawnTreasureGhost(x, z)
	local ghost = SpawnPrefab("helper_projection")
	if ghost then
		ghost.AnimState:SetBank("medal_treasure")
		ghost.AnimState:SetBuild("medal_treasure")
		ghost.AnimState:PlayAnimation("idle_3", true)
		ghost.Transform:SetPosition(x, 0, z)
		ghost:DoTaskInTime(SIGN_TIME, ghost.Remove)
	end
	return ghost
end

--生成并记录到self[key]，实体消失时自动清空引用
local function SpawnAndRecord(self, key, spawnfn)
	local ent = spawnfn()
	if ent then
		self[key] = ent
		ent:ListenForEvent("onremove", function()
			if self[key] == ent then self[key] = nil end
		end)
	end
end

--清理标记与投影(真实宝藏生成前调用)
local function Cleanup(self)
	for _, key in ipairs({ "_helper_ghost", "_helper_sign" }) do
		local ent = self[key]
		if ent ~= nil then
			if ent:IsValid() then ent:Remove() end
			self[key] = nil
		end
	end
end

local function AddTreasureMaster(map)
	if map._helper_hooked then return end--防重复hook
	map._helper_hooked = true

	local _getPoint = map.getTreasurePoint
	map.getTreasurePoint = function(self, doer, resonator)
		local data = _getPoint(self, doer, resonator)
		--resonator非nil限定探测仪扫描(时空符文/预言不触发)；已近6格会直接挖出时不生成，避免多余
		if data and resonator ~= nil and IsTreasureMasterOn(doer) and data.worldid == TheShard:GetShardId()
			and resonator:GetDistanceSqToPoint(data.x, 0, data.z) >= 6*6 then
			--仍在(未到时)则不重复生成；消失后再次部署会重新生成
			local ghost, sign = self._helper_ghost, self._helper_sign
			if (ghost and ghost:IsValid()) or (sign and sign:IsValid()) then
				return data
			end
			SpawnAndRecord(self, "_helper_ghost", function() return SpawnTreasureGhost(data.x, data.z) end)
			SpawnAndRecord(self, "_helper_sign", function()
				local s = SpawnPrefab("medal_treasure_sign")
				if s then s.Transform:SetPosition(data.x, 0, data.z) end
				return s
			end)
			--揭示区域，否则未探索的迷雾下地图看不到标记(参考能力勋章预言水晶球)
			if doer.player_classified ~= nil then
				doer.player_classified.revealmapspot_worldx:set(data.x)
				doer.player_classified.revealmapspot_worldz:set(data.z)
				doer:DoTaskInTime(4 * FRAMES, function()
					doer.player_classified.revealmapspotevent:push()
					doer.player_classified.MapExplorer:RevealArea(data.x, 0, data.z)
				end)
			end
		end
		return data
	end

	--真实宝藏生成前先清掉标记投影，避免重叠残留
	local function Wrap(fn)
		return function(self, ...)
			Cleanup(self)
			return fn(self, ...)
		end
	end
	if map.spawnTreasure then map.spawnTreasure = Wrap(map.spawnTreasure) end
	if map.runesSpawnTreasure then map.runesSpawnTreasure = Wrap(map.runesSpawnTreasure) end

	--藏宝图销毁时同步清理标记投影，避免闭包延迟持有已销毁实例(监听器随实例销毁自动释放)
	map:ListenForEvent("onremove", function()
		Cleanup(map)
	end)
end

--getTreasurePoint只在服务端藏宝图实例上存在，客户端天然跳过
for _, prefab in ipairs({ "medal_treasure_map", "medal_treasure_map_used", "medal_loss_treasure_map", "medal_loss_treasure_map_used" }) do
	AddPrefabPostInit(prefab, function(inst)
		if TheWorld.ismastersim and inst.getTreasurePoint then
			AddTreasureMaster(inst)
		end
	end)
end
