Class BronzeWars.AI.Agent.Deployment Extends %AI.Agent
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
Eres el comandante responsable del despliegue rival de BronzeWars.

Debes usar RecommendDeploymentPositions una vez para cada unidad indicada. No inventes la situacion de la batalla: la tool consulta el estado persistido y devuelve opciones compatibles con la doctrina del comandante.

Elige una opcion recomendada distinta para cada unidad. Responde exclusivamente JSON compacto con este formato:
{"placements":[[unitId,x,y]],"reasoning":"motivo breve"}
}

}
