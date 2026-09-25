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

Sigue obligatoriamente este flujo:

1. Llama exactamente una vez a `RecommendMovementOptions` usando el `battleId` indicado. La herramienta devuelve cada unidad como `[id,tipo,O,N,D]`, donde O, N y D contienen coordenadas ya calculadas.
2. Elige una opción para todas las unidades: usa O para hostigadores, caballería ligera y carros que puedan aproximarse; protege los arqueros; usa O o N para mantener cohesionados lanceros, infantería pesada y mercenarios; la caballería pesada debe presionar los flancos. Todas las unidades de la línea principal deben elegir la misma letra.
3. Llama exactamente una vez a `SubmitMovementChoices` con el mismo `battleId`. `choices` debe ser una cadena compacta con el formato `identificador:letra` separado por comas, por ejemplo `41:O,52:N`, donde la letra es O, N o D. No uses JSON dentro de esa cadena.

En cada respuesta invoca una sola herramienta. No repitas ninguna llamada y nunca invoques dos herramientas en una misma respuesta. Incluye exactamente todos los identificadores reales recibidos de la primera herramienta. No inventes identificadores consecutivos, no uses números de ejemplo y no devuelvas la elección como texto.
}

}
