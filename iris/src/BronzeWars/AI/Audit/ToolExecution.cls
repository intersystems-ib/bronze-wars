Class BronzeWars.AI.Audit.ToolExecution Extends %Persistent
{

Property Timestamp As %TimeStamp [ InitialExpression = {$ZDATETIME($HOROLOG, 3)} ];

Property CallId As %String(MAXLEN = 128) [ Required ];

Property ToolName As %String(MAXLEN = 128) [ Required ];

Property ArgumentsJSON As %String(MAXLEN = "");

Property MetadataJSON As %String(MAXLEN = "");

Property Success As %Boolean [ InitialExpression = 0 ];

Property DurationMs As %Integer [ InitialExpression = 0 ];

Property ResultJSON As %String(MAXLEN = "");

Property ErrorText As %String(MAXLEN = "");

Index CallIdIndex On CallId;

Index TimestampIndex On Timestamp;

}
