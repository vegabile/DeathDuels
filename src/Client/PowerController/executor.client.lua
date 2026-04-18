local PowerController = require(script.Parent)

--// Effects self-register when their module is required. Require them here so
--// registration happens before .start() listens.
require(script.Parent.Effects.Reveal)
require(script.Parent.Effects.Blind)

PowerController.start()
