Class BronzeWars.AI.ToolSets.CampaignRecruitment Extends %AI.ToolSet
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="BronzeWarsCampaignRecruitment">
  <Description>Economia y capacidad de reclutamiento de la nacion que decide este turno.</Description>
  <Policies><Audit Class="BronzeWars.AI.Policies.ToolAudit"/></Policies>
  <Tool Name="GetRecruitmentCapacity" Class="BronzeWars.AI.Tools.CampaignRecruitment" Method="GetRecruitmentCapacity">
    <Description>Devuelve la reserva de grano, produccion anual, consumo por turno y anual, efectivos actuales, capital disponible, maximo de efectivos alistables y sostenibles y unidades nacionales con coste, efectivos y maximo de formaciones asequibles. La escasez no prohibe reclutar si hay reservas.</Description>
  </Tool>
</ToolSet>
}

}
