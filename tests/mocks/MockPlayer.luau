local MockPlayer = {}

function MockPlayer.new(name, userId)
	return {
		Name = name,
		UserId = userId or 1,
	}
end

return MockPlayer
