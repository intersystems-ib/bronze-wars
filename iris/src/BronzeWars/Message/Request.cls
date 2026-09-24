Class BronzeWars.Message.Request Extends Ens.Request
{

Property Action As %String(MAXLEN = 40) [ Required ];
Property PayloadJSON As %String(MAXLEN = 1000000) [ InitialExpression = "{}", Required ];
Property SimulateFailure As %Boolean [ InitialExpression = 0 ];

Method Payload() As %DynamicObject
{
    return ##class(%DynamicObject).%FromJSON(..PayloadJSON)
}

}
