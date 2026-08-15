--制作栏重建优化(客户端)：关闭时只轻量更新固定配方，打开时才全量重建+补刷，避免卡顿和残留。
--仅跳过专用服务器(无UI)。不能用GetIsClient()判断，本地主机上它返回false会导致patch失效。
if GLOBAL.TheNet == nil or GLOBAL.TheNet:IsDedicated() then return end

--固定配方缓存(关闭时轻量更新用)，ActivePinBar记最新pinbar实例，避免闭包累积泄漏。
local PinnedRecipes = {}
local ActivePinBar = nil

local function CraftingMenuHudPatch(self)
	if self.__helper_rebuild_patched then return end
	self.__helper_rebuild_patched = true

	local isfirst = true

	local cmh_RebuildRecipes = self.RebuildRecipes
	function self:RebuildRecipes(...)
		if self:IsCraftingOpen() or isfirst then
			return cmh_RebuildRecipes(self, ...)
		end

		local player = ThePlayer
		local builder = player ~= nil and player.replica ~= nil and player.replica.builder or nil
		if builder == nil then return end
		local freecrafting = builder:IsFreeBuildMode()
		for _, rec in pairs(PinnedRecipes) do
			if IsRecipeValid(rec.name) then
				if self.valid_recipes[rec.name] == nil then
					self.valid_recipes[rec.name] = { recipe = rec, meta = {} }
				end

				local meta = self.valid_recipes[rec.name].meta
				local is_build_tag_restricted = not builder:CanLearn(rec.name)
				local knows_recipe = builder:KnowsRecipe(rec)
				if knows_recipe or freecrafting then
					if builder:IsBuildBuffered(rec.name) and not is_build_tag_restricted then
						meta.can_build = true
						meta.build_state = "buffered"
					elseif freecrafting then
						meta.can_build = true
						meta.build_state = "freecrafting"
					elseif knows_recipe then
						meta.can_build = builder:HasIngredients(rec)
						meta.build_state = meta.can_build and "has_ingredients" or "no_ingredients"
					else
						meta.can_build = false
						meta.build_state = "hide"
					end
				else
					meta.can_build = false
					meta.build_state = "hide"
				end
			end
		end
	end

	local cmh_Open = self.Open
	function self:Open(...)
		local result = cmh_Open(self, ...)

		--打开时补刷关闭期间积压的刷新，清残留
		if self.waittoupdate then
			self.needtoupdate = true
			self.tech_tree_changed = self.waittorefresh
			self:OnUpdate()
		end
		return result
	end

	function self:OnUpdate(dt)
		if self.needtoupdate then
			self:RebuildRecipes()
			if self:IsCraftingOpen() or isfirst then
				isfirst = false
				self.craftingmenu:Refresh(self.tech_tree_changed)
			else
				self.waittoupdate = self.needtoupdate
				self.waittorefresh = self.tech_tree_changed
			end
			self.pinbar:Refresh()

			self.needtoupdate = false
			self.tech_tree_changed = false
		end

		self:RefreshCraftingHelpText()
	end
end

local function CraftingMenuPinBarPatch(self)
	if self.__helper_pinbar_patched then return end
	self.__helper_pinbar_patched = true
	ActivePinBar = self

	local cmbp_RefreshPinnedRecipes = self.RefreshPinnedRecipes
	function self:RefreshPinnedRecipes(...)
		local t = cmbp_RefreshPinnedRecipes(self, ...)
		local profile = TheCraftingMenuProfile
		if profile == nil then return t end
		local pinbar_recipes = profile:GetPinnedRecipes()
		PinnedRecipes = {}
		for _, v in pairs(pinbar_recipes) do
			if v and v.recipe_name then
				PinnedRecipes[v.recipe_name] = AllRecipes[v.recipe_name]
			end
		end
		return t
	end
end

--进世界时收集固定配方(关闭时轻量更新用)
env.AddPrefabPostInit("world", function(world)
	world:ListenForEvent("playeractivated", function(_, player)
		if ActivePinBar ~= nil and ActivePinBar.owner == player then
			ActivePinBar:RefreshPinnedRecipes()
		end
	end)
end)

env.AddClassPostConstruct("widgets/redux/craftingmenu_hud", CraftingMenuHudPatch)
env.AddClassPostConstruct("widgets/redux/craftingmenu_pinbar", CraftingMenuPinBarPatch)
