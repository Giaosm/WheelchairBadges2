--调试日志(开关关闭时第一行return，零开销)
function HelperDebug(...)
	if not TUNING.HELPER_DEBUG_SWITCH then return end
	print("[坐着轮椅玩勋章|调试] " .. string.format(...))
end
