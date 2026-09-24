Class BronzeWars.Rest.API Extends %CSP.REST
{

Parameter UseSession As Integer = 0;
Parameter HandleCorsRequest = 0;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
    <Route Url="/unit-types" Method="GET" Call="GetUnitTypes" />
    <Route Url="/battles" Method="POST" Call="CreateBattle" />
    <Route Url="/battles/:battleId" Method="GET" Call="GetBattle" />
    <Route Url="/battles/:battleId/deployment" Method="GET" Call="GetDeployment" />
    <Route Url="/battles/:battleId/units/:unitId/position" Method="PUT" Call="PutUnitPosition" />
    <Route Url="/battles/:battleId/start" Method="POST" Call="StartBattle" />
</Routes>
}

ClassMethod GetUnitTypes() As %Status
{
    do ..WriteResult(##class(BronzeWars.Interop.Client).ListUnitTypes())
    return $$$OK
}

ClassMethod CreateBattle() As %Status
{
    set parseResult = ..ReadJSON(0, .input)
    if 'parseResult.ok {
        do ..WriteResult(parseResult)
        return $$$OK
    }

    set validation = ..ValidateCreateInput(input)
    if 'validation.ok {
        do ..WriteResult(validation)
        return $$$OK
    }

    set result = ##class(BronzeWars.Interop.Client).CreateBattle(input)
    if result.ok {
        set battleId = result.data.battle.id
        do %response.SetHeader("Location", "/api/bronzewars/battles/" _ battleId)
    }
    do ..WriteResult(result)
    return $$$OK
}

ClassMethod GetBattle(battleId As %String) As %Status
{
    do ..WriteResult(##class(BronzeWars.Interop.Client).GetBattle(battleId))
    return $$$OK
}

ClassMethod GetDeployment(battleId As %String) As %Status
{
    do ..WriteResult(##class(BronzeWars.Interop.Client).GetDeployment(battleId))
    return $$$OK
}

ClassMethod PutUnitPosition(battleId As %String, unitId As %String) As %Status
{
    set parseResult = ..ReadJSON(0, .input)
    if 'parseResult.ok {
        do ..WriteResult(parseResult)
        return $$$OK
    }
    set validation = ..ValidatePositionInput(input)
    if 'validation.ok {
        do ..WriteResult(validation)
        return $$$OK
    }
    do ..WriteResult(##class(BronzeWars.Interop.Client).PlaceUnit(battleId, unitId, input.x, input.y))
    return $$$OK
}

ClassMethod StartBattle(battleId As %String) As %Status
{
    do ..WriteResult(##class(BronzeWars.Interop.Client).StartBattle(battleId))
    return $$$OK
}

ClassMethod ReadJSON(allowEmpty As %Boolean, Output input As %DynamicObject) As %DynamicObject [ Private ]
{
    set body = %request.Content.Read()
    if body = "" {
        if allowEmpty {
            set input = ##class(%DynamicObject).%New()
            return ##class(BronzeWars.Service.Result).Success(200)
        }
        return ##class(BronzeWars.Service.Result).Error(400, "INVALID_JSON", "El cuerpo debe contener un objeto JSON.")
    }
    set result = ""
    try {
        set input = ##class(%DynamicObject).%FromJSON(body)
        if '$isobject(input) {
            set result = ##class(BronzeWars.Service.Result).Error(400, "INVALID_JSON", "El cuerpo debe contener un objeto JSON.")
        } else {
            set result = ##class(BronzeWars.Service.Result).Success(200)
        }
    } catch exception {
        set result = ##class(BronzeWars.Service.Result).Error(400, "INVALID_JSON", "El cuerpo JSON no es valido.")
    }
    return result
}

ClassMethod ValidateCreateInput(input As %DynamicObject) As %DynamicObject [ Private ]
{
    if input.%IsDefined("name"), (input.%GetTypeOf("name") '= "string") return ..BadField("name", "El nombre debe ser texto.")
    if input.%IsDefined("boardWidth") {
        if (input.%GetTypeOf("boardWidth") '= "number") ! (input.boardWidth '= (input.boardWidth \ 1)) return ..BadField("boardWidth", "El ancho debe ser un entero.")
    }
    if input.%IsDefined("boardHeight") {
        if (input.%GetTypeOf("boardHeight") '= "number") ! (input.boardHeight '= (input.boardHeight \ 1)) return ..BadField("boardHeight", "El alto debe ser un entero.")
    }
    if input.%IsDefined("faction"), (input.%GetTypeOf("faction") '= "string") return ..BadField("faction", "La faccion debe ser texto.")
    if input.%IsDefined("units"), (input.%GetTypeOf("units") '= "array") return ..BadField("units", "La composicion del ejercito debe ser una lista.")
    return ##class(BronzeWars.Service.Result).Success(200)
}

ClassMethod ValidatePositionInput(input As %DynamicObject) As %DynamicObject [ Private ]
{
    if 'input.%IsDefined("x") return ..BadField("x", "La coordenada x es obligatoria.")
    if 'input.%IsDefined("y") return ..BadField("y", "La coordenada y es obligatoria.")
    if (input.%GetTypeOf("x") '= "number") ! (input.x '= (input.x \ 1)) return ..BadField("x", "La coordenada x debe ser un entero.")
    if (input.%GetTypeOf("y") '= "number") ! (input.y '= (input.y \ 1)) return ..BadField("y", "La coordenada y debe ser un entero.")
    return ##class(BronzeWars.Service.Result).Success(200)
}

ClassMethod BadField(field As %String, message As %String) As %DynamicObject [ Private ]
{
    set details = ##class(%DynamicArray).%New()
    do details.%Push({"field":(field),"message":(message)})
    return ##class(BronzeWars.Service.Result).Error(400, "INVALID_REQUEST", "La solicitud no es valida.", details)
}

ClassMethod WriteResult(result As %DynamicObject) [ Private ]
{
    set %response.ContentType = "application/json"
    set %response.CharSet = "utf-8"
    set %response.Status = result.status
    if result.ok {
        if result.%IsDefined("data") {
            write result.data.%ToJSON()
        } else {
            write "{}"
        }
        quit
    }

    set error = {"error":{"code":(result.code),"message":(result.message)}}
    if result.%IsDefined("details") do error.error.%Set("details", result.details)
    write error.%ToJSON()
}

}
