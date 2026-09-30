Class BronzeWars.Interop.Client Extends %RegisteredObject
{

ClassMethod Invoke(serviceName As %String, action As %String, payload As %DynamicObject = "", simulateFailure As %Boolean = 0) As %DynamicObject
{
    if '$isobject(payload) set payload = {}
    set request = ##class(BronzeWars.Message.Request).%New()
    set request.Action = action
    set request.PayloadJSON = payload.%ToJSON()
    set request.SimulateFailure = simulateFailure

    set sc = ##class(Ens.Director).CreateBusinessService(serviceName, .service)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    set sc = service.ProcessInput(request, .response)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    if '$isobject(response) return ##class(BronzeWars.Service.Result).InternalError()

    set result = ""
    try {
        set result = response.Result()
    } catch exception {
        set result = ##class(BronzeWars.Service.Result).InternalError(exception.AsStatus())
    }
    return result
}

ClassMethod ListUnitTypes() As %DynamicObject
{
    return ..Invoke("Unit Type Service", "LIST_UNIT_TYPES")
}

ClassMethod CreateBattle(input As %DynamicObject) As %DynamicObject
{
    return ..Invoke("Battle Service", "CREATE_BATTLE", input)
}

ClassMethod GetBattle(battleId As %String) As %DynamicObject
{
    return ..Invoke("Battle Service", "GET_BATTLE", {"battleId":(battleId)})
}

ClassMethod GetDeployment(battleId As %String) As %DynamicObject
{
    return ..Invoke("Deployment Service", "GET_DEPLOYMENT", {"battleId":(battleId)})
}

ClassMethod PlaceUnit(battleId As %String, unitId As %String, x As %Integer, y As %Integer) As %DynamicObject
{
    return ..Invoke("Deployment Service", "PLACE_UNIT", {"battleId":(battleId),"unitId":(unitId),"x":(x),"y":(y)})
}

ClassMethod StartBattle(battleId As %String, simulateFailure As %Boolean = 0) As %DynamicObject
{
    return ..Invoke("Battle Service", "START_BATTLE", {"battleId":(battleId)}, simulateFailure)
}

ClassMethod MoveUnit(battleId As %String, unitId As %String, x As %Integer, y As %Integer) As %DynamicObject
{
    return ..Invoke("Battle Service", "MOVE_UNIT", {"battleId":(battleId),"unitId":(unitId),"x":(x),"y":(y)})
}

ClassMethod AttackUnit(battleId As %String, unitId As %String, targetUnitId As %String) As %DynamicObject
{
    return ..Invoke("Battle Service", "ATTACK_UNIT", {"battleId":(battleId),"unitId":(unitId),"targetUnitId":(targetUnitId)})
}

ClassMethod NextTurn(battleId As %String, confirmIncomplete As %Boolean = 0) As %DynamicObject
{
    return ..Invoke("Battle Service", "NEXT_TURN", {"battleId":(battleId),"confirmIncomplete":(confirmIncomplete)})
}

ClassMethod SurrenderBattle(battleId As %String) As %DynamicObject
{
    return ..Invoke("Battle Service", "SURRENDER_BATTLE", {"battleId":(battleId),"side":"HUMAN"})
}

}
