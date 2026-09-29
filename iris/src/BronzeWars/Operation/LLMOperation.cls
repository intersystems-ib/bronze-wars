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
        if pRequest.Action = "PLAN_AI_MOVEMENT" {
            set model = ##class(BronzeWars.AI.Agent.Movement).#MODEL
            set provider = ##class(BronzeWars.AI.Agent.Movement).CreateProvider()
            set sc = provider.ValidateConfig()
            if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
            set agent = ##class(BronzeWars.AI.Agent.Movement).%New(provider)
            set sc = agent.UseToolSet("BronzeWars.AI.ToolSets.BattleSituation")
            if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
            set session = agent.CreateSession({"model":(model)})
            set response = agent.Run(session, body.%Get("goal"), body.%Get("max_iterations"))
            set content = response.Content
            set result = ##class(BronzeWars.Service.Result).Success(200, {"content":(content),"model":(model),"mode":"AGENT_TOOLSET"})
            set pResponse = ##class(BronzeWars.Message.Response).FromResult(result)
            return $$$OK
        }
        if pRequest.Action = "PLAN_AI_DEPLOYMENT" {
            set model = ##class(BronzeWars.AI.Agent.Deployment).#MODEL
            set provider = ##class(BronzeWars.AI.Agent.Deployment).CreateProvider()
            set sc = provider.ValidateConfig()
            if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
            set agent = ##class(BronzeWars.AI.Agent.Deployment).%New(provider)
            set sc = agent.UseToolSet("BronzeWars.AI.ToolSets.DeploymentPositions")
            if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
            set session = agent.CreateSession({"model":(model)})
            set response = agent.Run(session, body.%Get("goal"), body.%Get("max_iterations"))
            set content = response.Content
            if '##class(BronzeWars.AI.DeploymentCommander).HasPlacementPayload(content) {
                set correction = "La respuesta anterior no cumple el formato. Responde ahora exclusivamente con el JSON compacto de placements [[unitId,x,y],...] usando las recommendedOptions ya consultadas para las " _ body.unitIds.%Size() _ " unidades. No incluyas explicaciones ni vuelvas a consultar tools."
                set response = agent.Chat(session, correction)
                set content = response.Content
            }
            set result = ##class(BronzeWars.Service.Result).Success(200, {"content":(content),"model":(model),"mode":"AGENT_TOOLSET"})
            set pResponse = ##class(BronzeWars.Message.Response).FromResult(result)
            return $$$OK
        }

        set model = ##class(BronzeWars.AI.Agent.Movement).#MODEL

        set provider = ##class(BronzeWars.AI.Agent.Movement).CreateProvider()
        set sc = provider.ValidateConfig()
        if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)

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
