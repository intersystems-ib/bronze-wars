Class BronzeWars.AI.MovementSubmission Extends %RegisteredObject
{

ClassMethod Clear(battleId As %String)
{
    kill ^||BronzeWarsMovementChoices(battleId)
}

ClassMethod Store(battleId As %String, choices As %DynamicArray)
{
    set ^||BronzeWarsMovementChoices(battleId) = choices.%ToJSON()
}

ClassMethod Get(battleId As %String, Output choices As %DynamicArray) As %Status
{
    set choices = ""
    if '$data(^||BronzeWarsMovementChoices(battleId)) return $$$ERROR($$$GeneralError, "AI Hub agent did not submit movement choices")
    try {
        set choices = ##class(%DynamicArray).%FromJSON(^||BronzeWarsMovementChoices(battleId))
    } catch exception {
        return exception.AsStatus()
    }
    return $$$OK
}

}
