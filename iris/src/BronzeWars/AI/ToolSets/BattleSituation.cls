Class BronzeWars.AI.ToolSets.BattleSituation Extends %AI.ToolSet
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="BronzeWarsBattleSituation">
  <Description>Herramientas de BronzeWars para consultar el estado general del ejercito controlado por la IA.</Description>

  <Policies>
    <Audit Class="BronzeWars.AI.Policies.ToolAudit"/>
  </Policies>

  <Tool Name="GetBattleSituation" Class="BronzeWars.AI.Tools.BattleSituation" Method="GetBattleSituation">
    <Description>Devuelve un resumen compacto del ejercito de la IA para la batalla indicada: moral media cualitativa y porcentaje de bajas sobre su fuerza inicial.</Description>
  </Tool>
</ToolSet>
}

}
