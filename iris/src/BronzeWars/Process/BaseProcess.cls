Class BronzeWars.Process.BaseProcess Extends Ens.BusinessProcess [ Abstract ]
{

Parameter ALLOWEDACTIONS = "";
Parameter OPERATION = "Data Operation";

Method OnRequest(request As BronzeWars.Message.Request, Output response As BronzeWars.Message.Response) As %Status
{
    if '..IsAllowed(request.Action) return ..SetError(.response, 500, "UNSUPPORTED_ACTION", "La operacion solicitada no esta configurada.")
    return ..SendToOperation(request, .response)
}

Method IsAllowed(action As %String) As %Boolean
{
    return $listfind($listfromstring(..#ALLOWEDACTIONS, ","), action) > 0
}

Method SendToOperation(request As BronzeWars.Message.Request, Output response As BronzeWars.Message.Response) As %Status
{
    return ..SendRequestSync(..#OPERATION, request, .response)
}

Method SetError(Output response As BronzeWars.Message.Response, status As %Integer, code As %String, message As %String) As %Status
{
    set result = ##class(BronzeWars.Service.Result).Error(status, code, message)
    set response = ##class(BronzeWars.Message.Response).FromResult(result)
    return $$$OK
}

Method OnResponse(request As %Persistent, ByRef response As %Persistent, callrequest As %Persistent, callresponse As %Persistent, pCompletionKey As %String) As %Status
{
    return $$$OK
}

}
