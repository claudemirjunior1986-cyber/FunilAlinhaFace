/* ============ Teleconsulta: criar a sala e mandar o link ============
   Usado no painel (equipe) e na área do médico. Só depende de FUNIL. */
async function teleSala(p, cirurgiao){
  // reaproveita a sala aberta nas últimas 12 h para este paciente
  const desde = new Date(Date.now() - 12*3600e3).toISOString();
  const { data: ex } = await FUNIL.sb.from("funil_teleconsultas").select("id")
    .eq("paciente_id", p.id).is("fim", null).gte("criada_em", desde).order("criada_em",{ascending:false}).limit(1);
  if(ex && ex[0]) return ex[0].id;
  const { data, error } = await FUNIL.sb.from("funil_teleconsultas")
    .insert({ paciente_id: p.id, paciente_nome: p.nome || "", cirurgiao: cirurgiao || p.cirurgiao || null })
    .select("id").single();
  if(error) throw error;
  return data.id;
}
const teleLinkPaciente = id => location.origin + "/sala.html?c=" + id + "&p=1";
const teleLinkMedico   = id => location.origin + "/sala.html?c=" + id;
function teleMensagem(p, id, nomeMedico){
  const pn = String(p.nome||"").trim().split(/\s+/)[0] || "";
  const nome1 = pn ? pn.charAt(0).toUpperCase() + pn.slice(1).toLowerCase() : "";
  const quando = p.dataConsulta ? " de " + p.dataConsulta.slice(8,10) + "/" + p.dataConsulta.slice(5,7) + (p.horaConsulta ? " às " + p.horaConsulta : "") : "";
  return "Oi" + (nome1 ? ", " + nome1 : "") + "! Sua consulta online" + quando + (nomeMedico ? " com o " + nomeMedico : "") +
    " vai ser por este link:\n" + teleLinkPaciente(id) +
    "\n\nNo horário, abra pelo celular (de preferência no Chrome ou Safari), permita câmera e microfone e toque em Entrar. Se puder, use fone de ouvido. Qualquer dificuldade, é só responder aqui.";
}
