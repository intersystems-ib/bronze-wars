Include %AI

Class BronzeWars.AI.Policies.ToolAudit Extends %AI.Policy.Audit
{

Method %LogExecution(call As %DynamicObject, metadata As %DynamicObject, result As %DynamicObject, duration As %Integer, status As %Status) As %Status
{
    set log = ##class(BronzeWars.AI.Audit.ToolExecution).%New()
    set log.CallId = call.%Get("id")
    set log.ToolName = call.%Get("name")
    set log.Success = $SYSTEM.Status.IsOK(status)
    set log.DurationMs = duration

    if call.%IsDefined("arguments") {
        set arguments = call.%Get("arguments")
        set log.ArgumentsJSON = $select($isobject(arguments):arguments.%ToJSON(), 1:arguments)
    }
    if $isobject(metadata) set log.MetadataJSON = metadata.%ToJSON()
    if $isobject(result) {
        if result.%IsDefined("tool_name") set log.ToolName = result.%Get("tool_name")
        if result.%IsDefined("result_json") set log.ResultJSON = result.%Get("result_json")
        if (log.ResultJSON = "") set log.ResultJSON = result.%ToJSON()
    }
    if 'log.Success set log.ErrorText = $SYSTEM.Status.GetErrorText(status)

    return log.%Save()
}

}
