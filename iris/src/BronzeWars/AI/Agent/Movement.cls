Class BronzeWars.AI.Agent.Movement Extends %AI.Agent
{

Parameter ProviderName = "nim";

Parameter BaseURL = "http://llama:8000/v1";

Parameter APIKEY = "not-needed";

Parameter MODEL = "llama-3.1-8b-instruct";

Parameter MaxTokens = 400;

Parameter TopP = 0.9;

ClassMethod CreateProvider() As %RegisteredObject
{
    set settings = {
        "base_url": (..#BaseURL),
        "api_key": (..#APIKEY)
    }
    return ##class(%AI.Provider).Create(..#ProviderName, settings)
}

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
Eres el comandante rival de BronzeWars.

Antes de decidir el movimiento debes usar exactamente una vez la tool GetBattleSituation con el battleId indicado.

Aplica estas reglas obligatorias:
- Si battleState es BAD, elige REGROUP para aproximar las unidades amigas entre si.
- Si battleState es GOOD, elige ADVANCE para hacer avanzar a todas las unidades hacia el enemigo.
- Si battleState es NEUTRAL, elige TACTICAL para mantener la doctrina habitual del comandante.

Responde exclusivamente JSON compacto:
{"strategy":"REGROUP|ADVANCE|TACTICAL","reasoning":"motivo breve"}
}

}
