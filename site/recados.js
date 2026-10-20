/* ============ Recados internos da equipe ============
   Orientações entre administradores (ex.: Claudemir → Ana Clara), gerais ou sobre um paciente.
   Só quem mandou e quem recebeu enxergam. O paciente nunca vê.
   Usa do painel: el, $, toast, pacientes, abrirDrawer, fecharOverlays, dataBR. */
const RC = { lista: [], equipe: [], eu: null, aba: "recebidos", _t: null, primeiraCarga: true };

const rcQuando = iso => {
  if(!iso) return "";
  const d = new Date(iso), hj = new Date();
  const hm = d.toLocaleTimeString("pt-BR",{hour:"2-digit",minute:"2-digit",timeZone:"America/Sao_Paulo"});
  return d.toDateString() === hj.toDateString() ? "hoje " + hm
    : d.toLocaleDateString("pt-BR",{day:"2-digit",month:"2-digit",timeZone:"America/Sao_Paulo"}) + " " + hm;
};
const rcPendentes = () => RC.lista.filter(r => r.para === RC.eu && !r.feito_em);
const rcNaoLidos  = () => RC.lista.filter(r => r.para === RC.eu && !r.lido_em);

async function rcIniciar(eu){
  RC.eu = String(eu.email||"").toLowerCase(); RC.nome = eu.nome;
  try{
    const { data } = await FUNIL.sb.from("perfis").select("email,nome,papel").order("nome");
    RC.equipe = (data||[]).filter(p => p.email !== RC.eu)
      .sort((a,b)=> (a.papel==="admin"?0:1)-(b.papel==="admin"?0:1) || a.nome.localeCompare(b.nome));
  }catch(e){ RC.equipe = []; }
  await rcLer();
  FUNIL.sb.channel("rt-recados")
    .on("postgres_changes",{event:"*",schema:"public",table:"funil_recados"}, ev=>{
      if(ev.eventType === "INSERT" && ev.new && ev.new.para === RC.eu){
        toast("📩 Novo recado de " + (ev.new.de_nome || ev.new.de) + (ev.new.paciente_nome ? " sobre " + ev.new.paciente_nome : ""));
      }
      clearTimeout(RC._t); RC._t = setTimeout(rcLer, 300);
    }).subscribe();
  setInterval(()=>{ if(!document.hidden) rcLer(); }, 120000);
}
async function rcLer(){
  const { data, error } = await FUNIL.sb.from("funil_recados").select("*").order("criado_em",{ascending:false}).limit(500);
  if(error) return;
  RC.lista = data || [];
  rcBadge();
  if(document.getElementById("rcPainel")) rcRenderLista();
  const sec = document.getElementById("rcFicha"); if(sec) rcRenderFicha(sec.dataset.pid);
}
function rcBadge(){
  const b = document.getElementById("btnRecados"); if(!b) return;
  const n = rcPendentes().length, novos = rcNaoLidos().length;
  b.textContent = n ? "📩 Recados · " + n : "📩 Recados";
  b.classList.toggle("rc-novo", novos > 0);
  b.title = novos ? novos + " recado(s) novo(s) para você" : "Orientações internas da equipe";
}

/* ---------- painel de recados ---------- */
function rcAbrirPainel(){
  fecharOverlays();
  const scrim = el("div","scrim"); scrim.addEventListener("click",fecharOverlays);
  const d = el("aside","drawer"); d.id = "rcPainel"; d.setAttribute("role","dialog"); d.setAttribute("aria-label","Recados");
  const h = el("header"); h.append(el("h2",null,"Recados da equipe"));
  const bx = el("button","btn btn-ghost btn-sm","Fechar"); bx.addEventListener("click",fecharOverlays); h.appendChild(bx);
  const abas = el("div","rc-abas");
  [["recebidos","Para mim"],["enviados","Que eu mandei"]].forEach(([k,t])=>{
    const b = el("button",null,t); b.dataset.k = k; b.addEventListener("click",()=>{ RC.aba = k; rcRenderLista(); }); abas.appendChild(b);
  });
  const body = el("div","body"); body.id = "rcLista";
  const f = el("footer"); const nv = el("button","btn btn-primary","+ Novo recado"); nv.addEventListener("click",()=>rcNovo(null)); f.appendChild(nv);
  d.append(h, abas, body, f);
  document.body.append(scrim, d);
  rcRenderLista();
  // abriu a lista: o que chegou para mim fica como lido
  const ids = rcNaoLidos().map(r=>r.id);
  if(ids.length){
    const agora = new Date().toISOString();
    RC.lista.forEach(r=>{ if(ids.includes(r.id)) r.lido_em = agora; }); rcBadge();
    FUNIL.sb.from("funil_recados").update({ lido_em: agora }).in("id", ids).then(()=>{});
  }
}
function rcRenderLista(){
  const box = document.getElementById("rcLista"); if(!box) return;
  document.querySelectorAll(".rc-abas button").forEach(b=>b.setAttribute("aria-pressed", String(b.dataset.k===RC.aba)));
  box.textContent = "";
  const lista = RC.lista.filter(r => RC.aba === "recebidos" ? r.para === RC.eu : r.de === RC.eu);
  lista.sort((a,b)=> (!!a.feito_em - !!b.feito_em) || String(b.criado_em).localeCompare(String(a.criado_em)));
  if(!lista.length){
    box.appendChild(el("div","rc-vazio", RC.aba==="recebidos" ? "Nenhum recado para você." : "Você ainda não mandou recados. Use \"+ Novo recado\" ou o botão dentro da ficha do paciente."));
    return;
  }
  lista.forEach(r=>box.appendChild(rcCartao(r)));
}
function rcCartao(r, naFicha){
  const c = el("div","rc-card" + (r.feito_em ? " feito" : "") + (r.para===RC.eu && !r.feito_em ? " pend" : ""));
  const topo = el("div","rc-topo");
  const quem = r.de === RC.eu ? "Você → " + (r.para_nome || r.para) : (r.de_nome || r.de) + " → " + (r.para === RC.eu ? "você" : (r.para_nome || r.para));
  topo.append(el("strong",null,quem), el("span","rc-hora",rcQuando(r.criado_em)));
  c.appendChild(topo);
  if(r.paciente_id && !naFicha){
    const pl = el("button","rc-pac","👤 " + (r.paciente_nome || "Paciente"));
    pl.title = "Abrir a ficha"; pl.addEventListener("click",()=>{ if(pacientes.has(r.paciente_id)) abrirDrawer(r.paciente_id); else toast("Paciente não encontrado."); });
    c.appendChild(pl);
  }
  if(r.responde_a){
    const orig = RC.lista.find(x=>x.id===r.responde_a);
    if(orig) c.appendChild(el("div","rc-cita","↪ " + String(orig.texto).slice(0,120) + (String(orig.texto).length>120?"…":"")));
  }
  c.appendChild(el("div","rc-txt", r.texto));
  if(r.anexo){
    const ax = el("button","rc-anexo","📎 " + (r.anexo_nome || "Anexo"));
    ax.title = "Abrir o anexo"; ax.addEventListener("click",()=>rcAbrirAnexo(r));
    c.appendChild(ax);
  }
  const st = el("div","rc-st");
  if(r.feito_em) st.textContent = "✔ Feito " + rcQuando(r.feito_em);
  else if(r.lido_em) st.textContent = "Lido " + rcQuando(r.lido_em);
  else st.textContent = r.de === RC.eu ? "Ainda não lido" : "Novo";
  const ops = el("div","rc-ops");
  if(r.para === RC.eu){
    const resp = el("button","btn btn-sm","Responder"); resp.addEventListener("click",()=>rcNovo(r.paciente_id ? pacientes.get(r.paciente_id) || {id:r.paciente_id, nome:r.paciente_nome} : null, r));
    ops.appendChild(resp);
    if(!r.feito_em){
      const ok = el("button","btn btn-sm btn-primary","Feito ✔"); ok.title = "Avisa quem mandou que a orientação foi cumprida";
      ok.addEventListener("click",async ()=>{
        ok.disabled = true;
        const { error } = await FUNIL.sb.from("funil_recados").update({ feito_em: new Date().toISOString(), lido_em: r.lido_em || new Date().toISOString() }).eq("id", r.id);
        if(error){ toast("Não consegui marcar."); ok.disabled = false; return; }
        toast("Marcado como feito."); rcLer();
      });
      ops.appendChild(ok);
    }
  }else if(r.de === RC.eu && !r.feito_em){
    const ap = el("button","btn btn-sm btn-ghost","Apagar"); ap.addEventListener("click",async ()=>{
      if(!confirm("Apagar este recado?")) return;
      const { error } = await FUNIL.sb.from("funil_recados").delete().eq("id", r.id);
      if(error) toast("Não consegui apagar."); else rcLer();
    });
    ops.appendChild(ap);
  }
  const rod = el("div","rc-rod"); rod.append(st, ops); c.appendChild(rod);
  return c;
}

/* ---------- escrever recado ---------- */
const rcEhCirurgiao = email => (RC.equipe.find(p=>p.email===email)||{}).papel === "cirurgiao";
async function rcAbrirAnexo(r){
  const w = window.open("about:blank","_blank");
  const { data, error } = await FUNIL.sb.storage.from("anexos").createSignedUrl(r.anexo, 600);
  if(error || !data){ if(w) w.close(); toast("Não consegui abrir o anexo."); return; }
  if(w) w.location = data.signedUrl; else location.href = data.signedUrl;
}
function rcDiasUteis(n){
  const d = new Date(hoje()+"T12:00:00"); let k = 0;
  while(k < n){ d.setDate(d.getDate()+1); if(d.getDay()!==0 && d.getDay()!==6) k++; }
  return d.toISOString().slice(0,10);
}
// paciente: ficha (opcional); respondendo: recado original; paraPadrao: e-mail do destino
function rcNovo(paciente, respondendo, paraPadrao){
  document.querySelectorAll(".rc-scrim,.rc-modal").forEach(n=>n.remove());
  if(!RC.equipe.length){ toast("Não achei outras pessoas da equipe para receber o recado."); return; }
  const scrim = el("div","rc-scrim");
  const m = el("form","rc-modal");
  const titulo = el("h3",null, respondendo ? "Responder recado" : "Novo recado"); m.appendChild(titulo);
  const lp = el("label","f","Para");
  const sel = el("select");
  RC.equipe.forEach(p=>{ const o = el("option",null,p.nome + (p.papel==="cirurgiao" ? " (cirurgião)" : "")); o.value = p.email; sel.appendChild(o); });
  sel.value = respondendo ? respondendo.de : (paraPadrao || (RC.equipe.find(p=>/ana/i.test(p.nome))||RC.equipe[0]).email);
  lp.appendChild(sel); m.appendChild(lp);
  if(paciente) m.appendChild(el("div","rc-pac-fixo","👤 Sobre: " + (paciente.nome || "paciente")));
  const lt = el("label","f","Recado");
  const ta = el("textarea"); ta.rows = 5; ta.required = true; ta.maxLength = 4000;
  lt.appendChild(ta); m.appendChild(lt);

  // só quando vai para um cirurgião: anexo + tarefa de cobrar o retorno
  const extra = el("div","rc-extra");
  const la = el("label","f","Anexar exame (PDF ou imagem, opcional)");
  const fa = el("input"); fa.type = "file"; fa.accept = "image/*,application/pdf";
  la.appendChild(fa); extra.appendChild(la);
  const lc = el("label","rc-chk");
  const cc = el("input"); cc.type = "checkbox"; cc.checked = !!paciente;
  const dc = el("input"); dc.type = "date"; dc.value = rcDiasUteis(2);
  lc.append(cc, document.createTextNode(" Criar minha tarefa de cobrar o retorno dele em "), dc);
  if(paciente) extra.appendChild(lc);
  m.appendChild(extra);
  const ajustar = ()=>{
    const cir = rcEhCirurgiao(sel.value);
    extra.style.display = cir ? "flex" : "none";
    if(!respondendo) titulo.textContent = cir ? "Avisar o cirurgião" : "Novo recado";
    ta.placeholder = cir
      ? (paciente ? "Ex.: Chegou o exame da " + (String(paciente.nome||"").split(" ")[0]||"paciente") + ". Pode avaliar e me dizer a conduta?" : "Ex.: Doutor, chegaram exames novos dos seus pacientes.")
      : (paciente ? "Ex.: Liga para ela amanhã cedo e confirma se já fez a ressonância." : "Ex.: Hoje prioriza quem está em Aguardando no WhatsApp.");
  };
  sel.addEventListener("change", ajustar); ajustar();

  const ops = el("div","rc-mops");
  const cx = el("button","btn","Cancelar"); cx.type = "button"; cx.addEventListener("click",()=>{ scrim.remove(); m.remove(); });
  const ok = el("button","btn btn-primary","Enviar"); ok.type = "submit";
  ops.append(cx, ok); m.appendChild(ops);
  m.addEventListener("submit", async e=>{
    e.preventDefault();
    const texto = ta.value.trim(); if(!texto) return;
    const dest = RC.equipe.find(p=>p.email===sel.value) || {};
    const paraCir = dest.papel === "cirurgiao";
    // cirurgião só enxerga paciente que está no nome dele
    let virarResponsavel = false;
    if(paraCir && paciente && paciente.cirurgiao !== dest.email){
      virarResponsavel = confirm(dest.nome + " ainda não é o cirurgião responsável por " + (paciente.nome||"este paciente") + ".\n\nColocar " + dest.nome + " como responsável? (Sem isso, ele recebe o aviso, mas não consegue abrir a ficha.)");
    }
    const arq = paraCir && fa.files && fa.files[0];
    if(arq && arq.size > 25*1024*1024){ toast("Arquivo grande demais (máximo 25 MB)."); return; }
    ok.disabled = true; ok.textContent = "Enviando…";
    let anexo = null, anexo_nome = null;
    if(arq){
      const ext = ((arq.name.match(/\.([a-z0-9]+)$/i)||[])[1]||"bin").toLowerCase();
      const caminho = Date.now() + "-" + Math.random().toString(36).slice(2,8) + "." + ext;
      const up = await FUNIL.sb.storage.from("anexos").upload(caminho, arq, { contentType: arq.type || undefined });
      if(up.error){ toast("Não consegui anexar o arquivo."); ok.disabled = false; ok.textContent = "Enviar"; return; }
      anexo = caminho; anexo_nome = arq.name;
    }
    const { error } = await FUNIL.sb.from("funil_recados").insert({
      de: RC.eu, de_nome: RC.nome, para: dest.email, para_nome: dest.nome || dest.email,
      paciente_id: paciente ? paciente.id : null, paciente_nome: paciente ? (paciente.nome||"") : null,
      texto, responde_a: respondendo ? respondendo.id : null, anexo, anexo_nome
    });
    if(error){ toast("Não consegui enviar o recado."); ok.disabled = false; ok.textContent = "Enviar"; return; }
    if(respondendo && respondendo.para === RC.eu && !respondendo.lido_em){
      FUNIL.sb.from("funil_recados").update({ lido_em: new Date().toISOString() }).eq("id", respondendo.id).then(()=>{});
    }
    // na ficha: responsável, tarefa de cobrar e histórico
    if(paraCir && paciente && typeof salvar === "function" && pacientes.has(paciente.id)){
      const q = Object.assign({}, pacientes.get(paciente.id));
      if(virarResponsavel) q.cirurgiao = dest.email;
      if(cc.checked && dc.value){
        q.proximaAcao = "Cobrar retorno do " + dest.nome + ": " + texto.replace(/\s+/g," ").slice(0,70) + (texto.length>70?"…":"");
        q.dataProximaAcao = dc.value;
      }
      registrarHistorico(q, "Aviso ao " + dest.nome + (anexo_nome ? " (com anexo: " + anexo_nome + ")" : "") + ": " + texto.replace(/\s+/g," ").slice(0,200));
      salvar(q);
      // reabre a ficha já atualizada, para o "Salvar" dela não desfazer a tarefa
      if(document.getElementById("drawer") && typeof abrirDrawer === "function") setTimeout(()=>abrirDrawer(paciente.id), 50);
    }
    scrim.remove(); m.remove();
    toast((paraCir ? "Aviso enviado para o " : "Recado enviado para ") + (dest.nome || "a equipe") + "." + (paraCir && paciente && cc.checked ? " Sua tarefa de cobrar ficou para " + dataBR(dc.value) + "." : ""));
    rcLer();
  });
  scrim.addEventListener("click",()=>{ scrim.remove(); m.remove(); });
  document.body.append(scrim, m);
  ta.focus();
}

/* ---------- dentro da ficha do paciente ---------- */
function rcSecaoFicha(p){
  const fs = el("fieldset"); fs.id = "rcFicha"; fs.dataset.pid = p.id;
  fs.append(el("div","legend","Recados e avisos sobre este paciente"));
  const corpo = el("div","rc-ficha-corpo"); fs.appendChild(corpo);
  const bs = el("div","rc-ficha-bts");
  const b = el("button","btn btn-sm","📩 Recado para a equipe"); b.type = "button";
  b.addEventListener("click",()=>rcNovo(p));
  const bc = el("button","btn btn-sm btn-primary","🩺 Avisar o cirurgião"); bc.type = "button";
  bc.title = "Ex.: chegou o exame. Ele vê no login dele, e sua tarefa de cobrar o retorno já fica marcada.";
  bc.addEventListener("click",()=>{
    const cir = RC.equipe.find(x=>x.email===p.cirurgiao && x.papel==="cirurgiao") || RC.equipe.find(x=>x.papel==="cirurgiao");
    if(!cir){ toast("Nenhum cirurgião cadastrado."); return; }
    rcNovo(pacientes.get(p.id) || p, null, cir.email);
  });
  bs.append(bc, b); fs.appendChild(bs);
  setTimeout(()=>rcRenderFicha(p.id), 0);
  return fs;
}
function rcRenderFicha(pid){
  const sec = document.getElementById("rcFicha"); if(!sec || sec.dataset.pid !== pid) return;
  const corpo = sec.querySelector(".rc-ficha-corpo"); corpo.textContent = "";
  const lista = RC.lista.filter(r=>r.paciente_id === pid).sort((a,b)=>String(a.criado_em).localeCompare(String(b.criado_em)));
  if(!lista.length){ corpo.appendChild(el("div","hint","Nenhum recado ou aviso sobre este paciente. Só a equipe e o cirurgião veem; o paciente nunca.")); return; }
  lista.forEach(r=>corpo.appendChild(rcCartao(r, true)));
}
