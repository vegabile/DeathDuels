local CancellationToken = {}

export type Token = {
	cancelled: boolean,
}

function CancellationToken.new(): Token
	return {
		cancelled = false,
	}
end

function CancellationToken.cancel(token: Token?)
	if token then
		token.cancelled = true
	end
end

function CancellationToken.delay(token: Token, duration: number, callback: () -> ())
	task.spawn(function()
		if duration > 0 then
			task.wait(duration)
		end
		if token.cancelled then
			return
		end
		callback()
	end)
end

return CancellationToken
