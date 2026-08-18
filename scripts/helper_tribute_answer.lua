--奉纳透视：服务端同步奉纳盒答案，客户端按开关在填答案格内半透明显示图标。
--答案用net_string显式指定dirty事件名同步，绕开SetPristine后无法新增网络变量的限制。
AddPrefabPostInit("medal_pay_tribute_box", function(inst)
	if inst.medal_cheat_answer == nil then
		inst.medal_cheat_answer = GLOBAL.net_string(inst.GUID, "medal_cheat_answer", "medal_cheat_answerdirty")
	end
	if not GLOBAL.TheNet:GetIsServer() then return end
	inst:DoTaskInTime(1, function()--等tribute_answer生成后再同步
		if inst.tribute_answer and inst.medal_cheat_answer then
			inst.medal_cheat_answer:set(GLOBAL.json.encode({ ans = inst.tribute_answer }))
		end
	end)
end)

if not GLOBAL.TheNet:IsDedicated() then
	local GLOBAL_Image = GLOBAL.require("widgets/image")
	local GLOBAL_Widget = GLOBAL.require("widgets/widget")

	local function GetVeggiePrefab(id)
		if GLOBAL.GetPayTributeData then return GLOBAL.GetPayTributeData(id) end
		return nil
	end

	AddClassPostConstruct("widgets/containerwidget", function(self)
		local function UpdateTributeHints(container)
			if not (self.tribute_hints and container and container.medal_cheat_answer) then return end
			local data_str = container.medal_cheat_answer:value()
			if data_str == nil or data_str == "" then return end
			local ok, data = pcall(GLOBAL.json.decode, data_str)
			if not (ok and data and data.ans) then return end
			self.tribute_hints:KillAllChildren()
			for i = 1, 4 do
				local prefab = GetVeggiePrefab(data.ans[i])
				if prefab and self.inv[i] then
					local hint = self.tribute_hints:AddChild(GLOBAL_Image(GLOBAL.GetInventoryItemAtlas(prefab..".tex"), prefab..".tex"))
					local pos = self.inv[i]:GetPosition()
					hint:SetPosition(pos.x, pos.y, 0)--居中于格子
					hint:SetScale(0.5, 0.5)
					hint:SetTint(1, 1, 1, 0.4)--半透明
					hint:SetClickable(false)
				end
			end
		end

		local old_Open = self.Open
		self.Open = function(self, container, doer, ...)
			old_Open(self, container, doer, ...)
			if container and container.prefab == "medal_pay_tribute_box" then
				if not (GLOBAL.IsTributeAnswerEnabled and GLOBAL.IsTributeAnswerEnabled()) then return end
				if self.tribute_hints then
					self.tribute_hints:Kill()
					self.tribute_hints = nil
				end
				self.tribute_hints = self:AddChild(GLOBAL_Widget("TRIBUTE_HINTS"))
				self.tribute_hints:MoveToFront()
				UpdateTributeHints(container)
				self._on_tribute_dirty = function() UpdateTributeHints(container) end
				self._tribute_container = container
				self.inst:ListenForEvent("medal_cheat_answerdirty", self._on_tribute_dirty, container)
			end
		end

		local old_Close = self.Close
		self.Close = function(self, ...)
			if self._on_tribute_dirty and self._tribute_container then
				self.inst:RemoveEventCallback("medal_cheat_answerdirty", self._on_tribute_dirty, self._tribute_container)
				self._on_tribute_dirty = nil
				self._tribute_container = nil
			end
			if self.tribute_hints then
				self.tribute_hints:Kill()
				self.tribute_hints = nil
			end
			return old_Close(self, ...)
		end
	end)
end