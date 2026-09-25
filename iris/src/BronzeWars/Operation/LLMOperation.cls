Class BronzeWars.Operation.LLMOperation Extends Ens.BusinessOperation
{

Parameter ADAPTER = "";
Parameter INVOCATION = "Queue";

Method Handle(pRequest As BronzeWars.Message.Request, Output pResponse As BronzeWars.Message.Response) As %Status
{
    if (pRequest.Action '= "PLAN_AI_ARMY") && (pRequest.Action '= "PLAN_AI_DEPLOYMENT") && (pRequest.Action '= "PLAN_AI_MOVEMENT") {
        set pResponse = ##class(BronzeWars.Message.Response).FromResult(##class(BronzeWars.Service.Result).Error(500, "UNSUPPORTED_ACTION", "La operacion de IA no admite esta accion."))
        return $$$OK
    }

    set result = ""
    try {
        set body = pRequest.Payload()
        set model = ##class(BronzeWars.AI.Agent.Movement).#MODEL

        set provider = ##class(BronzeWars.AI.Agent.Movement).CreateProvider()
        set sc = provider.ValidateConfig()
        if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)

        if pRequest.Action = "PLAN_AI_MOVEMENT" {
            set agent = ##class(BronzeWars.AI.Agent.Movement).%New(provider)
            set agent.Model = model
            set agent.Temperature = 0.1
            set agent.MaxIterations = 2
            set sc = agent.%Init()
            if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
            set sc = agent.UseToolSet("BronzeWars.AI.ToolSets.Movement")
            if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
            do ##class(BronzeWars.AI.MovementSubmission).Clear(body.battleId)
            set sessionConfig = {
                "max_iterations": (agent.MaxIterations),
                "max_tokens": (##class(BronzeWars.AI.Agent.Movement).#MaxTokens),
                "top_p": (##class(BronzeWars.AI.Agent.Movement).#TopP)
            }
            set session = agent.CreateSession(sessionConfig)
            set response = agent.Run(session, body.goal, agent.MaxIterations)
            set sc = ##class(BronzeWars.AI.MovementSubmission).Get(body.battleId, .choices)
            if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
            set content = {"choices":(choices)}.%ToJSON()
            do ##class(BronzeWars.AI.MovementSubmission).Clear(body.battleId)
            set result = ##class(BronzeWars.Service.Result).Success(200, {"content":(content),"model":(model),"mode":"AI_HUB_AGENT","toolSet":"BronzeWars.AI.ToolSets.Movement"})
        } else {
            set messages = body.messages
            if body.%IsDefined("response_format") {
                set responseFormat = body.%Get("response_format")
                set jsonSchema = responseFormat.%Get("json_schema")
                set schema = jsonSchema.%Get("schema").%ToJSON()
                do messages.%Push({"role":"system","content":("Respeta exactamente este esquema JSON: " _ schema)})
            }
            set maxTokens = body.%Get("max_tokens")
            if maxTokens = "" set maxTokens = ##class(BronzeWars.AI.Agent.Movement).#MaxTokens
            set response = provider.ChatComplete(model, messages, body.temperature, maxTokens, ##class(BronzeWars.AI.Agent.Movement).#TopP)
            set content = response.Content
            set result = ##class(BronzeWars.Service.Result).Success(200, {"content":(content),"model":(model),"mode":"CHAT_COMPLETE"})
        }
    } catch exception {
        set diagnostic = exception.DisplayString()
        $$$LOGERROR("LLM commander request failed: " _ diagnostic)
        set result = ##class(BronzeWars.Service.Result).Error(503, "LLM_UNAVAILABLE", "El comandante LLM no ha podido completar la decision tactica.")
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
