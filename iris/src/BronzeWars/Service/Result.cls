Class BronzeWars.Service.Result Extends %RegisteredObject
{

ClassMethod Success(status As %Integer, data As %DynamicObject = "") As %DynamicObject
{
    set result = {"ok":true,"status":(status)}
    if $isobject(data) do result.%Set("data", data)
    return result
}

ClassMethod Error(status As %Integer, code As %String, message As %String, details As %DynamicArray = "") As %DynamicObject
{
    set result = {"ok":false,"status":(status),"code":(code),"message":(message)}
    if $isobject(details), (details.%Size() > 0) do result.%Set("details", details)
    return result
}

ClassMethod InternalError(status As %Status = 1) As %DynamicObject
{
    if $SYSTEM.Status.IsError(status) do $SYSTEM.Status.DisplayError(status)
    return ..Error(500, "INTERNAL_ERROR", "Se ha producido un error interno.")
}

}
