--轮椅开关UI面板(客户端)
if GLOBAL.TheNet == nil or GLOBAL.TheNet:IsDedicated() then return end

local GLOBAL_Class = GLOBAL.Class
local GLOBAL_Screen = GLOBAL.require("widgets/screen")
local GLOBAL_Widget = GLOBAL.require("widgets/widget")
local GLOBAL_Image = GLOBAL.require("widgets/image")
local GLOBAL_Text = GLOBAL.require("widgets/text")
local GLOBAL_ImageButton = GLOBAL.require("widgets/imagebutton")
local GLOBAL_TEMPLATES = GLOBAL.require("widgets/redux/templates")

--勋章组列表(自动装备组，取helper_autoequip_actions.lua的name；特殊开关如autoexam自动答题走额外名字映射)
local UI_GROUP_ORDER = { "chopMedal", "minerMedal", "chefMedal", "handyMedal", "harvestMedal", "plantMedal", "wisdomMedal", "autoexam" }
--非自动装备组的开关中文名
local UI_EXTRA_NAMES = { autoexam = "自动答题" }
local UI_GROUPS = {}
for _, g in ipairs(UI_GROUP_ORDER) do
	local name = (HelperRules_AUTO_EQUIP_ACTIONS[g] and HelperRules_AUTO_EQUIP_ACTIONS[g].name)
		or UI_EXTRA_NAMES[g] or g
	table.insert(UI_GROUPS, { group = g, name = name })
end

--跨局存储：TheSim持久化(客户端本地，参考能力勋章medal_globalfn.lua)，统一存{group_enabled, medal_key}
local PERSIST_KEY = "helper_medal_ui_data"
local stored_data = { group_enabled = {}, medal_key = nil }
TheSim:GetPersistentString(PERSIST_KEY, function(success, str)
	if success and str then
		local ok, val = RunInSandbox(str)
		if ok and type(val) == "table" then
			stored_data = val
			if type(stored_data.group_enabled) ~= "table" then stored_data.group_enabled = {} end
		end
	end
end)
local function SavePersist()
	TheSim:SetPersistentString(PERSIST_KEY, DataDumper(stored_data, nil, true), false)
end

local function GetStoredConfig() return stored_data.group_enabled or {} end
local function SaveConfig(cfg) stored_data.group_enabled = cfg; SavePersist() end

--快捷键选项("global"跟随全局/false关闭/数字为具体键)
local MEDAL_KEY_OPTIONS = {
	{ text = "跟随全局", data = "global" },
	{ text = "关闭", data = false },
	{ text = "R", data = 114 }, { text = "O", data = 111 },
	{ text = "G", data = 103 }, { text = "H", data = 104 },
	{ text = "J", data = 106 }, { text = "K", data = 107 },
	{ text = "L", data = 108 }, { text = "X", data = 120 },
	{ text = "N", data = 110 },
	{ text = "F1", data = 282 }, { text = "F2", data = 283 },
	{ text = "F3", data = 284 }, { text = "F4", data = 285 },
	{ text = "F5", data = 286 }, { text = "F6", data = 287 },
	{ text = "F7", data = 288 }, { text = "F8", data = 289 },
	{ text = "F9", data = 290 }, { text = "F10", data = 291 },
	{ text = "F11", data = 292 }, { text = "F12", data = 293 },
}

local function GetMedalKey()
	local o = stored_data.medal_key
	if o == false or type(o) == "number" then return o end
	return TUNING.HELPER_MEDAL_UI_KEY
end
local function SaveMedalKeyOverride(data) stored_data.medal_key = data; SavePersist() end
--注意不能用 or "global"：medal_key为false时or会误判
local function GetMedalKeyOverride()
	if stored_data.medal_key == nil then return "global" end
	return stored_data.medal_key
end

local function IsGroupOn(cfg, group)
	return cfg[group] ~= false
end

--创建开/关箭头按钮，点击把组开关设为value
local function MakeArrowButton(self, parent, dir, x, y, group, value, cfg)
	local normal, over, disabled
	if dir == "left" then
		normal, over, disabled = "arrow2_left.tex", "arrow2_left_over.tex", "arrow_left_disabled.tex"
	else
		normal, over, disabled = "arrow2_right.tex", "arrow2_right_over.tex", "arrow_right_disabled.tex"
	end
	local btn = parent:AddChild(GLOBAL_ImageButton("images/global_redux.xml", normal, over, disabled))
	btn:SetPosition(x, y, 0)
	btn:SetScale(0.18)
	btn:SetText("")
	btn:SetOnClick(function()
		cfg[group] = value
		SaveConfig(cfg)
		self:UpdateButtons(cfg)
		GLOBAL.SyncGroupEnabled(cfg)--同步到服务端
	end)
	return btn
end

local MedalUIScreen = GLOBAL_Class(GLOBAL_Screen, function(self)
	GLOBAL_Screen._ctor(self, "MedalUIScreen")
	self.medal_ui_active = true

	local cfg = GetStoredConfig()

	--暗色背景(点击关闭)
	self.black = self:AddChild(GLOBAL_ImageButton("images/global.xml", "square.tex"))
	self.black.image:SetVRegPoint(GLOBAL.ANCHOR_MIDDLE)
	self.black.image:SetHRegPoint(GLOBAL.ANCHOR_MIDDLE)
	self.black.image:SetVAnchor(GLOBAL.ANCHOR_MIDDLE)
	self.black.image:SetHAnchor(GLOBAL.ANCHOR_MIDDLE)
	self.black.image:SetScaleMode(GLOBAL.SCALEMODE_FILLSCREEN)
	self.black.image:SetTint(0, 0, 0, 0.6)
	self.black:SetOnClick(function() self:Close() end)
	self.black:SetHelpTextMessage("")

	--主面板
	self.root = self:AddChild(GLOBAL_Widget("ROOT"))
	self.root:SetVAnchor(GLOBAL.ANCHOR_MIDDLE)
	self.root:SetHAnchor(GLOBAL.ANCHOR_MIDDLE)
	self.root:SetScaleMode(GLOBAL.SCALEMODE_PROPORTIONAL)

	self.bg = self.root:AddChild(GLOBAL_Image("images/skilltree.xml", "wilson_background_text.tex"))
	self.bg:ScaleToSize(1000, 700)

	self.title = self.root:AddChild(GLOBAL_Text(GLOBAL.BODYTEXTFONT, 34))
	self.title:SetString("轮椅开关")
	self.title:SetPosition(0, 235, 0)
	self.title:SetColour(1, 0.85, 0.3, 1)

	self.divider = self.root:AddChild(GLOBAL_Image("images/frontend_redux.xml", "achievements_wide_divider_top.tex"))
	self.divider:SetPosition(0, 215, 0)
	self.divider:ScaleToSize(900, 15)

	--每玩家快捷键选择器(右上角)
	self.key_spinner = self.root:AddChild(GLOBAL_TEMPLATES.LabelSpinner("快捷键", MEDAL_KEY_OPTIONS, 80, 100, 30, 8, GLOBAL.NEWFONT, 20, nil, nil, { 0, 0, 0, 1 }))
	self.key_spinner:SetPosition(270, 225, 0)
	self.key_spinner.spinner:SetTextColour(0, 0, 0, 1)
	self.key_spinner.spinner:SetSelected(GetMedalKeyOverride())
	self.key_spinner.spinner:SetOnChangedFn(function(data)
		SaveMedalKeyOverride(data)
		GLOBAL.ReRegisterMedalKey()
	end)

	--每个勋章组：名字 + 左箭头(关) + 状态 + 右箭头(开)，网格排布
	self.buttons = {}
	local SWITCH_START_X = -267
	local SWITCH_START_Y = 185
	local SWITCH_SPACING_X = 150
	local SWITCH_SPACING_Y = 50
	local SWITCH_PER_ROW = 5
	for idx, g in ipairs(UI_GROUPS) do
		local row = math.floor((idx - 1) / SWITCH_PER_ROW)
		local col = (idx - 1) % SWITCH_PER_ROW
		local x = SWITCH_START_X + col * SWITCH_SPACING_X
		local y = SWITCH_START_Y - row * SWITCH_SPACING_Y

		local name = self.root:AddChild(GLOBAL_Text(GLOBAL.NEWFONT, 24))
		name:SetString(g.name)
		name:SetPosition(x - 75, y, 0)
		name:SetColour(0, 0, 0, 1)

		local btn_off = MakeArrowButton(self, self.root, "left", x - 40, y, g.group, false, cfg)
		local btn_on = MakeArrowButton(self, self.root, "right", x + 10, y, g.group, true, cfg)

		local state = self.root:AddChild(GLOBAL_Text(GLOBAL.NEWFONT, 20))
		state:SetPosition(x - 15, y, 0)
		state:SetHAlign(GLOBAL.ANCHOR_MIDDLE)

		self.buttons[idx] = { g = g, btn_off = btn_off, btn_on = btn_on, name = name, state = state }
	end

	self:UpdateButtons(cfg)

	GLOBAL.SetAutopaused(true)
end)

function MedalUIScreen:OnControl(control, down)
	if MedalUIScreen._base.OnControl(self, control, down) then return true end
	if not down and control == GLOBAL.CONTROL_CANCEL then
		self:Close()
		return true
	end
	return false
end

function MedalUIScreen:UpdateButtons(cfg)
	for _, item in ipairs(self.buttons) do
		local on = IsGroupOn(cfg, item.g.group)
		item.state:SetString(on and "开" or "关")
		item.state:SetColour(on and 0.3 or 1, on and 1 or 0.3, on and 0.3 or 0.3, 1)
		--必须用Disable()/Enable()触发OnDisable切换禁用纹理，直接赋值enabled不刷新
		if on then
			item.btn_on:Disable()
			item.btn_off:Enable()
		else
			item.btn_off:Disable()
			item.btn_on:Enable()
		end
	end
end

function MedalUIScreen:Close()
	GLOBAL.SetAutopaused(false)
	TheFrontEnd:PopScreen(self)
end

--打字/输入状态检测(参考T键模组)：正在聊天/控制台/搜索栏等输入时不触发快捷键
local function IsTypingActive()
	local FE = TheFrontEnd
	if FE == nil then return false end
	--1. 屏幕名：聊天输入/控制台/调试菜单
	local screen = FE:GetActiveScreen()
	if screen ~= nil then
		local name = screen.name or ""
		if name == "ChatInputScreen" or name == "ConsoleScreen" or name == "DebugMenuScreen" then
			return true
		end
		--2. 屏幕上有编辑框
		if screen.edit_text ~= nil then return true end
	end
	--3. 引擎正强制处理文本输入(聊天/控制台/搜索栏等)
	if FE.forceProcessText == true and FE.textProcessorWidget ~= nil then return true end
	--4. 焦点控件链上有正在编辑的TextEdit(如制作面板搜索栏等自建输入框)
	local focus = FE:GetFocusWidget()
	local function FindEditing(widget, visited)
		if widget == nil or visited[widget] then return false end
		visited[widget] = true
		if widget.editing == true then return true end
		if FindEditing(widget.parent, visited) then return true end
		if widget.children then
			for _, child in ipairs(widget.children) do
				if FindEditing(child, visited) then return true end
			end
		end
		return false
	end
	if focus ~= nil and FindEditing(focus, {}) then return true end
	return false
end

GLOBAL.ToggleMedalUI = function()
	if IsTypingActive() then return end--正在打字输入时不触发快捷键
	local cur = TheFrontEnd:GetActiveScreen()
	if cur ~= nil and cur.medal_ui_active then
		cur:Close()
	else
		TheFrontEnd:PushScreen(MedalUIScreen())
	end
end

--暂停菜单入口按钮(仅快捷键关闭时显示，避免重复入口)
AddClassPostConstruct("screens/redux/pausescreen", function(self)
	local key = self.menu and GetMedalKey()
	if self.menu and (key == false or key == nil) then
		self.menu.helper_medal_btn = self.menu:AddItem("轮椅开关", function()
			self:unpause()
			TheFrontEnd:PushScreen(MedalUIScreen())
		end)
		self.menu.helper_medal_btn:SetScale(.7)
	end
end)

--快捷键注册(不能靠player==ThePlayer判断本地玩家：ThePlayer在postinit后才有值，故用标记防重复注册)
local medal_ui_key_registered = false
local medal_key_handler = nil
GLOBAL.ReRegisterMedalKey = function()
	if medal_key_handler ~= nil then
		medal_key_handler:Remove()
		medal_key_handler = nil
	end
	local key = GetMedalKey()
	if key ~= false and key ~= nil then
		medal_key_handler = TheInput:AddKeyDownHandler(key, function()
			GLOBAL.ToggleMedalUI()
		end)
	end
end
AddPlayerPostInit(function(player)
	if player == nil or not player:HasTag("player") or medal_ui_key_registered then return end
	medal_ui_key_registered = true
	GLOBAL.ReRegisterMedalKey()
	--进服同步配置到服务端(playeractivated后sender才是player，过早会收到userid)
	player:ListenForEvent("playeractivated", function()
		GLOBAL.SyncGroupEnabled(GetStoredConfig())
	end)
end)

--控制台命令：忘记快捷键时重置为关闭，使暂停菜单恢复入口
GLOBAL.c_medalkey = function()
	SaveMedalKeyOverride(false)
	GLOBAL.ReRegisterMedalKey()
	print("[轮椅开关] 快捷键已重置为关闭，请在暂停菜单中使用\"轮椅开关\"按钮重新设置")
end
