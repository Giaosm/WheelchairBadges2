--轮椅开关配置的服务端存档(玩家组件)：组件数据随玩家存档迁移，换世界/进出洞穴/重连都不丢
--逻辑层仍直接读player上的同名字段，这里只负责存档与恢复，避免改动所有读取点
local FIELDS = {
	{ "group_enabled", "medal_group_enabled" },--组开关
	{ "forced_keep", "medal_forced_keep" },--强制保留勋章
	{ "autorepair", "medal_autorepair" },--自动补充耐久阈值
	{ "jv_mode", "medal_jv_mode" },--正义武神模式
}

local MedalSettings = Class(function(self, inst)
	self.inst = inst
end)

function MedalSettings:OnSave()
	local data = {}
	for _, v in ipairs(FIELDS) do
		data[v[1]] = self.inst[v[2]]
	end
	return data
end

function MedalSettings:OnLoad(data)
	if data == nil then return end
	for _, v in ipairs(FIELDS) do
		if data[v[1]] ~= nil then
			self.inst[v[2]] = data[v[1]]
		end
	end
end

return MedalSettings
