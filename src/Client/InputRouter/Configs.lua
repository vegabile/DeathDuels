return {
	DEBUG_MODE = false,

	KnifeBindings = {
		Stab = {
			actionName = "KnifeStab",
			keyboard = Enum.KeyCode.F,
			gamepad = Enum.KeyCode.ButtonL1,
			touchButton = true,
		},
		Throw = {
			actionName = "KnifeThrow",
			keyboard = Enum.KeyCode.E,
			gamepad = Enum.KeyCode.ButtonR1,
			touchButton = true,
		},
	},

	GunBindings = {
		Shoot = {
			actionName = "GunShoot",
			mouseButton = Enum.UserInputType.MouseButton1,
			gamepad = Enum.KeyCode.ButtonR2,
			touchButton = true,
		},
	},

	PowerBindings = {
		Activate = {
			actionName = "PowerActivate",
			keyboard = Enum.KeyCode.Q,
			gamepad = Enum.KeyCode.ButtonY,
			touchButton = false,
		},
	},
}
