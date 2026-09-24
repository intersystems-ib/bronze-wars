Class BronzeWars.Operation.LLMOperation Extends Ens.BusinessOperation
{

Parameter ADAPTER = "";
Parameter INVOCATION = "Queue";

Method Handle(pRequest As BronzeWars.Message.Request, Output pResponse As BronzeWars.Message.Response) As %Status
{
    if (pRequest.Action '= "PLAN_AI_ARMY") && (pRequest.Action '= "PLAN_AI_DEPLOYMENT") {
        set pResponse = ##class(BronzeWars.Message.Response).FromResult(##class(BronzeWars.Service.Result).Error(500, "UNSUPPORTED_ACTION", "La operacion de IA no admite esta accion."))
        return $$$OK
    }

    set result = ""
    try {
        set body = pRequest.Payload()
        set model = $system.Util.GetEnviron("BRONZEWARS_LLM_MODEL")
        if model = "" set model = "llama-3.1-8b-instruct"

        set baseURL = $system.Util.GetEnviron("BRONZEWARS_LLM_BASE_URL")
        if baseURL = "" set baseURL = "http://llama:8000/v1"

        set apiKey = $system.Util.GetEnviron("BRONZEWARS_LLM_API_KEY")
        if apiKey = "" set apiKey = "not-needed"
        set settings = {"base_url":(baseURL),"api_key":(apiKey)}
        set provider = ##class(%AI.Provider).Create("openai", settings)
        set sc = provider.ValidateConfig()
        if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)

        set messages = body.messages
        if body.%IsDefined("response_format") {
            set responseFormat = body.%Get("response_format")
            set jsonSchema = responseFormat.%Get("json_schema")
            set schema = jsonSchema.%Get("schema").%ToJSON()
            do messages.%Push({"role":"system","content":("Respeta exactamente este esquema JSON: " _ schema)})
        }
        set response = provider.ChatComplete(model, messages, body.temperature, body.%Get("max_tokens"))
        set content = response.Content
        set result = ##class(BronzeWars.Service.Result).Success(200, {"content":(content),"model":(model)})
    } catch exception {
        set diagnostic = exception.DisplayString()
        $$$LOGERROR("LLM deployment request failed: " _ diagnostic)
        set result = ##class(BronzeWars.Service.Result).Error(503, "LLM_UNAVAILABLE", "El comandante LLM no ha podido generar un despliegue.")
    }
    set pResponse = ##class(BronzeWars.Message.Response).FromResult(result)
    return $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="BronzeWars.Message.Request">
    <Method>Handle</Method>
  </MapItem>
</MapItems>
}

}
