

export type ProfileEntry = {
	id: string,
	releaseTime: number?,
}

export type ProfileTable = { [string]: { [string]: ProfileEntry } }

local AnimationProfile = {}

function AnimationProfile.resolve(
	toolName: string,
	profiles: ProfileTable?,
	animationType: string
): ProfileEntry?
	if type(profiles) ~= "table" then
		warn(`[AnimationProfile] resolve called with non-table profiles for tool {toolName}`)
		return nil
	end

	local toolProfile = profiles[toolName]
	if not toolProfile then
		warn(`[AnimationProfile] no profile for tool {toolName}`)
		return nil
	end

	local entry = toolProfile[animationType]
	if not entry then
		warn(`[AnimationProfile] tool {toolName} has no {animationType} entry`)
		return nil
	end

	return entry
end

return AnimationProfile
