/* ============ WhatsApp dentro do painel ============
   Conversas da Bia (GPT Maker) lidas e respondidas pelo site.
   A chave do GPT Maker fica na função "whats" do Supabase; aqui só chamamos a função.
   Usa do painel: el, $, toast, telBR, pacientes, abrirDrawer, salvar, novoId, modo, trocarModo. */
const WA = {
  chats: new Map(),       // chat_id -> linha de funil_whats
  aberto: null,           // chat_id aberto
  msgs: [], pagina: 1, temMais: false,
  filtro: "aguardando",   // aguardando | todas | equipe
  busca: "",
  rascunho: {},           // chat_id -> texto digitado
  semChave: false, carregou: false,
  timerLista: null, timerConversa: null, enviando: false
};

async function waChamar(corpo){
  const { data, error } = await FUNIL.sb.functions.invoke("whats", { body: corpo });
  if(error){
    let msg = error.message || "erro";
    try{ const j = await error.context.json(); msg = j.erro || msg; }catch(e){}
    if(msg === "sem_chave") WA.semChave = true;
    throw new Error(msg);
  }
  WA.semChave = false;
  return data;
}

/* Guarda o arquivo no Storage (bucket privado "envios") e manda pelo WhatsApp da Bia.
   Usado aqui e na página do voucher. Só depende de FUNIL. */
async function waEnviarArquivo(chatId, blob, nome, legenda){
  const mime = blob.type || (/\.pdf$/i.test(nome) ? "application/pdf" : "image/png");
  const ext = (nome.match(/\.([a-z0-9]+)$/i)||[])[1] || (mime.split("/")[1]||"bin");
  const caminho = chatId.replace(/[^A-Za-z0-9_-]/g,"") + "/" + Date.now() + "-" + Math.random().toString(36).slice(2,8) + "." + ext.toLowerCase();
  const st = FUNIL.sb.storage.from("envios");
  const up = await st.upload(caminho, blob, { contentType: mime, upsert: false });
  if(up.error) throw new Error("não consegui guardar o arquivo (" + up.error.message + ")");
  const sg = await st.createSignedUrl(caminho, 3600);
  if(sg.error) throw new Error("não consegui gerar o link do arquivo");
  return waChamar({ acao:"arquivo", chatId, url: sg.data.signedUrl,
    tipo: mime.startsWith("image/") ? "imagem" : "documento", legenda: legenda||"", nome, mime });
}
async function waChatPorTelefone(tel){
  const t8 = String(tel||"").replace(/\D/g,"").slice(-8); if(t8.length < 8) return null;
  const { data } = await FUNIL.sb.from("funil_whats").select("chat_id,humano,ultima_em").eq("tel8", t8).order("ultima_em",{ascending:false}).limit(1);
  return (data && data[0]) || null;
}

const waT8 = t => String(t||"").replace(/\D/g,"").slice(-8);
function waPacienteDoChat(c){
  if(!c || !c.tel8) return null;
  for(const p of pacientes.values()){ if(waT8(p.telefone) === c.tel8) return p; }
  return null;
}
function waChatDoPaciente(p){
  const t = waT8(p && p.telefone); if(t.length < 8) return null;
  let melhor = null;
  for(const c of WA.chats.values()){ if(c.tel8 === t && (!melhor || (c.ultima_em||"") > (melhor.ultima_em||""))) melhor = c; }
  return melhor;
}
// paciente falou por último, nos últimos 30 dias, e ninguém abriu a conversa no site depois disso
const waAguardando = c => !c.ignorado && c.ultima_de === "user" && (c.ultima_em||"") > new Date(Date.now()-30*864e5).toISOString()
  && (!c.visto_em || (c.ultima_em||"") > c.visto_em);
function waNome(c){ const p = waPacienteDoChat(c); return (p && p.nome) || c.nome || telBR(c.telefone) || "Sem nome"; }
function waQuando(isoStr){
  if(!isoStr) return "";
  const d = new Date(isoStr), agora = new Date();
  const mesmoDia = d.toDateString() === agora.toDateString();
  const ontem = new Date(agora - 864e5).toDateString() === d.toDateString();
  const hm = d.toLocaleTimeString("pt-BR",{hour:"2-digit",minute:"2-digit",timeZone:"America/Sao_Paulo"});
  if(mesmoDia) return hm;
  if(ontem) return "ontem " + hm;
  return d.toLocaleDateString("pt-BR",{day:"2-digit",month:"2-digit",timeZone:"America/Sao_Paulo"}) + " " + hm;
}

/* ---------- dados ---------- */
async function waLerTabela(){
  const linhas = [];
  for(let de=0;;de+=1000){
    const { data, error } = await FUNIL.sb.from("funil_whats").select("*").order("ultima_em",{ascending:false}).range(de, de+999);
    if(error) throw error;
    linhas.push(...data);
    if(data.length < 1000) break;
  }
  // contatos marcados como "não é paciente" (tabela funil_ignorados) não contam como "Aguardando",
// mas continuam em "Todas" e na busca
  try{
    const { data:ig } = await FUNIL.sb.from("funil_ignorados").select("id");
    WA.ignorados = new Set((ig||[]).map(r=>String(r.id).replace(/^k/,"")));
  }catch(e){ WA.ignorados = WA.ignorados || new Set(); }
  linhas.forEach(c=>{ c.ignorado = WA.ignorados.has(c.tel8); });
  WA.chats = new Map(linhas.map(c=>[c.chat_id, c]));
  WA.carregou = true;
  waBadge();
  if(modo === "whats") waRenderLista();
}
async function waAtualizar(paginas){
  try{ await waChamar({ acao:"atualizar", paginas: paginas||1 }); }
  catch(e){ if(modo==="whats") waRenderAviso(); return; }
  await waLerTabela();
}
function waIniciar(){
  waLerTabela().catch(()=>{});
  FUNIL.sb.channel("rt-whats")
    .on("postgres_changes",{event:"*",schema:"public",table:"funil_whats"},()=>{
      clearTimeout(WA._t); WA._t = setTimeout(()=>waLerTabela().catch(()=>{}), 400);
    }).subscribe();
  // primeira carga mais funda (conversas antigas), depois só as recentes
  waAtualizar(WA.chats.size ? 1 : 5);
  waAgendarLista();
}
function waAgendarLista(){
  clearInterval(WA.timerLista);
  // com a aba aberta: a cada 20 s; nas outras abas: a cada 90 s (só para o contador)
  WA.timerLista = setInterval(()=>{ if(!document.hidden) waAtualizar(1); }, modo==="whats" ? 20000 : 90000);
}

function waBadge(){
  const b = document.getElementById("viewWhats"); if(!b) return;
  const n = [...WA.chats.values()].filter(waAguardando).length;
  b.textContent = n ? "WhatsApp · " + n : "WhatsApp";
  b.classList.toggle("alerta", n > 0);
}

/* ---------- tela ---------- */
function renderWhats(){
  const box = $("#whatsview");
  if(!box.dataset.montado){
    box.dataset.montado = "1";
    box.innerHTML =
      '<div class="wa">' +
        '<div class="wa-lista">' +
          '<div class="wa-busca"><input type="text" id="waBusca" placeholder="Buscar nome ou telefone">' +
          '<div class="wa-filtros" role="group" aria-label="Filtro">' +
            '<button data-f="aguardando">Aguardando</button><button data-f="equipe">Com a equipe</button><button data-f="todas">Todas</button>' +
          '</div></div>' +
          '<div id="waAviso"></div>' +
          '<div class="wa-itens" id="waItens"></div>' +
        '</div>' +
        '<div class="wa-conversa" id="waConversa"></div>' +
      '</div>';
    $("#waBusca").addEventListener("input", e=>{ WA.busca = e.target.value; waRenderLista(); });
    box.querySelectorAll(".wa-filtros button").forEach(b=>b.addEventListener("click",()=>{ WA.filtro = b.dataset.f; waRenderLista(); }));
  }
  waRenderAviso();
  waRenderLista();
  waRenderConversa();
}
function waRenderAviso(){
  const a = document.getElementById("waAviso"); if(!a) return;
  a.textContent = "";
  if(WA.semChave){
    const m = el("div","msg err","Falta guardar a chave do GPT Maker no Supabase. Sem ela o site não lê nem envia mensagens. Peça ao Claude para concluir a ligação.");
    a.appendChild(m);
  }
}
function waRenderLista(){
  const box = document.getElementById("waItens"); if(!box) return;
  document.querySelectorAll(".wa-filtros button").forEach(b=>b.setAttribute("aria-pressed", String(b.dataset.f===WA.filtro)));
  const q = WA.busca.trim().toLowerCase(), qd = q.replace(/\D/g,"");
  let lista = [...WA.chats.values()];
  if(q){
    lista = lista.filter(c => waNome(c).toLowerCase().includes(q) || (qd.length>=3 && String(c.telefone||"").includes(qd)));
  }else if(WA.filtro === "aguardando"){
    lista = lista.filter(waAguardando);
  }else if(WA.filtro === "equipe"){
    lista = lista.filter(c=>c.humano);
  }
  lista.sort((a,b)=>(b.ultima_em||"").localeCompare(a.ultima_em||""));
  box.textContent = "";
  if(!WA.carregou){ box.appendChild(el("div","wa-vazio","Carregando conversas…")); return; }
  if(!lista.length){
    box.appendChild(el("div","wa-vazio", q ? "Nenhuma conversa com esse nome ou telefone." :
      WA.filtro==="aguardando" ? "Nenhum paciente esperando resposta. 👏" : "Nenhuma conversa aqui."));
    return;
  }
  for(const c of lista.slice(0, 300)){
    const it = el("button","wa-item" + (c.chat_id===WA.aberto ? " on" : ""));
    const p = waPacienteDoChat(c);
    const topo = el("div","wa-item-top");
    topo.append(el("strong",null,waNome(c)), el("span","wa-hora",waQuando(c.ultima_em)));
    const linha = el("div","wa-item-txt", (c.ultima_de==="user" ? "" : "↪ ") + (c.ultima || ""));
    const tags = el("div","wa-tags");
    if(waAguardando(c)) tags.appendChild(el("span","wa-tag wa-tag-esp","Aguardando resposta"));
    tags.appendChild(el("span","wa-tag", c.humano ? "Equipe" : "Bia"));
    if(c.ignorado) tags.appendChild(el("span","wa-tag","Não é paciente"));
    else if(!p) tags.appendChild(el("span","wa-tag wa-tag-sem","Sem ficha"));
    it.append(topo, linha, tags);
    it.addEventListener("click",()=>waAbrir(c.chat_id));
    box.appendChild(it);
  }
}

async function waAbrir(chatId, textoPronto){
  if(WA.aberto && WA.aberto !== chatId){
    const t = document.getElementById("waTexto"); if(t) WA.rascunho[WA.aberto] = t.value;
  }
  WA.aberto = chatId; WA.msgs = []; WA.pagina = 1; WA.temMais = false;
  if(textoPronto) WA.rascunho[chatId] = textoPronto;
  document.querySelector(".wa")?.classList.add("com-conversa");
  waRenderLista(); waRenderConversa(true);
  await waCarregarMensagens();
  // marca como vista no site
  const c = WA.chats.get(chatId);
  if(c){
    c.visto_em = new Date().toISOString(); waBadge(); waRenderLista();
    FUNIL.sb.from("funil_whats").update({ visto_em: c.visto_em, visto_por: FUNIL._email || null }).eq("chat_id", chatId).then(()=>{});
  }
  clearInterval(WA.timerConversa);
  WA.timerConversa = setInterval(()=>{ if(!document.hidden && modo==="whats" && WA.aberto===chatId) waCarregarMensagens(true); }, 10000);
}
async function waCarregarMensagens(silencioso){
  const id = WA.aberto; if(!id) return;
  try{
    const r = await waChamar({ acao:"mensagens", chatId:id, pagina:1 });
    if(WA.aberto !== id) return;
    const antes = WA.msgs.length ? WA.msgs[WA.msgs.length-1].id : null;
    // mantém páginas antigas já carregadas e troca só a mais recente
    const ids = new Set(r.mensagens.map(m=>m.id));
    const velhas = WA.pagina > 1 ? WA.msgs.filter(m=>!ids.has(m.id) && (m.em||"") < (r.mensagens[0]?.em||"")) : [];
    WA.msgs = velhas.concat(r.mensagens);
    if(WA.pagina === 1) WA.temMais = r.temMais;
    const depois = WA.msgs.length ? WA.msgs[WA.msgs.length-1].id : null;
    if(!silencioso || antes !== depois) waRenderMensagens(!silencioso || antes !== depois);
  }catch(e){
    if(!silencioso){ waRenderAviso(); const b = document.getElementById("waMsgs"); if(b){ b.textContent=""; b.appendChild(el("div","wa-vazio","Não consegui abrir a conversa: "+e.message)); } }
  }
}
async function waMaisAntigas(){
  const id = WA.aberto; if(!id) return;
  try{
    const r = await waChamar({ acao:"mensagens", chatId:id, pagina: WA.pagina+1 });
    if(WA.aberto !== id) return;
    WA.pagina++; WA.temMais = r.temMais;
    const ids = new Set(WA.msgs.map(m=>m.id));
    WA.msgs = r.mensagens.filter(m=>!ids.has(m.id)).concat(WA.msgs);
    const box = document.getElementById("waMsgs"); const h0 = box ? box.scrollHeight : 0;
    waRenderMensagens(false);
    if(box) box.scrollTop = box.scrollHeight - h0;
  }catch(e){ toast("Não consegui buscar as mensagens antigas."); }
}

function waRenderConversa(carregando){
  const box = document.getElementById("waConversa"); if(!box) return;
  box.textContent = "";
  const c = WA.chats.get(WA.aberto);
  if(!c){ box.appendChild(el("div","wa-vazio wa-escolha","Escolha uma conversa ao lado para ler e responder.")); return; }
  const p = waPacienteDoChat(c);

  const h = el("div","wa-cab");
  const volta = el("button","btn btn-sm btn-ghost wa-volta","‹ Conversas");
  volta.addEventListener("click",()=>{ document.querySelector(".wa")?.classList.remove("com-conversa"); });
  const id = el("div","wa-cab-id");
  id.append(el("strong",null,waNome(c)), el("span",null, telBR(c.telefone) + (c.humano ? " · com a equipe (Bia pausada)" : " · Bia respondendo")));
  const acoes = el("div","wa-cab-acoes");
  if(c.ignorado && !p){
    /* contato da equipe / não paciente: sem ficha */
  }else if(p){
    const bf = el("button","btn btn-sm","Abrir ficha"); bf.addEventListener("click",()=>abrirDrawer(p.id)); acoes.appendChild(bf);
  }else{
    const bn = el("button","btn btn-sm","Criar ficha"); bn.title = "Cadastra como paciente novo (A classificar)";
    bn.addEventListener("click",()=>waCriarFicha(c)); acoes.appendChild(bn);
  }
  const bh = el("button","btn btn-sm", c.humano ? "Devolver para a Bia" : "Assumir conversa");
  bh.title = c.humano ? "A Bia volta a responder sozinha" : "A Bia para de responder; a equipe conversa pelo site";
  bh.addEventListener("click",()=>waTrocarHumano(c, !c.humano, bh));
  acoes.appendChild(bh);
  h.append(volta, id, acoes);

  const msgs = el("div","wa-msgs"); msgs.id = "waMsgs";
  if(carregando) msgs.appendChild(el("div","wa-vazio","Carregando mensagens…"));

  const comp = el("form","wa-comp");
  const ta = el("textarea"); ta.id = "waTexto"; ta.rows = 2; ta.placeholder = "Escreva a mensagem… (Enter envia, Shift+Enter quebra linha)";
  ta.value = WA.rascunho[c.chat_id] || "";
  ta.addEventListener("input",()=>{ WA.rascunho[c.chat_id] = ta.value; });
  ta.addEventListener("keydown",e=>{ if(e.key==="Enter" && !e.shiftKey && !e.isComposing){ e.preventDefault(); comp.requestSubmit(); } });
  const be = el("button","btn btn-primary","Enviar"); be.type = "submit";
  const fi = el("input"); fi.type = "file"; fi.accept = "image/*,application/pdf"; fi.hidden = true;
  const ba = el("button","btn wa-anexo","📎 Foto / PDF"); ba.type = "button"; ba.title = "Enviar foto ou PDF (o texto escrito vai junto)";
  ba.addEventListener("click",()=>fi.click());
  fi.addEventListener("change", async ()=>{
    const f = fi.files && fi.files[0]; fi.value = ""; if(!f) return;
    if(f.size > 15*1024*1024){ toast("Arquivo grande demais (máximo 15 MB)."); return; }
    if(!confirm("Enviar \"" + f.name + "\" para " + waNome(c) + (ta.value.trim() ? ", com o texto escrito como legenda?" : "?"))) return;
    ba.disabled = true; be.disabled = true; ba.textContent = "…";
    try{
      const legenda = ta.value.trim();
      await waEnviarArquivo(c.chat_id, f, f.name, legenda);
      ta.value = ""; delete WA.rascunho[c.chat_id];
      c.humano = true; c.ultima_de = "assistant"; c.ultima_em = new Date().toISOString();
      WA.msgs.push({ id:"local"+Date.now(), de:"equipe", quem:FUNIL._nome||"Equipe", texto:(legenda||"") , documento: f.type.startsWith("image/") ? null : "#", arquivo:f.name, imagem: f.type.startsWith("image/") ? URL.createObjectURL(f) : null, em:c.ultima_em });
      waRenderMensagens(true); waRenderLista();
      toast("Arquivo enviado.");
      setTimeout(()=>waCarregarMensagens(true), 3000);
    }catch(e){ toast("Não enviou: " + e.message); }
    finally{ ba.disabled = false; be.disabled = false; ba.textContent = "📎 Foto / PDF"; }
  });
  comp.append(fi, ba, ta, be);
  comp.addEventListener("submit", e=>{ e.preventDefault(); waEnviar(ta, be); });
  const nota = el("div","wa-nota", c.humano ? "Sai pelo WhatsApp da Bia, com o seu nome registrado aqui no site." :
    "Ao enviar, a conversa passa para a equipe e a Bia para de responder este paciente (dá para devolver depois).");

  box.append(h, msgs, comp, nota);
  if(!carregando) waRenderMensagens(true);
  if(ta.value) setTimeout(()=>{ ta.focus(); ta.setSelectionRange(ta.value.length, ta.value.length); }, 50);
}
function waRenderMensagens(rolarFim){
  const box = document.getElementById("waMsgs"); if(!box) return;
  const perto = box.scrollHeight - box.scrollTop - box.clientHeight < 80;
  box.textContent = "";
  if(WA.temMais){
    const b = el("button","btn btn-sm btn-ghost wa-mais","Mensagens anteriores");
    b.addEventListener("click", waMaisAntigas); box.appendChild(b);
  }
  if(!WA.msgs.length){ box.appendChild(el("div","wa-vazio","Nenhuma mensagem nesta conversa.")); return; }
  let diaAnt = "";
  for(const m of WA.msgs){
    const dia = m.em ? new Date(m.em).toLocaleDateString("pt-BR",{weekday:"short",day:"2-digit",month:"2-digit",timeZone:"America/Sao_Paulo"}) : "";
    if(dia && dia !== diaAnt){ box.appendChild(el("div","wa-dia",dia)); diaAnt = dia; }
    if(m.de === "sistema"){ box.appendChild(el("div","wa-sis", m.texto)); continue; }
    const b = el("div","wa-b wa-" + m.de);
    if(m.de !== "paciente") b.appendChild(el("div","wa-quem", m.de==="bia" ? "Bia (IA)" : (m.quem || "Equipe")));
    if(m.imagem){
      const a = el("a"); a.href = m.imagem; a.target = "_blank"; a.rel = "noopener";
      const img = el("img"); img.src = m.imagem; img.alt = "Imagem enviada"; img.loading = "lazy"; a.appendChild(img); b.appendChild(a);
    }
    if(m.audio){
      const au = el("audio"); au.controls = true; au.preload = "none"; au.src = m.audio; b.appendChild(au);
      if(m.transcricao) b.appendChild(el("div","wa-transc","“"+m.transcricao+"”"));
    }
    if(m.documento){
      const a = el("a","wa-doc","📄 " + (m.arquivo || "Documento")); a.href = m.documento; a.target = "_blank"; a.rel = "noopener"; b.appendChild(a);
    }
    if(m.texto) b.appendChild(el("div","wa-txt", m.texto));
    b.appendChild(el("div","wa-h", waQuando(m.em)));
    box.appendChild(b);
  }
  if(rolarFim || perto) box.scrollTop = box.scrollHeight;
}

async function waEnviar(ta, be){
  const c = WA.chats.get(WA.aberto); const texto = ta.value.trim();
  if(!c || !texto || WA.enviando) return;
  WA.enviando = true; be.disabled = true; be.textContent = "Enviando…";
  try{
    await waChamar({ acao:"enviar", chatId:c.chat_id, texto });
    ta.value = ""; delete WA.rascunho[c.chat_id];
    c.humano = true; c.ultima = texto; c.ultima_de = "assistant"; c.ultima_em = new Date().toISOString();
    WA.msgs.push({ id:"local"+Date.now(), de:"equipe", quem:FUNIL._nome || "Equipe", texto, em:c.ultima_em });
    waRenderMensagens(true); waRenderLista(); waBadge();
    const p = waPacienteDoChat(c);
    if(p){ const q = Object.assign({}, p); q.ultimaMensagem = texto.replace(/\s+/g," ").slice(0,120); q.ultimaMensagemEm = c.ultima_em; salvar(q); }
    setTimeout(()=>waCarregarMensagens(true), 2500);
  }catch(e){
    toast(WA.semChave ? "Falta a chave do GPT Maker no Supabase." : "Não enviou: " + e.message);
  }finally{
    WA.enviando = false; be.disabled = false; be.textContent = "Enviar";
  }
}
async function waTrocarHumano(c, assumir, botao){
  botao.disabled = true;
  try{
    await waChamar({ acao: assumir ? "assumir" : "devolver", chatId:c.chat_id });
    c.humano = assumir;
    toast(assumir ? "Conversa com a equipe. A Bia não responde mais este paciente." : "Conversa devolvida para a Bia.");
    waRenderConversa(); waRenderLista();
  }catch(e){ toast("Não consegui: " + e.message); botao.disabled = false; }
}
function waCriarFicha(c){
  const nome = prompt("Nome do paciente:", c.nome || "");
  if(nome === null) return;
  const p = {
    id: novoId(), nome: nome.trim() || c.nome || "", telefone: c.telefone, etapa: "triagem",
    tratamento: "A definir", convenio: "Não sabe", pagamento: "A definir", modalidade: "Online", local: "Online",
    origem: "Outro", fonte: "WhatsApp (site)", opme: 0, valorProposta: 0, historico: [],
    criadoEm: c.criado_em || new Date().toISOString(),
    ultimaMensagem: (c.ultima||"").slice(0,120), ultimaMensagemEm: c.ultima_em
  };
  salvar(p); toast("Ficha criada em A classificar."); waRenderConversa(); waRenderLista();
}

/* Usado pelos botões "WhatsApp" do painel: abre a conversa aqui no site com a mensagem pronta.
   Se o paciente ainda não tem conversa com a Bia, cai no WhatsApp normal. */
function waAbrirComTexto(p, txt){
  const c = waChatDoPaciente(p);
  if(!c) return false;
  fecharOverlays();
  trocarModo("whats");
  waAbrir(c.chat_id, txt);
  toast("Mensagem pronta. Confira e clique em Enviar.");
  return true;
}
