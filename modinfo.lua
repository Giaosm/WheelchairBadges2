name = "坐着轮椅玩勋章2"
description = [[勋章不用手换、答题不用打转，轮椅一推就到位，懒人必备！]]
author = "哇唧唧哇"

version = "0.0.4"--整体.大章节.小章节.优化、修Bug

api_version = 10

dont_starve_compatible = true
reign_of_giants_compatible = true
dst_compatible = true
restart_required = false
all_clients_require_mod = true--所有客户端都要装
icon = "modicon.tex"
icon_atlas = "modicon.xml"
server_filter_tags = {"轮椅","勋章辅助","medal"}

priority = -10002--比能力勋章(-10001)晚加载

forumthread = ""

local function Subtitle(name)
	return {
		name = name,
		label = name,
		options = { {description = "", data = false}, },
		default = false,
	}
end

configuration_options =
{
	Subtitle("基础"),
	{
		name = "medal_ui_key",
		label = "轮椅开关快捷键",
		hover = "游戏内按此键开关轮椅开关UI。忘记快捷键时可在控制台输入 c_medalkey() 重置为关闭，届时暂停菜单会出现入口按钮。",
		options =
		{
			{description = "关闭", data = false, hover = "禁用快捷键，只能通过暂停菜单按钮打开UI"},
			{description = "R", data = 114, hover = "按R键开关UI"},	--KEY_R
			{description = "O", data = 111, hover = "按O键开关UI"},	--KEY_O
			{description = "G", data = 103, hover = "按G键开关UI"},	--KEY_G
			{description = "H", data = 104, hover = "按H键开关UI"},	--KEY_H
			{description = "J", data = 106, hover = "按J键开关UI"},	--KEY_J
			{description = "K", data = 107, hover = "按K键开关UI"},	--KEY_K
			{description = "L", data = 108, hover = "按L键开关UI"},	--KEY_L
			{description = "X", data = 120, hover = "按X键开关UI"},	--KEY_X
			{description = "N", data = 110, hover = "按N键开关UI"},	--KEY_N
			{description = "F1", data = 282, hover = "按F1键开关UI"},	--KEY_F1
			{description = "F2", data = 283, hover = "按F2键开关UI"},	--KEY_F2
			{description = "F3", data = 284, hover = "按F3键开关UI"},	--KEY_F3
			{description = "F4", data = 285, hover = "按F4键开关UI"},	--KEY_F4
			{description = "F5", data = 286, hover = "按F5键开关UI"},	--KEY_F5
			{description = "F6", data = 287, hover = "按F6键开关UI"},	--KEY_F6
			{description = "F7", data = 288, hover = "按F7键开关UI"},	--KEY_F7
			{description = "F8", data = 289, hover = "按F8键开关UI"},	--KEY_F8
			{description = "F9", data = 290, hover = "按F9键开关UI"},	--KEY_F9
			{description = "F10", data = 291, hover = "按F10键开关UI"},	--KEY_F10
			{description = "F11", data = 292, hover = "按F11键开关UI"},	--KEY_F11
			{description = "F12", data = 293, hover = "按F12键开关UI"},	--KEY_F12
		},
		default = false,
	},
	Subtitle("调试"),
	{
		name = "debug_switch",
		label = "调试日志",
		options =
		{
			{description = "关闭", data = false},
			{description = "开启", data = true},
		},
		default = false,
	},
}
