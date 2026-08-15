name = "坐着轮椅玩勋章"
description = [[制作中....]]
author = "哇唧唧哇"

version = "0.0.1"--整体.大章节.小章节.优化、修Bug

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
	Subtitle("调试"),
	{
		name = "debug_switch",
		label = "调试日志",
		hover = "是否打印本Mod的调试信息，关闭时零开销",
		options =
		{
			{description = "关闭", data = false, hover = "关闭调试信息(推荐)"},
			{description = "开启", data = true, hover = "开启调试信息"},
		},
		default = false,
	},
}
