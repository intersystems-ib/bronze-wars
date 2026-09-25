Class BronzeWars.AI.Tools.Movement Extends %RegisteredObject
{

/// Description: Returns three prevalidated movement recommendations for every AI unit in a BronzeWars battle.
/// The compact units format is [unitId, unitType, offensive[x,y], neutral[x,y], defensive[x,y]].
/// Call this exactly once with the battleId supplied by the user, then call SubmitMovementChoices.
ClassMethod RecommendMovementOptions(battleId As %String) As %DynamicObject
{
    set result = {}
    set sc = ##class(BronzeWars.AI.MovementContext).Build(battleId, .context)
    if $SYSTEM.Status.IsError(sc) {
        do result.%Set("error", $SYSTEM.Status.GetErrorText(sc))
        return result
    }
    set sc = ##class(BronzeWars.AI.MovementRecommendationGenerator).Compact(context, .result)
    if $SYSTEM.Status.IsError(sc) {
        set result = {"error":($SYSTEM.Status.GetErrorText(sc))}
    }
    return result
}

/// Description: Submits the selected movement stance for every AI unit.
/// choices must contain one unitId:stance item per recommended unit, separated by commas, where stance is O, N, or D.
/// Call this after RecommendMovementOptions instead of returning a textual answer.
ClassMethod SubmitMovementChoices(battleId As %String, choices As %String) As %DynamicObject
{
    set result = {"accepted":false}
    set selected = ##class(%DynamicArray).%New()
    for index = 1:1:$length(choices, ",") {
        set item = $zstrip($piece(choices, ",", index), "<>W")
        set unitId = $zstrip($piece(item, ":", 1), "<>W")
        set stance = $zconvert($zstrip($piece(item, ":", 2), "<>W"), "U")
        if (unitId = "") || ((stance '= "O") && (stance '= "N") && (stance '= "D")) || ($piece(item, ":", 3) '= "") {
            do result.%Set("error", "choices must use the compact unitId:stance format")
            return result
        }
        set choice = ##class(%DynamicArray).%New()
        do choice.%Push(+unitId), choice.%Push(stance), selected.%Push(choice)
    }
    if selected.%Size() = 0 {
        do result.%Set("error", "choices must contain at least one selection")
        return result
    }
    do ##class(BronzeWars.AI.MovementSubmission).Store(battleId, selected)
    set result.accepted = 1
    set result.count = selected.%Size()
    return result
}

}
