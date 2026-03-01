local ClientEventBus = require(script.Parent.Parent.ClientEventBus)

ClientEventBus:Connect("RequestInputConnection", function(inputFlag: string, scriptConnection: RBXScriptSignal)
    local CentralInputHandler = require(script.Parent)
    CentralInputHandler.addInputConnection(inputFlag, scriptConnection)
end)

ClientEventBus:Connect("RequestInputDisconnection", function(inputFlag: string)
    local CentralInputHandler = require(script.Parent)
    CentralInputHandler.removeInputConnection(inputFlag)
end)