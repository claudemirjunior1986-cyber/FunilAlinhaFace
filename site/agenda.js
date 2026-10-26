/* ============ Agenda do cirurgião (Google Agenda) ============
   A mesma agenda que a Bia usa no GPT Maker. O site mostra a agenda (embutida do Google)
   e cria eventos abrindo o Google Agenda já preenchido: quem salva é a pessoa, com a conta
   Google dela, que precisa ter a agenda compartilhada com permissão de editar.
   Usa do painel: el, $, toast, dataBR, hoje, pacientes, abrirDrawer.
   Dr. Gustavo: agenda dele (gu.martins00). Dr. Afonso e Dr. Victor: calendários da conta
   alinhaface@gmail.com, ligados à Bia no GPT Maker do mesmo jeito.
   (A grade dentro do funil — tabelas agenda_*, arquivo 013 — ficou guardada, mas não é usada.) */
const AGENDAS = {
  gus:    { nome: "Dr. Gustavo", email: "gu.martins00@gmail.com",       calendario: "gu.martins00@gmail.com", duracaoMin: 15 },
  afonso: { nome: "Dr. Afonso",  email: "dr.aptrindadefilho@gmail.com", calendario: "b084c9639ff3b3b3ad75465c059ca93ff5eeaf6483bd736ffb17ba1a07ecc4b9@group.calendar.google.com", duracaoMin: 30 },
  victor: { nome: "Dr. Victor",  email: "admvictorssa@gmail.com",       calendario: "4ce2bc789a67e0f757eee2f6312298f3c15447217234364f6d7bca335fd68546@group.calendar.google.com", duracaoMin: 15 }
};
const agPorEmail = email => Object.keys(AGENDAS).find(k => AGENDAS[k].email === email) || "gus";
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
    const [d2,h2] = agSomaMin(info.data, info.hora, info.duracaoMin || a.duracaoMin);
    u.searchParams.set("dates", agCarimbo(info.data, info.hora) + "/" + agCarimbo(d2, h2));
  }
  if(info.detalhes) u.searchParams.set("details", info.detalhes);
  if(info.local) u.searchParams.set("location", info.local);
  return u.toString();
}

/* ---------- aba "Agendas": Dr. Gustavo (Google) + Dr. Afonso e Dr. Victor (funil) ---------- */
const AG = { k: null, semana: null, medicos: [], grade: [], bloq: [], carregado: false, carregando: null };
try{ AG.k = localStorage.getItem("funil_ag") || "gus"; }catch(e){ AG.k = "gus"; }

function renderAgendaMed(k){
  if(k) AG.k = k;
  const box = $("#agview");
  if(!AGENDAS[AG.k]) AG.k = "gus";
  if(box.dataset.ag === AG.k && box.childElementCount) return;   // não recarrega o Google à toa
  box.dataset.ag = AG.k;
  box.textContent = "";
  const abas = el("div","ag-tabs");
  [["gus","Dr. Gustavo"],["afonso","Dr. Afonso"],["victor","Dr. Victor"]].forEach(([c,n])=>{
    const b = el("button",null,n); b.type = "button"; b.setAttribute("aria-pressed", String(AG.k===c));
    b.addEventListener("click",()=>{ try{ localStorage.setItem("funil_ag", c); }catch(e){} renderAgendaMed(c); });
    abas.appendChild(b);
  });
  box.appendChild(abas);
  renderAgendaGoogle(box, AG.k);
}

function renderAgendaGoogle(box, k){
  const a = AGENDAS[k];
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

/* ---------- agendas que ficam no próprio funil ---------- */
async function agCarregar(forcar){
  if(AG.carregado && !forcar) return true;
  if(!window.FUNIL || !FUNIL.sb) return false;
  if(AG.carregando && !forcar) return AG.carregando;
  AG.carregando = (async ()=>{
    const [m, g, b] = await Promise.all([
      FUNIL.sb.from("agenda_medicos").select("*"),
      FUNIL.sb.from("agenda_grade").select("*").order("dia_semana").order("inicio"),
      FUNIL.sb.from("agenda_bloqueios").select("*").gte("fim", hoje()).order("inicio")
    ]);
    if(m.error || g.error || b.error) throw (m.error || g.error || b.error);
    AG.medicos = m.data || []; AG.grade = g.data || []; AG.bloq = b.data || [];
    AG.carregado = true; return true;
  })();
  try{ return await AG.carregando; } finally { AG.carregando = null; }
}
const agMin = h => { const [H,M] = String(h||"0:0").split(":").map(Number); return H*60 + (M||0); };
const agHora = m => String(Math.floor(m/60)).padStart(2,"0") + ":" + String(m%60).padStart(2,"0");
const agDur = mod => mod === "Presencial" ? 30 : 15;
const agIso = dt => dt.getFullYear() + "-" + String(dt.getMonth()+1).padStart(2,"0") + "-" + String(dt.getDate()).padStart(2,"0");
function agSegunda(iso){ const d = new Date(iso+"T12:00:00"); d.setDate(d.getDate() - ((d.getDay()+6)%7)); return agIso(d); }
function agMaisDias(iso, n){ const d = new Date(iso+"T12:00:00"); d.setDate(d.getDate()+n); return agIso(d); }
const agMedico = k => AG.medicos.find(m=>m.chave===k) || {chave:k, nome:k};
function agDoMedico(k, p){
  const m = agMedico(k);
  return p.agendaMedico === k || (!!m.email && p.cirurgiao === m.email);
}
// consultas valendo do médico num dia
function agConsultas(k, iso, ignorar){
  return [...pacientes.values()].filter(p => p.id !== ignorar && agDoMedico(k, p) && p.dataConsulta === iso
      && /^\d{2}:\d{2}$/.test(p.horaConsulta||"") && !["perdido","noshow"].includes(p.etapa))
    .sort((a,b)=>a.horaConsulta.localeCompare(b.horaConsulta));
}
function agBloqueiosDia(k, iso){
  return AG.bloq.filter(b => b.medico===k && b.inicio.slice(0,10) <= iso && b.fim.slice(0,10) >= iso);
}
// [ini, fim) em minutos do dia está livre?
function agLivre(k, iso, ini, fim, ignorar){
  if(agConsultas(k, iso, ignorar).some(p=>{ const a = agMin(p.horaConsulta); return a < fim && a + agDur(p.modalidade) > ini; })) return false;
  const t0 = iso+"T"+agHora(ini), t1 = iso+"T"+agHora(fim);
  return !AG.bloq.some(b => b.medico===k && b.inicio.slice(0,16) < t1 && b.fim.slice(0,16) > t0);
}
const agAgoraMin = () => { const p = new Intl.DateTimeFormat("en-GB",{timeZone:"America/Sao_Paulo",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date()); return agMin(p); };

async function renderAgendaFunil(box, k){
  const carregando = el("div","ag-vazio","Carregando agenda…"); box.appendChild(carregando);
  try{
    if(!await agCarregar()){ carregando.textContent = "A agenda só aparece com o site ligado ao banco (entre com seu login)."; return; }
  }catch(e){
    carregando.textContent = "Não consegui ler a agenda. Se ainda não rodou o arquivo 013_agendas_medicos.sql no Supabase, rode e recarregue a página.";
    return;
  }
  if(box.dataset.ag !== k) return;   // trocou de aba enquanto carregava
  carregando.remove();
  const m = agMedico(k);
  if(!AG.semana) AG.semana = agSegunda(hoje());

  const head = el("div","hoje-head");
  const hl = el("div");
  hl.append(el("h2",null,"Agenda " + (m.nome||k)),
            el("div","dt","Agenda dentro do funil: a Bia marca aqui sozinha. Online de 15 em 15 min, presencial de 30 em 30. Clique num horário livre para marcar um paciente."));
  const acts = el("div","acts");
  const bAnt = el("button","btn btn-sm","‹ Semana anterior"), bHoje = el("button","btn btn-sm","Esta semana"), bProx = el("button","btn btn-sm","Próxima semana ›");
  bAnt.addEventListener("click",()=>{ AG.semana = agMaisDias(AG.semana,-7); renderAgendaMed(); });
  bHoje.addEventListener("click",()=>{ AG.semana = agSegunda(hoje()); renderAgendaMed(); });
  bProx.addEventListener("click",()=>{ AG.semana = agMaisDias(AG.semana,7); renderAgendaMed(); });
  const bBloq = el("button","btn btn-sm","+ Folga / bloqueio");
  bBloq.addEventListener("click",()=>agNovoBloqueio(k));
  acts.append(bAnt, bHoje, bProx, bBloq);
  head.append(hl, acts); box.appendChild(head);
  if(!m.email) box.appendChild(el("div","ag-bloq","O " + (m.nome||k) + " ainda não tem login no site: as consultas marcadas ficam na agenda e no painel, mas ele ainda não vê nem recebe o aviso por WhatsApp."));

  const grade = AG.grade.filter(g=>g.medico===k);
  const sem = el("div","ag-sem");
  const nomesDia = ["Domingo","Segunda","Terça","Quarta","Quinta","Sexta","Sábado"];
  const hj = hoje(), agora = agAgoraMin();
  for(let i=0;i<7;i++){
    const iso = agMaisDias(AG.semana, i);
    const dow = new Date(iso+"T12:00:00").getDay();
    const blocos = grade.filter(g=>g.dia_semana===dow);
    const cons = agConsultas(k, iso);
    if(!blocos.length && !cons.length) continue;
    const card = el("div","ag-dia" + (iso===hj ? " hoje" : ""));
    card.appendChild(el("h3",null, nomesDia[dow] + " " + dataBR(iso)));
    card.appendChild(el("div","sub", blocos.map(g=>
      g.inicio.slice(0,5)+"–"+g.fim.slice(0,5)+" · "+(g.modalidades.includes("Presencial") ? (g.local||"Presencial").replace(/\s*\(.*\)$/,"") + " + online" : "só online")
    ).join(" | ") || "fora da grade"));
    agBloqueiosDia(k, iso).forEach(b=>{
      const t = (b.inicio.slice(0,10)===iso ? b.inicio.slice(11,16) : "00:00") + "–" + (b.fim.slice(0,10)===iso ? b.fim.slice(11,16) : "24:00");
      card.appendChild(el("div","ag-bloq","⛔ " + (t==="00:00–24:00" ? "Dia bloqueado" : "Bloqueado " + t) + (b.motivo ? " · " + b.motivo : "")));
    });
    cons.forEach(p=>{
      const bt = el("button","ag-cons"); bt.type = "button";
      bt.append(el("b",null,p.horaConsulta), el("span",null,(p.modalidade==="Presencial"?"🏥 ":"💻 ") + (p.nome||"Sem nome") + (p.agendadoPor==="Bia" ? " · Bia" : "")));
      bt.title = (p.modalidade||"") + (p.local && p.modalidade==="Presencial" ? " · " + p.local : "") + " — abrir ficha";
      bt.addEventListener("click",()=>abrirDrawer(p.id));
      card.appendChild(bt);
    });
    const livres = el("div","ag-livres");
    let n = 0;
    blocos.forEach(g=>{
      for(let t=agMin(g.inicio); t + 15 <= agMin(g.fim); t += 15){
        if(iso < hj || (iso===hj && t < agora + 60)) continue;
        if(!agLivre(k, iso, t, t+15)) continue;
        const presOk = g.modalidades.includes("Presencial") && t % 30 === agMin(g.inicio) % 30 && t + 30 <= agMin(g.fim) && agLivre(k, iso, t, t+30);
        const c = el("button","ag-livre", agHora(t)); c.type = "button";
        c.title = presOk ? "Livre (online ou presencial)" : "Livre só para online (15 min)";
        c.addEventListener("click",()=>agMarcar(k, g, iso, agHora(t), presOk));
        livres.appendChild(c); n++;
      }
    });
    if(n) card.appendChild(livres);
    else if(iso >= hj) card.appendChild(el("div","ag-vazio","Sem horário livre."));
    sem.appendChild(card);
  }
  if(!sem.childElementCount) box.appendChild(el("div","ag-vazio","Nenhum atendimento nesta semana."));
  box.appendChild(sem);

  // folgas futuras
  const futuros = AG.bloq.filter(b=>b.medico===k);
  if(futuros.length){
    box.appendChild(el("h3",null,"Folgas e bloqueios"));
    const l = el("div","ag-lista-bloq");
    futuros.forEach(b=>{
      const linha = el("div");
      linha.append(el("span",null, dataBR(b.inicio.slice(0,10)) + " " + b.inicio.slice(11,16) + " → " + dataBR(b.fim.slice(0,10)) + " " + b.fim.slice(11,16) + (b.motivo ? " · " + b.motivo : "")));
      const x = el("button","btn btn-sm btn-ghost","Remover");
      x.addEventListener("click",async ()=>{
        if(!confirm("Remover este bloqueio? O horário volta a ser oferecido pela Bia.")) return;
        const { error } = await FUNIL.sb.from("agenda_bloqueios").delete().eq("id", b.id);
        if(error){ toast("Não consegui remover."); return; }
        await agCarregar(true); renderAgendaMed();
      });
      linha.appendChild(x); l.appendChild(linha);
    });
    box.appendChild(l);
  }
}

function agMarcar(k, g, iso, hora, presOk){
  const m = agMedico(k);
  let mod = "Online";
  if(presOk) mod = confirm("Marcar " + dataBR(iso) + " às " + hora + " com o " + m.nome + ".\n\nOK = presencial (" + (g.local||"") + ")\nCancelar = online") ? "Presencial" : "Online";
  abrirDrawer(null, {
    dataConsulta: iso, horaConsulta: hora, modalidade: mod,
    local: mod==="Presencial" ? (g.local||"") : "Online",
    cirurgiao: m.email || "", agendaMedico: k, etapa: "agendou"
  });
  toast("Preencha nome e telefone e clique em Salvar.");
}

async function agNovoBloqueio(k){
  const m = agMedico(k);
  const dia = prompt("Bloquear a agenda do " + m.nome + "\n\nDia (dd/mm/aaaa):", dataBR(hoje()) + "/" + hoje().slice(0,4));
  if(!dia) return;
  const mt = dia.trim().match(/^(\d{1,2})\/(\d{1,2})(?:\/(\d{4}))?$/);
  if(!mt){ toast("Data inválida. Use dd/mm/aaaa."); return; }
  const iso = (mt[3]||hoje().slice(0,4)) + "-" + mt[2].padStart(2,"0") + "-" + mt[1].padStart(2,"0");
  const faixa = prompt("Horário bloqueado (ex.: 14:00-16:00).\nDeixe vazio para bloquear o dia inteiro.", "");
  if(faixa === null) return;
  let ini = iso + "T00:00", fim = agMaisDias(iso,1) + "T00:00";
  if(faixa.trim()){
    const f = faixa.match(/(\d{1,2})[:h]?(\d{2})?\s*[-–a]+\s*(\d{1,2})[:h]?(\d{2})?/);
    if(!f){ toast("Horário inválido. Use 14:00-16:00."); return; }
    ini = iso + "T" + f[1].padStart(2,"0") + ":" + (f[2]||"00");
    fim = iso + "T" + f[3].padStart(2,"0") + ":" + (f[4]||"00");
    if(fim <= ini){ toast("O fim precisa ser depois do início."); return; }
  }
  const motivo = prompt("Motivo (opcional):", "") || null;
  const ocupadas = agConsultas(k, iso).filter(p=>{ const t = iso+"T"+p.horaConsulta; return t >= ini && t < fim; });
  const { error } = await FUNIL.sb.from("agenda_bloqueios").insert({ medico:k, inicio:ini, fim, motivo });
  if(error){ toast("Não consegui bloquear."); return; }
  await agCarregar(true); renderAgendaMed();
  toast(ocupadas.length ? "Bloqueado. Atenção: " + ocupadas.length + " consulta(s) já marcada(s) nesse período — remarque." : "Horário bloqueado. A Bia não oferece mais esse período.");
}

// chamado ao salvar a ficha: mantém a ligação com a agenda do funil coerente e avisa conflito
function agAjustarFicha(p){
  if(!AG.carregado) return;
  const dono = AG.medicos.find(m=>m.email && m.email===p.cirurgiao);
  if(dono) p.agendaMedico = dono.chave;
  else if(p.agendaMedico){
    const m = agMedico(p.agendaMedico);
    if(p.cirurgiao && p.cirurgiao !== m.email) delete p.agendaMedico;   // passou para outro cirurgião
  }
  if(p.agendaMedico && p.dataConsulta && /^\d{2}:\d{2}$/.test(p.horaConsulta||"") && !["perdido","noshow"].includes(p.etapa)){
    const ini = agMin(p.horaConsulta);
    if(!agLivre(p.agendaMedico, p.dataConsulta, ini, ini + agDur(p.modalidade), p.id))
      toast("Atenção: esse horário já tem consulta ou bloqueio na agenda do " + agMedico(p.agendaMedico).nome + ".");
  }
}

/* ---------- botão dentro da ficha ---------- */
function agBotaoFicha(p){
  const b = el("button","btn btn-sm","📅 Agendar no Google"); b.type = "button";
  b.title = "Abre a agenda do cirurgião escolhido na ficha (sem cirurgião: Dr. Gustavo) com a consulta preenchida";
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
    const sc = $("#f_cir");
    const k = agPorEmail(sc ? sc.value : "");
    window.open(agLinkNovo(k, {
      titulo: "Consulta Alinha Face — " + nome, data, hora, detalhes,
      duracaoMin: mod==="Presencial" ? 30 : 15,
      local: mod==="Presencial" ? local : "Online (Google Meet)"
    }), "_blank", "noopener");
    // deixa a ficha pronta: cirurgião responsável e etapa "agendou"
    if(sc && !sc.value) sc.value = AGENDAS[k].email;
    const se = $("#f_etapa"); if(se && ["triagem","lead"].includes(se.value)) se.value = "agendou";
    toast("No Google, confira e clique em Salvar. Depois clique em Salvar aqui na ficha.");
  });
  return b;
}
