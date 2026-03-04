local dataServiceSpec = require("./DataService/DataService.spec")
dataServiceSpec()

local knifeStateMachineSpec = require("./Knife/KnifeStateMachine.spec")
knifeStateMachineSpec()

local payloadValidatorSpec = require("./Knife/PayloadValidator.spec")
payloadValidatorSpec()

local knifeServiceSpec = require("./KnifeService/KnifeService.spec")
knifeServiceSpec()

local centralInputHandlerSpec = require("./CentralInputHandler/CentralInputHandler.spec")
centralInputHandlerSpec()
