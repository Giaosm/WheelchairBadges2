--制作栏重建优化(客户端)：关闭时只轻量更新固定配方，打开时才全量重建+补刷，避免卡顿和残留。
--仅跳过专用服务器(无UI)：GetIsClient() 在本地主机返回 false，会让补丁整体失效。
if GLOBAL.TheNet == nil or GLOBAL.TheNet:IsDedicated() then return end

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
		--状态判定与官方 RebuildRecipes 一致(见 craftingmenu_hud.lua)
		local tech_trees = builder:GetTechTrees()
		local tech_trees_no_temp = builder:GetTechTreesNoTemp()
		local craftinglimits = builder:GetAllRecipeCraftingLimits()
		--cache 须独立表：KnowsRecipe 会往里写，传 GetTechTrees() 会污染 replica 数据
		local cached_should_hint, cached_tech_trees, cached_tech_trees_temp = {}, {}, {}
		--现读所有页固定配方(去重)：后 pin 的不触发 RefreshPinnedRecipes，关闭态翻页也不重建
		local pinned = {}
		for _, page in pairs(TheCraftingMenuProfile ~= nil and TheCraftingMenuProfile.pinned_pages or {}) do
			for _, pin in pairs(page) do
				if pin.recipe_name ~= nil then pinned[pin.recipe_name] = true end
			end
		end
		for name in pairs(pinned) do
			local rec = AllRecipes[name]
			if rec ~= nil and IsRecipeValid(rec.name) then
				if self.valid_recipes[rec.name] == nil then
					self.valid_recipes[rec.name] = { recipe = rec, meta = {} }
				end

				local meta = self.valid_recipes[rec.name].meta
				local knows_recipe = builder:KnowsRecipe(rec, nil, cached_tech_trees)
				local should_hint_recipe = cached_should_hint[rec.level]
				if should_hint_recipe == nil then
					should_hint_recipe = ShouldHintRecipe(rec.level, tech_trees)
					cached_should_hint[rec.level] = should_hint_recipe
				end
				local needs_unlocked_skin = rec.unlocks_from_skin ~= nil
				local has_unlocked_skin = false
				if needs_unlocked_skin and player.isplayer then
					local prefabskins = PREFAB_SKINS[rec.product]
					if prefabskins ~= nil then
						for _, skin in ipairs(prefabskins) do
							if TheInventory:CheckOwnership(skin) then
								has_unlocked_skin = true
								break
							end
						end
					end
				end

				meta.limitedamount = craftinglimits[rec.name]
				meta.hide_due_to_missing_skin = nil
				if needs_unlocked_skin and not has_unlocked_skin then
					meta.can_build = false
					meta.hide_due_to_missing_skin = true
					meta.build_state = "hide"
				elseif knows_recipe or should_hint_recipe or rec.force_hint or rec.always_allow_buffered_placer or freecrafting then
					local is_build_tag_restricted = not builder:CanLearn(rec.name)
					if builder:IsBuildBuffered(rec.name) and not is_build_tag_restricted then
						meta.can_build = true
						meta.build_state = "buffered"
					elseif freecrafting then
						meta.can_build = true
						meta.build_state = "freecrafting"
					elseif is_build_tag_restricted then
						meta.can_build = false
						meta.build_state = "hide"
					elseif knows_recipe then
						meta.can_build = builder:HasIngredients(rec)
						if not rec.nounlock and not builder:KnowsRecipe(rec, true, cached_tech_trees_temp) and CanPrototypeRecipe(rec.level, tech_trees_no_temp) then
							meta.build_state = "prototype"
						else
							meta.build_state = meta.can_build and "has_ingredients" or "no_ingredients"
						end
					elseif CanPrototypeRecipe(rec.level, tech_trees) then
						meta.can_build = builder:HasIngredients(rec)
						meta.build_state = rec.nounlock and (meta.can_build and "has_ingredients" or "no_ingredients") or "prototype"
					elseif rec.force_hint then
						meta.can_build = false
						meta.build_state = "hint"
					elseif rec.nounlock then
						meta.can_build = false
						meta.build_state = "hide"
					elseif should_hint_recipe then
						meta.can_build = false
						meta.build_state = "hint"
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
		--补刷关闭期间积压的刷新
		if self.waittoupdate then
			self.needtoupdate = true
			self.tech_tree_changed = self.waittorefresh
			self.waittoupdate = false
			self.waittorefresh = false
			self:OnUpdate()
		end
		return result
	end

	local cmh_OnUpdate = self.OnUpdate
	function self:OnUpdate(dt)
		if self.needtoupdate then
			if self:IsCraftingOpen() or isfirst then
				isfirst = false
				return cmh_OnUpdate(self, dt)
			end
			--关闭且非首次：只轻量重建，全量刷新推迟到打开
			self:RebuildRecipes()
			self.pinbar:Refresh()
			self.waittoupdate = true
			self.waittorefresh = self.tech_tree_changed
			self.needtoupdate = false
			self.tech_tree_changed = false
		end
		return cmh_OnUpdate(self, dt)--原实现兜底，不吞官方/其他mod后续逻辑
	end
end

env.AddClassPostConstruct("widgets/redux/craftingmenu_hud", CraftingMenuHudPatch)
