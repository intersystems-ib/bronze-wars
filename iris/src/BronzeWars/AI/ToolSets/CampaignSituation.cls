Class BronzeWars.AI.ToolSets.CampaignSituation Extends %AI.ToolSet
{
XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="BronzeWarsCampaignSituation">
  <Description>Situacion estrategica y opciones de movimiento legales bajo la niebla de guerra.</Description>
  <Policies><Audit Class="BronzeWars.AI.Policies.ToolAudit"/></Policies>
  <Tool Name="GetCampaignSituation" Class="BronzeWars.AI.Tools.CampaignSituation" Method="GetCampaignSituation">
    <Description>Devuelve ejercitos propios, invasores detectados y opciones de defensa, recuperacion, saqueo y conquista para el turno actual. No revela ejercitos ocultos.</Description>
  </Tool>
  <Tool Name="GetArmyReinforcementAdvice" Class="BronzeWars.AI.Tools.CampaignSituation" Method="GetArmyReinforcementAdvice">
    <Description>Compara divisiones enemigas detectadas a un maximo de dos hexagonos con cada ejercito propio. Recomienda fusionarse con aliados si el enemigo es mas numeroso, sin inventar recuentos desconocidos.</Description>
  </Tool>
</ToolSet>
}
}
