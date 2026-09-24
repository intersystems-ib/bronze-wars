Class BronzeWars.Service.BaseService Extends Ens.BusinessService [ Abstract ]
{

Parameter ADAPTER = "";
Parameter TARGET = "";

Method OnProcessInput(pInput As BronzeWars.Message.Request, Output pOutput As BronzeWars.Message.Response) As %Status
{
    return ..SendRequestSync(..#TARGET, pInput, .pOutput)
}

}
