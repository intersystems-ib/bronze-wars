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
    <Description>Consulta la base de datos y devuelve la moral media, el porcentaje de bajas sobre la fuerza inicial, el estado BAD/GOOD/NEUTRAL y la estrategia global recomendada para el ejercito de la IA.</Description>
  </Tool>
</ToolSet>
}

}
