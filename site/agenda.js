/* ============ Agenda do cirurgião (Google Agenda) ============
   A mesma agenda que a Bia usa no GPT Maker. O site mostra a agenda (embutida do Google)
   e cria eventos abrindo o Google Agenda já preenchido: quem salva é a pessoa, com a conta
   Google dela, que precisa ter a agenda compartilhada com permissão de editar.
   Usa do painel: el, $, toast, dataBR, MEDICOS. */
const AGENDAS = {
  gus: { nome: "Dr. Gustavo", calendario: "gu.martins00@gmail.com", duracaoMin: 30 }
};
const agTz = "America/Sao_Paulo";

function agLinkVer(k){
  const a = AGENDAS[k];
  return "https://calendar.google.com/calendar/u/0/r/week?cid=" + encodeURIComponent(a.calendario);
}
function agLinkEmbed(k){
  const a = AGENDAS[k];
  return "https://calendar.google.com/calendar/embed?src=" + encodeURIComponent(a.calendario)
    + "&ctz=" + encodeURIComponent(agTz) + "&mode=WEEK&showPrint=0&showTitle=0&showTabs=1&showCalendars=0&hl=pt_BR";
}
// "2026-10-22" + "13:30" -> "20261022T133000" (hora local; o fuso vai no ctz)
const agCarimbo = (d, h) => d.replace(/-/g,"") + "T" + String(h||"09:00").replace(":","").padEnd(4,"0") + "00";
function agSomaMin(d, h, min){
  const [H,M] = String(h||"09:00").split(":").map(Number);
  const x = new Date(d+"T00:00:00Z"); x.setUTCMinutes(H*60 + M + min);
  return [x.toISOString().slice(0,10), x.toISOString().slice(11,16)];
}
function agLinkNovo(k, info){
  const a = AGENDAS[k];
  const u = new URL("https://calendar.google.com/calendar/render");
  u.searchParams.set("action","TEMPLATE");
  u.searchParams.set("src", a.calendario);
  u.searchParams.set("ctz", agTz);
  u.searchParams.set("text", info.titulo || "Consulta Alinha Face");
  if(info.data){
    const [d2,h2] = agSomaMin(info.data, info.hora, a.duracaoMin);
    u.searchParams.set("dates", agCarimbo(info.data, info.hora) + "/" + agCarimbo(d2, h2));
  }
  if(info.detalhes) u.searchParams.set("details", info.detalhes);
  if(info.local) u.searchParams.set("location", info.local);
  return u.toString();
}

/* ---------- aba "Agenda Dr. Gustavo" ---------- */
function renderAgendaMed(k){
  k = k || "gus";
  const a = AGENDAS[k];
  const box = $("#agview"); box.textContent = "";
  const head = el("div","hoje-head");
  const hl = el("div");
  hl.append(el("h2",null,"Agenda " + a.nome),
            el("div","dt","A mesma agenda do Google que a Bia usa para marcar. O que a equipe marcar aqui a Bia já enxerga como ocupado."));
  const acts = el("div","acts");
  const bNovo = el("button","btn btn-primary","+ Novo agendamento");
  bNovo.addEventListener("click",()=>window.open(agLinkNovo(k,{titulo:"Consulta Alinha Face — ", detalhes:"Agendado pela equipe (painel Alinha Face)"}),"_blank","noopener"));
  const bAbrir = el("button","btn","Abrir no Google Agenda");
  bAbrir.addEventListener("click",()=>window.open(agLinkVer(k),"_blank","noopener"));
  acts.append(bNovo, bAbrir);
  head.append(hl, acts); box.appendChild(head);

  const fr = el("iframe","ag-frame");
  fr.src = agLinkEmbed(k); fr.title = "Agenda " + a.nome; fr.loading = "lazy";
  box.appendChild(fr);
  box.appendChild(el("div","hint","Se a agenda aparecer vazia ou pedir permissão: entre no Chrome com a conta Google que tem a agenda do " + a.nome + " compartilhada, ou use \"Abrir no Google Agenda\". Para marcar um paciente que já está no funil, use o botão \"📅 Agendar no Google\" dentro da ficha: ele já leva nome, telefone e convênio."));
}

/* ---------- botão dentro da ficha ---------- */
function agBotaoFicha(p){
  const b = el("button","btn btn-sm","📅 Agendar no Google (Dr. Gustavo)"); b.type = "button";
  b.title = "Abre a agenda do Dr. Gustavo com a consulta preenchida (data e horário desta ficha)";
  b.addEventListener("click",()=>{
    const data = $("#f_data").value, hora = $("#f_hora").value;
    if(!data || !hora){ toast("Preencha a data da consulta e o horário na ficha primeiro."); ($("#f_data").value ? $("#f_hora") : $("#f_data")).focus(); return; }
    const nome = ($("#f_nome").value || p.nome || "").trim();
    const tel = ($("#f_tel").value || p.telefone || "").trim();
    const conv = $("#f_conv") ? $("#f_conv").value : p.convenio;
    const nconv = $("#f_nconv") ? $("#f_nconv").value.trim() : (p.nomeConvenio||"");
    const mod = $("#f_mod").value, local = $("#f_local").value;
    const detalhes = [
      "Paciente: " + nome,
      tel ? "WhatsApp: " + tel : "",
      "Convênio: " + (conv==="Sim" ? (nconv || "sim") : (conv==="Não" ? "particular" : "a confirmar")),
      $("#f_trat") ? "Queixa/tratamento: " + $("#f_trat").value : "",
      "Modalidade: " + (mod||"") + (mod==="Presencial" && local ? " — " + local : ""),
      "",
      "Agendado pela equipe (painel Alinha Face)."
    ].filter(x=>x!==null).join("\n");
    window.open(agLinkNovo("gus", {
      titulo: "Consulta Alinha Face — " + nome, data, hora, detalhes,
      local: mod==="Presencial" ? local : "Online (Google Meet)"
    }), "_blank", "noopener");
    // deixa a ficha pronta: Gustavo como responsável e etapa "agendou"
    const sc = $("#f_cir"); if(sc && !sc.value) sc.value = AGENDAS.gus.calendario;
    const se = $("#f_etapa"); if(se && ["triagem","lead"].includes(se.value)) se.value = "agendou";
    toast("No Google, confira e clique em Salvar. Depois clique em Salvar aqui na ficha.");
  });
  return b;
}
