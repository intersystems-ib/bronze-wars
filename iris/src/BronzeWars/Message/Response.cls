Class BronzeWars.Message.Response Extends Ens.Response
{

Property ResultJSON As %String(MAXLEN = 1000000) [ Required ];

ClassMethod FromResult(result As %DynamicObject) As BronzeWars.Message.Response
{
    set response = ..%New()
    set response.ResultJSON = result.%ToJSON()
    return response
}

Method Result() As %DynamicObject
{
    return ##class(%DynamicObject).%FromJSON(..ResultJSON)
}

}
