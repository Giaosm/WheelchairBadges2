--通用半透明投影prefab：外观由调用方设置(SetBank/SetBuild/PlayAnimation)，AnimState会同步到客户端。
--新增投影外观时：1.在下方assets加一行动画资源 2.调用方SpawnPrefab后设置外观即可，无需新建文件。
local assets =
{
	Asset("ANIM", "anim/medal_treasure.zip"),--寻宝大师藏宝点投影
}

local function fn()
	local inst = CreateEntity()
	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddNetwork()

	inst.persists = false--不存档，避免计时移除任务不跨存档导致残留

	--外观由调用方设置(此处不硬编码，保持通用壳)
	inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
	inst.AnimState:SetMultColour(1, 1, 1, 0.55)--半透明

	inst:AddTag("NOCLICK")
	inst:AddTag("FX")

	inst.entity:SetPristine()

	if not TheWorld.ismastersim then
		return inst
	end

	return inst
end

return Prefab("helper_projection", fn, assets)
