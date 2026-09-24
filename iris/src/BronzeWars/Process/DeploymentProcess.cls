Class BronzeWars.Process.DeploymentProcess Extends BronzeWars.Process.BaseProcess
{

Parameter ALLOWEDACTIONS = "GET_DEPLOYMENT,PLACE_UNIT";

Method OnRequest(request As BronzeWars.Message.Request, Output response As BronzeWars.Message.Response) As %Status
{
    if '..IsAllowed(request.Action) return ..SetError(.response, 500, "UNSUPPORTED_ACTION", "La operacion solicitada no esta configurada.")
    set payload = request.Payload()

    if request.Action = "PLACE_UNIT" {
        lock +^BronzeWarsBattleLock(payload.battleId):5
        if '$test return ..SetError(.response, 409, "BATTLE_BUSY", "La batalla esta siendo modificada por otra peticion.")
        set sc = ..SendToOperation(request, .response)
        lock -^BronzeWarsBattleLock(payload.battleId)
        return sc
    }
    return ..SendToOperation(request, .response)
}

}
