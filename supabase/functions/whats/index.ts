// Função "whats": ponte entre o painel e o GPT Maker (WhatsApp da Bia).
// A chave do GPT Maker fica guardada como segredo GPTMAKER_TOKEN no Supabase,
// nunca no site. Só administradores (tabela perfis) podem usar.
//
// Ações (POST JSON {acao, ...}):
//   atualizar {paginas?}        -> relê as conversas mais recentes e grava em funil_whats
//   mensagens {chatId, pagina?} -> mensagens da conversa (página 1 = mais recentes)
//   enviar    {chatId, texto}   -> assume a conversa (Bia para) e envia a mensagem
//   assumir   {chatId}          -> equipe assume; a Bia para de responder
//   devolver  {chatId}          -> devolve a conversa para a Bia
//   iniciar   {telefone, texto} -> começa conversa nova com um número que ainda não falou com a Bia
//   transcrever {sala, caminho} -> transcreve um trecho de áudio da teleconsulta (agente "Resumo de Consultas")
//   resumir     {sala}          -> gera o resumo da consulta a partir da transcrição
//   situacao_canal              -> diz se o WhatsApp da Bia está conectado no GPT Maker
//   gastos_meta {dias}          -> (agendador) grava o gasto do Meta Ads por dia e campanha em funil_gastos
//   arquivo   {chatId, url, tipo:'imagem'|'documento', legenda?, nome?, mime?}
//             -> envia imagem/PDF já guardado no Storage (bucket "envios", link assinado)

const WORKSPACE = "3DB36E552D5A00174085B2C1E91B873D";
const AGENTE_RESUMO = "3FB07B55850BE022B42DDA18E3B5B6A6";   // agente "Resumo de Consultas" (sem canal)
const espera = (ms: number) => new Promise((r) => setTimeout(r, ms));
const API = "https://api.gptmaker.ai/v2";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
let SB_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...CORS, "Content-Type": "application/json" } });

async function gm(path: string, init: RequestInit = {}) {
  const token = Deno.env.get("GPTMAKER_TOKEN");
  if (!token) throw new Error("sem_chave");
  const r = await fetch(API + path, {
    ...init,
    headers: { Authorization: "Bearer " + token, "Content-Type": "application/json", ...(init.headers || {}) },
  });
  const txt = await r.text();
  let corpo: any = null;
  try { corpo = txt ? JSON.parse(txt) : null; } catch { corpo = txt; }
  if (!r.ok) throw new Error("GPT Maker " + r.status + ": " + (corpo?.error || String(txt).slice(0, 200)));
  return corpo;
}

// chamadas ao banco com o login de quem pediu (as regras de acesso valem normalmente)
function rest(auth: string, path: string, init: RequestInit = {}) {
  return fetch(SB_URL + "/rest/v1/" + path, {
    ...init,
    headers: { apikey: SB_KEY, Authorization: auth, "Content-Type": "application/json", ...(init.headers || {}) },
  });
}

async function registrarEnvio(auth: string, chatId: string, texto: string, email: string) {
  try {
    const pr = await rest(auth, "perfis?select=nome&email=eq." + encodeURIComponent(String(email || "").toLowerCase()));
    const nome = pr.ok ? ((await pr.json())[0]?.nome || email) : email;
    await rest(auth, "funil_whats_envios", {
      method: "POST", headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ chat_id: chatId, texto: texto.slice(0, 2000), por: email, por_nome: nome }),
    });
  } catch { /* só para mostrar o nome; não impede o envio */ }
}

const AGENTE_BIA = "3F666308EBFC10E017FACE855605F1BA";
// A conversa voltou para a Bia: ela lê as últimas mensagens e responde o que ficou pendente.
// O GPT Maker só faz a Bia falar quando chega mensagem nova; aqui pedimos a resposta ao agente
// numa conversa à parte (com o histórico) e enviamos o texto na conversa do paciente.
async function biaRetoma(chatId: string, quem = "Bia") {
  const brutas = await gm(`/chat/${encodeURIComponent(chatId)}/messages?page=1&pageSize=40`);
  const ms = (Array.isArray(brutas) ? brutas : []).map(mensagem).filter(Boolean)
    .filter((m: any) => m.de !== "sistema" && (m.texto || m.transcricao))
    .sort((a: any, b: any) => String(a.em).localeCompare(String(b.em)));
  if (!ms.length || ms[ms.length - 1].de !== "paciente") return { ok: false, motivo: "nada_pendente" };
  const linhas = ms.slice(-24).map((m: any) => (m.de === "paciente" ? "Paciente" : m.de === "equipe" ? `Equipe (${m.quem || "humano"})` : "Bia")
    + ": " + String(m.texto || m.transcricao || "").replace(/\s+/g, " ").slice(0, 600));
  const ctx = "RT" + chatId.slice(-10) + Date.now();
  const prompt = "[RETOMADA DE CONVERSA DO WHATSAPP]\nEsta conversa estava com a equipe humana e voltou para você agora. "
    + "Leia o histórico abaixo (do mais antigo para o mais novo) e responda, como a Bia e seguindo todas as suas regras, "
    + "à(s) última(s) mensagem(ns) do paciente que ainda não foram respondidas. Continue a conversa de onde parou, sem se apresentar de novo "
    + "e sem repetir o que a equipe já disse. Escreva SOMENTE o texto da mensagem que será enviada ao paciente.\n\nHistórico:\n" + linhas.join("\n");
  const r = await gm(`/agent/${AGENTE_BIA}/conversation`, { method: "POST", body: JSON.stringify({ contextId: ctx, chatName: ctx, prompt }) });
  let texto = String(r?.message || "").trim();
  let tmp: string | null = null;
  for (let t = 0; t < 15 && !texto; t++) {
    await espera(3000);
    try {
      const cs = await gm(`/workspace/${WORKSPACE}/chats?page=1&pageSize=3&query=${ctx}`);
      const c = (Array.isArray(cs) ? cs : []).find((x: any) => x.name === ctx);
      if (!c) continue;
      tmp = c.id;
      const rs = await gm(`/chat/${c.id}/messages?page=1&pageSize=5`);
      const a = (Array.isArray(rs) ? rs : []).find((m: any) => m.role === "assistant" && String(m.text || "").trim());
      if (a) texto = String(a.text).trim();
    } catch { /* tenta de novo */ }
  }
  // apaga a conversa auxiliar
  try {
    if (!tmp) { const cs = await gm(`/workspace/${WORKSPACE}/chats?page=1&pageSize=3&query=${ctx}`); tmp = (Array.isArray(cs) ? cs : []).find((x: any) => x.name === ctx)?.id || null; }
    if (tmp) await gm(`/chat/${tmp}`, { method: "DELETE" });
  } catch { /* ok */ }
  if (!texto) return { ok: false, motivo: "sem_resposta" };
  await gm(`/chat/${encodeURIComponent(chatId)}/send-message`, { method: "POST", body: JSON.stringify({ message: texto.slice(0, 3000) }) });
  try {
    const SR = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
    await fetch(SB_URL + "/rest/v1/funil_whats_envios", { method: "POST",
      headers: { apikey: SR, Authorization: "Bearer " + SR, "Content-Type": "application/json", Prefer: "return=minimal" },
      body: JSON.stringify({ chat_id: chatId, texto: texto.slice(0, 2000), por: "bia@alinhaface", por_nome: quem }) });
  } catch { /* só para o histórico */ }
  return { ok: true, texto };
}
const emSegundoPlano = (p: Promise<unknown>) => {
  const er = (globalThis as any).EdgeRuntime;
  if (er?.waitUntil) er.waitUntil(p.catch(() => {})); else p.catch(() => {});
};

// Ana Clara atende de terça a sexta, das 14h às 18h (horário de Brasília); fora disso a Bia cuida das conversas
function horarioDaEquipe(d = new Date()) {
  const f = new Intl.DateTimeFormat("en-US", { timeZone: "America/Sao_Paulo", weekday: "short", hour: "2-digit", hourCycle: "h23" }).formatToParts(d);
  const dia = f.find((x) => x.type === "weekday")!.value, h = Number(f.find((x) => x.type === "hour")!.value);
  return ["Tue", "Wed", "Thu", "Fri"].includes(dia) && h >= 14 && h < 18;
}
const iso = (ms: unknown) => (typeof ms === "number" && ms > 0 ? new Date(ms).toISOString() : null);
const so8 = (t: unknown) => String(t || "").replace(/\D/g, "").slice(-8);

function linhaDoChat(c: any) {
  return {
    chat_id: c.id,
    tel8: so8(c.whatsappPhone) || null,
    telefone: String(c.whatsappPhone || ""),
    nome: c.name || c.userName || "",
    foto: c.picture || null,
    ultima: String(c.conversation || "").replace(/\s+/g, " ").slice(0, 160),
    ultima_de: c.role || null,
    ultima_em: iso(c.time),
    humano: !!c.humanTalk,
    nao_lidas: Number(c.unReadCount) || 0,
    criado_em: iso(c.createdAt),
    atualizado_em: new Date().toISOString(),
  };
}

function mensagem(m: any) {
  if (m.type === "TOOL_CALLS") return null;
  const texto = String(m.text || "");
  if (m.role === "system" && !texto.trim()) return null;
  const de = m.role === "user" ? "paciente" : m.role === "system" ? "sistema" : m.userName ? "equipe" : "bia";
  return {
    id: m.id, de, quem: m.userName || null, tipo: m.type, texto,
    em: iso(m.time),
    imagem: m.imageUrl || null, audio: m.audioUrl || null,
    documento: m.documentUrl || null, arquivo: m.fileName || null,
    transcricao: m.midiaContent || null,
  };
}

async function gravarChats(auth: string, linhas: any[]) {
  if (!linhas.length) return;
  const r = await rest(auth, "funil_whats?on_conflict=chat_id", {
    method: "POST",
    headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify(linhas),
  });
  if (!r.ok) throw new Error("Banco: " + (await r.text()).slice(0, 200));
}

// ---------- avisos de consulta para os cirurgiões (fila funil_avisos_medico) ----------
async function processarAvisos() {
  const SR = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (!SR) throw new Error("sem chave de serviço");
  const db = (path: string, init: RequestInit = {}) => fetch(SB_URL + "/rest/v1/" + path, {
    ...init, headers: { apikey: SR, Authorization: "Bearer " + SR, "Content-Type": "application/json", ...(init.headers || {}) },
  });
  // espera 1 minuto depois da última mudança (a equipe costuma salvar a ficha mais de uma vez)
  const limite = new Date(Date.now() - 60000).toISOString();
  const r = await db("funil_avisos_medico?select=*&situacao=eq.fila&order=criado_em.asc&limit=50");
  const fila: any[] = r.ok ? await r.json() : [];
  if (!fila.length) return { ok: true, enviados: 0 };
  // por paciente + cirurgião, só vale o aviso mais recente
  const ultimo = new Map<string, any>();
  const classe = (a: any) => a.tipo === "alerta" ? "alerta" + a.id
    : String(a.tipo || "").startsWith("lembrete") || a.tipo === "presencial" || a.tipo === "confirmacao_paciente" ? a.tipo : (a.tipo === "cancelada" ? "c" : "m");
  for (const a of fila) ultimo.set(a.paciente_id + "|" + a.email + "|" + classe(a), a);
  let enviados = 0;
  const canalDe = async () => {
    const lista = await gm(`/workspace/${WORKSPACE}/chats?page=1&pageSize=5`);
    return (Array.isArray(lista) ? lista : []).map((c: any) => c.channelId).find(Boolean);
  };
  let canal: string | undefined;
  for (const a of fila) {
    const lembrete = String(a.tipo || "").startsWith("lembrete") || a.tipo === "presencial" || a.tipo === "alerta";   // sem minuto de espera
    const doPaciente = a.tipo === "lembrete_paciente" || a.tipo === "confirmacao_paciente";   // não tira a conversa da Bia
    const chave = a.paciente_id + "|" + a.email + "|" + classe(a);
    if (ultimo.get(chave) !== a) {
      await db("funil_avisos_medico?id=eq." + a.id, { method: "PATCH", body: JSON.stringify({ situacao: "substituido" }) });
      continue;
    }
    if (!lembrete && a.criado_em > limite) continue;   // aviso de agenda: ainda dentro do minuto de espera
    // aviso de remarcação/nova anula um cancelamento pendente do mesmo paciente e cirurgião, e vice-versa
    const oposto = lembrete || doPaciente ? null : ultimo.get(a.paciente_id + "|" + a.email + "|" + (a.tipo === "cancelada" ? "m" : "c"));
    if (oposto && oposto.criado_em > a.criado_em) {
      await db("funil_avisos_medico?id=eq." + a.id, { method: "PATCH", body: JSON.stringify({ situacao: "substituido" }) });
      continue;
    }
    try {
      let tel = String(a.telefone || "").replace(/\D/g, "");
      if (tel.length === 10 || tel.length === 11) tel = "55" + tel;
      const t8 = tel.slice(-8);
      const cw = await db("funil_whats?select=chat_id&tel8=eq." + t8 + "&limit=1");
      let chatId: string | null = cw.ok ? ((await cw.json())[0]?.chat_id || null) : null;
      if (chatId) {
        // lembrete ao paciente: a Bia continua atendendo a conversa
        if (!doPaciente) { try { await gm(`/chat/${encodeURIComponent(chatId)}/start-human`, { method: "PUT" }); } catch { /* já estava com a equipe */ } }
        await gm(`/chat/${encodeURIComponent(chatId)}/send-message`, { method: "POST", body: JSON.stringify({ message: a.texto }) });
      } else {
        canal = canal || await canalDe();
        if (!canal) throw new Error("não achei o canal da Bia");
        await gm(`/channel/${encodeURIComponent(canal)}/start-conversation`, { method: "POST", body: JSON.stringify({ phone: tel, message: a.texto }) });
        // a Bia não deve responder o cirurgião: põe a conversa nova com a equipe
        for (let t = 0; t < 4 && !chatId; t++) {
          await espera(1500);
          const novos = await gm(`/workspace/${WORKSPACE}/chats?page=1&pageSize=20`);
          chatId = (Array.isArray(novos) ? novos : []).find((c: any) => so8(c.whatsappPhone) === t8)?.id || null;
        }
        if (chatId && !doPaciente) { try { await gm(`/chat/${encodeURIComponent(chatId)}/start-human`, { method: "PUT" }); } catch { /* ok */ } }
      }
      if (chatId) {
        await db("funil_whats_envios", { method: "POST", headers: { Prefer: "return=minimal" },
          body: JSON.stringify({ chat_id: chatId, texto: a.texto.slice(0, 2000), por: "avisos@alinhaface", por_nome: String(a.tipo || "").startsWith("lembrete") ? "Lembrete automático" : "Aviso automático" }) });
        if (!doPaciente) await db("funil_whats?chat_id=eq." + encodeURIComponent(chatId), { method: "PATCH", body: JSON.stringify({ humano: true }) });
      }
      await db("funil_avisos_medico?id=eq." + a.id, { method: "PATCH", body: JSON.stringify({ situacao: "enviado", enviado_em: new Date().toISOString() }) });
      enviados++;
    } catch (e) {
      const n = (a.tentativas || 0) + 1;
      await db("funil_avisos_medico?id=eq." + a.id, { method: "PATCH",
        body: JSON.stringify({ tentativas: n, erro: String((e as Error).message || e).slice(0, 300), situacao: n >= 5 ? "erro" : "fila" }) });
    }
  }
  return { ok: true, enviados };
}

// ---------- vigia: canal do WhatsApp, Bia sem responder, frases da Bia que podem estar erradas ----------
const SRK = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const dbs = (path: string, init: RequestInit = {}) => fetch(SB_URL + "/rest/v1/" + path, {
  ...init, headers: { apikey: SRK(), Authorization: "Bearer " + SRK(), "Content-Type": "application/json", ...(init.headers || {}) },
});
async function rpc(nome: string, args: Record<string, unknown>) {
  const r = await dbs("rpc/" + nome, { method: "POST", body: JSON.stringify(args) });
  if (!r.ok) return null;
  const t = await r.text();
  try { return t ? JSON.parse(t) : null; } catch { return null; }
}
const horaBR = (d: Date) => new Intl.DateTimeFormat("pt-BR", { timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }).format(d);
const horaLocal = (d = new Date()) => Number(new Intl.DateTimeFormat("en-US", { timeZone: "America/Sao_Paulo", hour: "2-digit", hourCycle: "h23" }).format(d));
const hojeBR = () => new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" }).format(new Date());

// WhatsApp para os administradores que têm número no perfil e avisos ligados (vai pela fila)
async function avisarEquipe(texto: string) {
  const adms = await dbs("perfis?select=email,whatsapp&papel=eq.admin&whatsapp=not.is.null&avisos_whats=is.true").then((r) => r.ok ? r.json() : []);
  if (!adms.length) return 0;
  await dbs("funil_avisos_medico", { method: "POST", headers: { Prefer: "return=minimal" },
    body: JSON.stringify(adms.map((a: any) => ({ email: a.email, telefone: a.whatsapp, tipo: "alerta", texto }))) });
  return adms.length;
}

// situação do canal no GPT Maker: true conectado, false desconectado, null se não deu para saber
function lerSituacao(c: any): boolean | null {
  if (!c || typeof c !== "object") return null;
  for (const k of ["connected", "isConnected", "conectado", "online"]) if (typeof c[k] === "boolean") return c[k];
  const s = String(c.status ?? c.connectionStatus ?? c.state ?? c.situation ?? "").toUpperCase();
  if (!s) return null;
  if (/DISCONNECT|DESCONECT|OFFLINE|CLOSE|LOGOUT|QRCODE|QR_CODE|ERROR|FAIL|PENDING/.test(s)) return false;
  if (/CONNECT|CONECTAD|ONLINE|OPEN|READY|ACTIVE|ATIVO/.test(s)) return true;
  return null;
}
async function situacaoDoCanal(canal: string) {
  const bruto: Record<string, unknown> = {};
  for (const caminho of [`/workspace/${WORKSPACE}/channels`, `/channel/${canal}`, `/agent/${AGENTE_BIA}/channels`, `/channel/${canal}/status`]) {
    try {
      const r = await gm(caminho);
      bruto[caminho] = r;
      const lista = Array.isArray(r) ? r : Array.isArray(r?.data) ? r.data : Array.isArray(r?.channels) ? r.channels : [r];
      const c = lista.find((x: any) => x && (x.id === canal || x.channelId === canal)) || (lista.length === 1 && !Array.isArray(r) ? lista[0] : null);
      const v = lerSituacao(c);
      if (v !== null) return { conectado: v, fonte: caminho, bruto };
    } catch (e) { bruto[caminho] = String((e as Error).message || e).slice(0, 200); }
  }
  return { conectado: null as boolean | null, fonte: null as string | null, bruto };
}

// frases da Bia que pedem conferência
const FRASES: { re: RegExp; titulo: string; consulta?: boolean }[] = [
  { re: /(j[aá] (tem|possui) (uma )?(consulta|avalia[cç][aã]o)|(consulta|avalia[cç][aã]o)[^.!?\n]{0,50}(ficou|est[aá]|foi) (agendad|marcad|confirmad)|agendad[oa] com sucesso|^\s*agendad[oa]\s*!?\s*$)/im,
    titulo: "Bia disse que há consulta marcada, mas não há consulta no funil", consulta: true },
  { re: /(R\$\s?\d|\b\d{1,3}(\.\d{3})+,\d{2}\b|\bcusta\b|valor (da|do) (cirurgia|tratamento|procedimento|placa) (é|fica|sai))/i,
    titulo: "Bia falou de valor" },
  { re: /(n[aã]o (é|ser[aá]|vai ser) cobrad|(seu|o) (plano|conv[eê]nio) (cobre|vai cobrir|paga|cobrir[aá])|cobertura (garantida|total))/i,
    titulo: "Bia afirmou o que o convênio cobre ou cobra" },
];

async function vigiar(arr: any[], fora: Set<string>) {
  const res: Record<string, unknown> = {};
  const agora = Date.now();
  // 1) canal do WhatsApp
  const canal = arr.map((c: any) => c.canal).find(Boolean);
  if (canal) {
    const st = await situacaoDoCanal(canal);
    let caiu = st.conectado === false, detalhe = "Os pacientes não estão recebendo resposta. Reconecte o WhatsApp no GPT Maker (Canais) lendo o QR code com o celular da Bia.";
    if (st.conectado === null) {
      // sem como perguntar ao GPT Maker: nenhuma mensagem de paciente há 3 h, entre 8h e 22h, é sinal de canal fora
      const ultimaEntrada = Math.max(0, ...arr.filter((c: any) => c.ultima_de === "user" && c.ultima_em).map((c: any) => Date.parse(c.ultima_em)));
      const h = horaLocal();
      if (h >= 11 && h < 22 && ultimaEntrada && agora - ultimaEntrada > 3 * 3600000) {
        caiu = true;
        detalhe = "Nenhuma mensagem de paciente chegou nas últimas 3 horas. Confira no GPT Maker (Canais) se o WhatsApp da Bia está conectado.";
      }
    }
    res.canal = st.conectado === null ? (caiu ? "suspeito" : "sem_dado") : (st.conectado ? "conectado" : "desconectado");
    if (caiu) {
      await rpc("abrir_alerta", { p_tipo: "canal", p_chave: "canal", p_titulo: "WhatsApp da Bia parece desconectado", p_detalhe: detalhe });
    } else {
      const desde = await rpc("fechar_alerta", { p_chave: "canal" });
      if (desde) await avisarEquipe("✅ *WhatsApp da Bia voltou a funcionar.*\nEle estava fora desde " + horaBR(new Date(desde))
        + ".\nMensagens que pacientes mandaram nesse período podem não ter chegado à Bia — vale olhar o celular do canal.");
    }
  }
  if (res.canal === "desconectado" || res.canal === "suspeito") return res;   // com o canal fora, o resto não faz sentido

  // 2) paciente sem resposta da Bia (conversa com a Bia, última mensagem do paciente entre 15 min e 6 h atrás)
  const abertos: any[] = await dbs("funil_alertas?select=id,chave,chat_id&tipo=eq.bia_sem_resposta&resolvido_em=is.null").then((r) => r.ok ? r.json() : []);
  const porChat = new Map(arr.map((c: any) => [c.chat_id, c]));
  for (const a of abertos) {   // já respondeu ou a equipe assumiu: fecha
    const c: any = porChat.get(a.chat_id);
    if (!c || c.humano || c.ultima_de !== "user") await rpc("fechar_alerta", { p_chave: a.chave });
  }
  let semResposta = 0, retomadas = 0;
  for (const c of arr) {
    if (c.humano || c.ultima_de !== "user" || !c.ultima_em || !c.tel8 || fora.has(c.tel8)) continue;
    const idade = agora - Date.parse(c.ultima_em);
    if (idade < 15 * 60000 || idade > 6 * 3600000) continue;
    semResposta++;
    const novo = await rpc("abrir_alerta", { p_tipo: "bia_sem_resposta", p_chave: "semresp:" + c.chat_id,
      p_titulo: (c.nome || "Paciente") + " está sem resposta da Bia desde " + horaBR(new Date(c.ultima_em)).slice(-5),
      p_detalhe: c.ultima || null, p_chat: c.chat_id });
    if (novo && retomadas < 3) { retomadas++; emSegundoPlano(biaRetoma(c.chat_id, "Bia (estava sem resposta)")); }
  }
  res.sem_resposta = semResposta; res.retomadas = retomadas;

  // 3) frases da Bia: confere as mensagens da Bia de 10 a 30 min atrás (dá tempo de a agenda sincronizar)
  let conferidas = 0, frases = 0;
  const recentes = arr.filter((c: any) => c.ultima_em && agora - Date.parse(c.ultima_em) < 30 * 60000 && c.tel8 && !fora.has(c.tel8)).slice(0, 15);
  for (const c of recentes) {
    let msgs: any[] = [];
    try { msgs = (await gm(`/chat/${encodeURIComponent(c.chat_id)}/messages?page=1&pageSize=12`) || []).map(mensagem).filter(Boolean); } catch { continue; }
    const daBia = msgs.filter((m: any) => m.de === "bia" && m.texto && m.em && agora - Date.parse(m.em) >= 10 * 60000 && agora - Date.parse(m.em) <= 30 * 60000);
    for (const m of daBia) {
      conferidas++;
      for (const f of FRASES) {
        if (!f.re.test(m.texto)) continue;
        let fichaId: string | null = null;
        if (f.consulta) {
          const fichas: any[] = await dbs(`funil_pacientes?select=id,dados->>dataConsulta&dados->>telefone=like.*${c.tel8}`).then((r) => r.ok ? r.json() : []);
          if (fichas.some((x: any) => String(x.dataConsulta || "") >= hojeBR())) continue;   // tem consulta mesmo: está certo
          fichaId = fichas[0]?.id || null;
        }
        const novo = await rpc("abrir_alerta", { p_tipo: "bia_frase", p_chave: "frase:" + m.id + ":" + f.titulo.slice(0, 20),
          p_titulo: f.titulo + " — " + (c.nome || "paciente"), p_detalhe: String(m.texto).replace(/\s+/g, " ").slice(0, 400), p_chat: c.chat_id, p_paciente: fichaId });
        if (novo) {
          frases++;
          if (f.consulta) await avisarEquipe("⚠️ *Confira a conversa de " + (c.nome || "um paciente") + "*\n" + f.titulo + ".\nA Bia escreveu: “"
            + String(m.texto).replace(/\s+/g, " ").slice(0, 300) + "”\nAbra o funil > Rotina do dia > Bia · conferir.");
        }
        break;
      }
    }
  }
  res.frases_conferidas = conferidas; res.frases_alertadas = frases;
  return res;
}

// ---------- gasto com anúncios do Meta (Facebook/Instagram) -> funil_gastos ----------
// Segredos: META_TOKEN (chave do usuário do sistema, só leitura de anúncios) e META_CONTAS (ex.: "act_123,act_456").
async function gastosMeta(dias: number) {
  const token = Deno.env.get("META_TOKEN") || "";
  const contas = (Deno.env.get("META_CONTAS") || "act_1845412043498364").split(",").map((x) => x.trim()).filter(Boolean);
  if (!token) return { ok: false, motivo: "falta o segredo META_TOKEN" };
  const ate = hojeBR();
  const de = new Date(Date.parse(ate + "T12:00:00Z") - (Math.max(1, Math.min(dias, 400)) - 1) * 864e5).toISOString().slice(0, 10);
  const acao = (lista: any[], tipos: string[]) => (Array.isArray(lista) ? lista : []).filter((a: any) => tipos.includes(a.action_type)).reduce((s: number, a: any) => s + (Number(a.value) || 0), 0);
  let linhas = 0;
  const erros: string[] = [];
  for (const conta of contas) {
    let url: string | null = "https://graph.facebook.com/v23.0/" + encodeURIComponent(conta) + "/insights?" + new URLSearchParams({
      level: "campaign", time_increment: "1", limit: "500",
      fields: "campaign_id,campaign_name,spend,impressions,inline_link_clicks,actions",
      time_range: JSON.stringify({ since: de, until: ate }),
    }).toString();
    while (url) {
      const r = await fetch(url, { headers: { Authorization: "Bearer " + token } });
      const j: any = await r.json().catch(() => ({}));
      if (!r.ok) { erros.push(conta + ": " + String(j?.error?.message || r.status).slice(0, 200)); break; }
      const rows = (j.data || []).map((x: any) => ({
        data: x.date_start, conta, campanha_id: String(x.campaign_id || "sem-campanha"), campanha: x.campaign_name || null,
        valor: Number(x.spend) || 0, impressoes: Number(x.impressions) || 0, cliques: Number(x.inline_link_clicks) || 0,
        conversas: acao(x.actions, ["onsite_conversion.messaging_conversation_started_7d"]),
        leads: acao(x.actions, ["lead", "onsite_conversion.lead_grouped"]),
        atualizado_em: new Date().toISOString(),
      }));
      if (rows.length) {
        const w = await dbs("funil_gastos?on_conflict=data,campanha_id", { method: "POST",
          headers: { Prefer: "resolution=merge-duplicates,return=minimal" }, body: JSON.stringify(rows) });
        if (!w.ok) { erros.push("banco: " + (await w.text()).slice(0, 200)); break; }
        linhas += rows.length;
      }
      url = j?.paging?.next || null;
    }
  }
  return { ok: !erros.length, de, ate, linhas, erros };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ erro: "use POST" }, 405);

  // fila de avisos aos cirurgiões: chamado pelo agendador do banco a cada minuto.
  // Não recebe conteúdo de fora: só envia o que o próprio banco colocou na fila.
  const corpoTxt = await req.text();
  let p: any = {};
  try { p = corpoTxt ? JSON.parse(corpoTxt) : {}; } catch { /* corpo vazio */ }
  if (p.acao === "sincronizar") {
    // chamado pelo agendador a cada 2 min: traz as conversas recentes do GPT Maker para o site
    // (o gatilho do banco cria a ficha das conversas novas). Não recebe dados de fora.
    try {
      const SR = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
      const lista = await gm(`/workspace/${WORKSPACE}/chats?page=1&pageSize=50`);
      const brutos = (Array.isArray(lista) ? lista : []).filter((c: any) => !c.isGroup && c.channelId && c.agentId !== AGENTE_RESUMO);
      const arr = brutos.map(linhaDoChat);
      const canalDaBia = brutos.find((c: any) => c.agentId === AGENTE_BIA)?.channelId || brutos[0]?.channelId || null;
      const hdrS = { apikey: SR, Authorization: "Bearer " + SR };
      const [pfS, igS] = await Promise.all([
        fetch(SB_URL + "/rest/v1/perfis?select=whatsapp&whatsapp=not.is.null", { headers: hdrS }).then((r) => r.ok ? r.json() : []),
        fetch(SB_URL + "/rest/v1/funil_ignorados?select=id", { headers: hdrS }).then((r) => r.ok ? r.json() : []),
      ]);
      const foraS = new Set<string>([...pfS.map((x: any) => so8(x.whatsapp)), ...igS.map((x: any) => String(x.id).replace(/^k/, ""))]);
      // fora do horário da Ana (ter a sex, 14h às 18h) as conversas voltam para a Bia, que atende sozinha
      let devolvidas = 0;
      if (!horarioDaEquipe() && arr.some((c: any) => c.humano)) {
        const hdr = { apikey: SR, Authorization: "Bearer " + SR };
        const [pf, ig] = await Promise.all([
          fetch(SB_URL + "/rest/v1/perfis?select=whatsapp&whatsapp=not.is.null", { headers: hdr }).then((r) => r.ok ? r.json() : []),
          fetch(SB_URL + "/rest/v1/funil_ignorados?select=id", { headers: hdr }).then((r) => r.ok ? r.json() : []),
        ]);
        const fora = new Set<string>([...pf.map((x: any) => so8(x.whatsapp)), ...ig.map((x: any) => String(x.id).replace(/^k/, ""))]);
        const recente = Date.now() - 20 * 60000;
        for (const c of arr) {
          if (!c.humano || !c.tel8 || fora.has(c.tel8)) continue;               // cirurgiões e contatos ignorados ficam com a equipe
          if (c.ultima_de === "assistant" && c.ultima_em && Date.parse(c.ultima_em) > recente) continue;   // alguém da equipe acabou de escrever
          try {
            await gm(`/chat/${encodeURIComponent(c.chat_id)}/stop-human`, { method: "PUT" }); c.humano = false; devolvidas++;
            // paciente esperando resposta (últimas 6 h): a Bia responde agora
            if (c.ultima_de === "user" && c.ultima_em && Date.parse(c.ultima_em) > Date.now() - 6 * 3600000 && devolvidas <= 5)
              emSegundoPlano(biaRetoma(c.chat_id, "Bia (fora do horário)"));
          } catch { /* tenta na próxima */ }
          if (devolvidas >= 20) break;
        }
      }
      // rede de segurança do presencial: a Bia disse "a secretária vai entrar em contato" e não acionou a intenção
      let presenciais = 0;
      const AT = Deno.env.get("AGENDA_TOKEN") || "";
      const dezMin = Date.now() - 10 * 60000;
      for (const c of arr) {
        if (!AT || c.ultima_de !== "assistant" || !c.ultima_em || Date.parse(c.ultima_em) < dezMin) continue;
        const disseSecretaria = /secret[aá]ria/i.test(c.ultima) && /(contato|chamar|ligar|falar com voc)/i.test(c.ultima);
        // a Bia tentou encaminhar o presencial e a intenção falhou ("não consegui encaminhar", "falha no sistema")
        const falhou = /(n[aã]o consegui (encaminhar|registrar)|falha no sistema|sistema (ainda )?n[aã]o conseguiu|erro no sistema)/i.test(c.ultima)
          && /(presencial|unidade|secret[aá]ria|encaminh)/i.test(c.ultima);
        if (!disseSecretaria && !falhou) continue;
        const hdr = { apikey: SR, Authorization: "Bearer " + SR };
        const fichas = await fetch(SB_URL + `/rest/v1/funil_pacientes?select=id&dados->>telefone=like.*${c.tel8}`, { headers: hdr }).then((r) => r.ok ? r.json() : []);
        const ids = fichas.map((x: any) => x.id);
        if (ids.length) {
          const desde = new Date(Date.now() - 24 * 3600000).toISOString();
          const ja = await fetch(SB_URL + `/rest/v1/funil_avisos_medico?select=id&tipo=eq.presencial&criado_em=gte.${desde}&paciente_id=in.(${ids.map((i: string) => '"' + i + '"').join(",")})`, { headers: hdr }).then((r) => r.ok ? r.json() : []);
          if (ja.length) continue;
        }
        try {
          const rr = await fetch(SB_URL + "/functions/v1/agenda", { method: "POST", headers: { "Content-Type": "application/json", "x-agenda-token": AT },
            body: JSON.stringify({ acao: "presencial_auto", chat_id: c.chat_id, telefone: c.telefone }) });
          const jr: any = await rr.json().catch(() => ({}));
          presenciais++;
          if (falhou) {
            // a paciente ouviu que deu erro: avisa que deu certo (ou deixa para a equipe se não deu)
            if (jr?.ok && !jr?.ja_enviado && jr?.medico) {
              const texto = "Pronto, " + (String(c.nome || "").split(/\s+/)[0] || "tudo certo") + "! Consegui passar seu caso para o " + jr.medico
                + ". A secretária dele vai entrar em contato para marcar o melhor dia e horário da sua consulta presencial. 😊";
              await gm(`/chat/${encodeURIComponent(c.chat_id)}/send-message`, { method: "POST", body: JSON.stringify({ message: texto }) });
              await dbs("funil_whats_envios", { method: "POST", headers: { Prefer: "return=minimal" },
                body: JSON.stringify({ chat_id: c.chat_id, texto, por: "bia@alinhaface", por_nome: "Bia (correção automática)" }) });
            } else {
              await rpc("abrir_alerta", { p_tipo: "bia_frase", p_chave: "falha-presencial:" + c.chat_id + ":" + c.ultima_em,
                p_titulo: "Bia não conseguiu encaminhar o presencial de " + (c.nome || "paciente") + " — encaminhe pelo funil",
                p_detalhe: c.ultima, p_chat: c.chat_id });
            }
          }
        } catch { /* tenta de novo na próxima rodada */ }
      }
      if (arr.length) {
        const r = await fetch(SB_URL + "/rest/v1/funil_whats?on_conflict=chat_id", {
          method: "POST",
          headers: { apikey: SR, Authorization: "Bearer " + SR, "Content-Type": "application/json", Prefer: "resolution=merge-duplicates,return=minimal" },
          body: JSON.stringify(arr),
        });
        if (!r.ok) return json({ erro: "banco: " + (await r.text()).slice(0, 200) }, 500);
      }
      let vigia: unknown = null;
      try { vigia = await vigiar(arr.map((c: any, i: number) => (i === 0 ? { ...c, canal: canalDaBia } : c)), foraS); } catch (e) { vigia = { erro: String((e as Error).message || e).slice(0, 200) }; }
      return json({ ok: true, conversas: arr.length, devolvidas_para_bia: devolvidas, presenciais_automaticos: presenciais, vigia });
    } catch (e) { return json({ erro: String((e as Error).message || e) }, 500); }
  }
  if (p.acao === "gastos_meta") {
    // chamado pelo agendador: só lê o gasto no Meta e grava no banco. Não recebe dados de fora além do número de dias.
    try { return json(await gastosMeta(Number(p.dias) || 3)); } catch (e) { return json({ erro: String((e as Error).message || e) }, 500); }
  }
  if (p.acao === "processar_avisos") {
    try { return json(await processarAvisos()); } catch (e) { return json({ erro: String((e as Error).message || e) }, 500); }
  }

  const auth = req.headers.get("Authorization") || "";
  SB_KEY = req.headers.get("apikey") || SB_KEY;   // a chave pública que o site já manda
  const u = await fetch(SB_URL + "/auth/v1/user", { headers: { apikey: SB_KEY, Authorization: auth } });
  if (!u.ok) return json({ erro: "faça login de novo" }, 401);
  const eu = await u.json();
  // teleconsulta: o cirurgião também usa (o banco só deixa ele ver as salas dele)
  const livre = p.acao === "transcrever" || p.acao === "resumir";
  if (!livre) {
    const adm = await rest(auth, "rpc/eh_admin", { method: "POST", body: "{}" });
    if (!adm.ok || (await adm.json()) !== true) return json({ erro: "só administradores" }, 403);
  }

  try {
    switch (p.acao) {
      case "atualizar": {
        const paginas = Math.min(Math.max(Number(p.paginas) || 1, 1), 30);
        let total = 0;
        for (let pg = 1; pg <= paginas; pg++) {
          const lista = await gm(`/workspace/${WORKSPACE}/chats?page=${pg}&pageSize=100`);
          const arr = Array.isArray(lista) ? lista : [];
          await gravarChats(auth, arr.filter((c: any) => !c.isGroup && c.channelId && c.agentId !== AGENTE_RESUMO).map(linhaDoChat));
          total += arr.length;
          if (arr.length < 100) break;
        }
        return json({ ok: true, total });
      }
      case "mensagens": {
        if (!p.chatId) return json({ erro: "falta chatId" }, 400);
        const pg = Math.max(Number(p.pagina) || 1, 1);
        const lista = await gm(`/chat/${encodeURIComponent(p.chatId)}/messages?page=${pg}&pageSize=50`);
        const arr: any[] = (Array.isArray(lista) ? lista : []).map(mensagem).filter(Boolean);
        // troca o nome do dono da chave pelo nome de quem enviou pelo site
        try {
          const ev = await rest(auth, "funil_whats_envios?select=texto,por_nome,em&order=em.desc&limit=300&chat_id=eq." + encodeURIComponent(p.chatId));
          const envios: any[] = ev.ok ? await ev.json() : [];
          const usados = new Set<number>();
          for (const m of arr) {
            if (m.de !== "equipe" || !m.em) continue;
            const t = new Date(m.em).getTime();
            const i = envios.findIndex((e, k) => !usados.has(k) && Math.abs(new Date(e.em).getTime() - t) < 180000 &&
              (String(e.texto || "").trim() === String(m.texto || "").trim() || m.imagem || m.documento));
            if (i >= 0) { usados.add(i); m.quem = envios[i].por_nome; }
          }
        } catch { /* segue com o nome do GPT Maker */ }
        return json({ ok: true, mensagens: arr, temMais: Array.isArray(lista) && lista.length >= 45 });
      }
      case "enviar": {
        const texto = String(p.texto || "").trim();
        if (!p.chatId || !texto) return json({ erro: "falta conversa ou texto" }, 400);
        if (texto.length > 4000) return json({ erro: "mensagem longa demais" }, 400);
        const id = encodeURIComponent(p.chatId);
        try { await gm(`/chat/${id}/start-human`, { method: "PUT" }); } catch { /* já estava com a equipe */ }
        await gm(`/chat/${id}/send-message`, { method: "POST", body: JSON.stringify({ message: texto }) });
        await registrarEnvio(auth, p.chatId, texto, eu.email);
        await rest(auth, "funil_whats?chat_id=eq." + id, {
          method: "PATCH",
          body: JSON.stringify({
            humano: true, ultima: texto.replace(/\s+/g, " ").slice(0, 160), ultima_de: "assistant",
            ultima_em: new Date().toISOString(), visto_em: new Date().toISOString(), visto_por: eu.email,
          }),
        });
        return json({ ok: true });
      }
      case "arquivo": {
        const url = String(p.url || "");
        if (!p.chatId || !url) return json({ erro: "falta conversa ou arquivo" }, 400);
        if (!url.startsWith(SB_URL + "/storage/v1/object/sign/envios/")) return json({ erro: "arquivo fora do lugar permitido" }, 400);
        const id = encodeURIComponent(p.chatId);
        const legenda = String(p.legenda || "").trim().slice(0, 1000);
        try { await gm(`/chat/${id}/start-human`, { method: "PUT" }); } catch { /* já estava com a equipe */ }
        if (p.tipo === "documento") {
          await gm(`/chat/${id}/send-message`, { method: "POST", body: JSON.stringify({
            document: url, documentName: String(p.nome || "documento.pdf").slice(0, 120), documentMimetype: String(p.mime || "application/pdf") }) });
          if (legenda) await gm(`/chat/${id}/send-message`, { method: "POST", body: JSON.stringify({ message: legenda }) });
        } else {
          await gm(`/chat/${id}/send-message`, { method: "POST", body: JSON.stringify({ image: url, message: legenda }) });
        }
        await registrarEnvio(auth, p.chatId, legenda || String(p.nome || "arquivo"), eu.email);
        await rest(auth, "funil_whats?chat_id=eq." + id, {
          method: "PATCH",
          body: JSON.stringify({
            humano: true, ultima: (p.tipo === "documento" ? "📄 " : "📷 ") + (legenda || p.nome || "arquivo").replace(/\s+/g, " ").slice(0, 150),
            ultima_de: "assistant", ultima_em: new Date().toISOString(), visto_em: new Date().toISOString(), visto_por: eu.email,
          }),
        });
        return json({ ok: true });
      }
      case "iniciar": {
        let tel = String(p.telefone || "").replace(/\D/g, "");
        const texto = String(p.texto || "").trim();
        if (tel.length === 10 || tel.length === 11) tel = "55" + tel;
        if (tel.length < 12 || !texto) return json({ erro: "falta telefone ou mensagem" }, 400);
        // canal da Bia: o mesmo das conversas existentes
        const lista = await gm(`/workspace/${WORKSPACE}/chats?page=1&pageSize=5`);
        const canal = (Array.isArray(lista) ? lista : []).map((c: any) => c.channelId).find(Boolean);
        if (!canal) return json({ erro: "não achei o canal da Bia" }, 502);
        await gm(`/channel/${encodeURIComponent(canal)}/start-conversation`, { method: "POST", body: JSON.stringify({ phone: tel, message: texto }) });
        // traz a conversa nova para a lista do site
        let chatId: string | null = null;
        for (let tent = 0; tent < 4 && !chatId; tent++) {
          if (tent) await new Promise((r) => setTimeout(r, 1500));
          const novos = await gm(`/workspace/${WORKSPACE}/chats?page=1&pageSize=20`);
          const arr = Array.isArray(novos) ? novos : [];
          await gravarChats(auth, arr.filter((c: any) => !c.isGroup && c.channelId && c.agentId !== AGENTE_RESUMO).map(linhaDoChat));
          chatId = arr.find((c: any) => so8(c.whatsappPhone) === tel.slice(-8))?.id || null;
        }
        if (chatId) await registrarEnvio(auth, chatId, texto, eu.email);
        return json({ ok: true, chatId });
      }
      case "transcrever": {
        const sala = String(p.sala || ""), caminho = String(p.caminho || "");
        if (!/^[0-9a-f-]{36}$/i.test(sala) || !caminho.startsWith("tele/" + sala + "/")) return json({ erro: "trecho inválido" }, 400);
        const rr = await rest(auth, "funil_teleconsultas?select=id,consentimento,transcricao&id=eq." + sala);
        const linha = rr.ok ? (await rr.json())[0] : null;
        if (!linha) return json({ erro: "sala não encontrada" }, 404);
        if (linha.consentimento !== true) return json({ erro: "paciente não autorizou a gravação" }, 403);
        // link temporário do áudio, assinado com o login de quem pediu
        const sg = await fetch(SB_URL + "/storage/v1/object/sign/anexos/" + caminho, {
          method: "POST", headers: { apikey: SB_KEY, Authorization: auth, "Content-Type": "application/json" },
          body: JSON.stringify({ expiresIn: 3600 }),
        });
        if (!sg.ok) return json({ erro: "não achei o áudio" }, 404);
        const url = SB_URL + "/storage/v1" + (await sg.json()).signedURL;
        // cada trecho vai numa conversa com nome único, para achar a transcrição depois
        const nomeConv = "TX" + sala.replace(/-/g, "").slice(0, 12) + Date.now();
        try {
          await gm(`/agent/${AGENTE_RESUMO}/conversation`, { method: "POST", body: JSON.stringify({ contextId: nomeConv, chatName: nomeConv, audio: url }) });
        } catch { /* o agente não responde a áudio; a transcrição fica na conversa */ }
        let texto = "", chatId = "";
        for (let t = 0; t < 30 && !texto; t++) {
          await espera(t ? 3000 : 1500);
          const cs = await gm(`/workspace/${WORKSPACE}/chats?page=1&pageSize=3&query=${nomeConv}`);
          const c = (Array.isArray(cs) ? cs : []).find((x: any) => x.name === nomeConv);
          if (!c) continue;
          chatId = c.id;
          const ms = await gm(`/chat/${c.id}/messages?page=1&pageSize=5`);
          const a = (Array.isArray(ms) ? ms : []).find((m: any) => m.type === "AUDIO" || m.audioUrl);
          if (a && a.midiaContent) texto = String(a.midiaContent);
        }
        // limpeza: apaga a conversa no GPT Maker e o áudio no Storage
        if (chatId) { try { await gm(`/chat/${chatId}`, { method: "DELETE" }); } catch { /* ok */ } }
        await fetch(SB_URL + "/storage/v1/object/anexos/" + caminho, { method: "DELETE", headers: { apikey: SB_KEY, Authorization: auth } });
        if (!texto) return json({ erro: "a transcrição não ficou pronta" }, 504);
        if (/não foi possível transcrever/i.test(texto)) texto = "[trecho sem fala reconhecível]";
        const n = (caminho.match(/\/(\d+)\.\w+$/) || [])[1] || "?";
        const nova = ((linha.transcricao || "") + "\n\n[Trecho " + n + "]\n" + texto).trim();
        await rest(auth, "funil_teleconsultas?id=eq." + sala, { method: "PATCH", body: JSON.stringify({ transcricao: nova }) });
        return json({ ok: true, caracteres: texto.length });
      }
      case "resumir": {
        const sala = String(p.sala || "");
        if (!/^[0-9a-f-]{36}$/i.test(sala)) return json({ erro: "sala inválida" }, 400);
        const rr = await rest(auth, "funil_teleconsultas?select=id,transcricao,paciente_nome&id=eq." + sala);
        const linha = rr.ok ? (await rr.json())[0] : null;
        if (!linha) return json({ erro: "sala não encontrada" }, 404);
        const tr = String(linha.transcricao || "").trim();
        if (tr.length < 40) return json({ erro: "transcrição vazia ou curta demais para resumir" }, 400);
        const nomeRes = "RS" + sala.replace(/-/g, "").slice(0, 12) + Date.now();
        const r = await gm(`/agent/${AGENTE_RESUMO}/conversation`, {
          method: "POST",
          body: JSON.stringify({ contextId: nomeRes, chatName: nomeRes, prompt: "GERAR RESUMO\n\nObservações: a transcrição é automática e pode errar palavras parecidas (ex.: \"a mil\"/\"a 1000\" = Amil, \"uni med\" = Unimed, \"bradesco saúde\", \"sul américa\", \"hap vida\" = Hapvida, \"notre dame\"/\"intermédica\"). Interprete pelo contexto. Use TUDO o que foi falado, inclusive em perguntas e respostas curtas (ex.: \"Qual seu plano? É a Amil\" = CONVÊNIO: Amil; \"Você tem dor de cabeça? Tenho\" = sintoma). Escreva \"não mencionado\" só quando o assunto realmente não apareceu.\n\nTranscrição da consulta (em trechos, na ordem):\n" + tr.slice(0, 60000) }),
        });
        let resumo = String(r?.message || "").trim();
        // às vezes a resposta não vem na hora: busca a resposta do agente na conversa
        for (let t = 0; t < 20 && !resumo; t++) {
          await espera(3000);
          try {
            const cs = await gm(`/workspace/${WORKSPACE}/chats?page=1&pageSize=3&query=${nomeRes}`);
            const c = (Array.isArray(cs) ? cs : []).find((x: any) => x.name === nomeRes);
            if (!c) continue;
            const ms = await gm(`/chat/${c.id}/messages?page=1&pageSize=5`);
            const a = (Array.isArray(ms) ? ms : []).find((m: any) => m.role === "assistant" && String(m.text || "").length > 40);
            if (a) resumo = String(a.text).trim();
          } catch { /* tenta de novo */ }
        }
        if (!resumo) return json({ erro: "o resumo não veio", detalhe: JSON.stringify(r).slice(0, 300) }, 502);
        await rest(auth, "funil_teleconsultas?id=eq." + sala, { method: "PATCH", body: JSON.stringify({ resumo_ia: resumo, resumo_em: new Date().toISOString() }) });
        // limpeza da conversa de resumo no GPT Maker
        try {
          const cs = await gm(`/workspace/${WORKSPACE}/chats?page=1&pageSize=3&query=${nomeRes}`);
          const c = (Array.isArray(cs) ? cs : []).find((x: any) => x.name === nomeRes);
          if (c) await gm(`/chat/${c.id}`, { method: "DELETE" });
        } catch { /* ok */ }
        return json({ ok: true, resumo });
      }
      case "limpar_resumo": {
        // apaga as conversas que ficaram no agente "Resumo de Consultas" (não tem paciente nelas)
        let apagadas = 0;
        for (let volta = 0; volta < 10; volta++) {
          const cs = await gm(`/workspace/${WORKSPACE}/chats?page=1&pageSize=50&agentId=${AGENTE_RESUMO}`);
          const lista = Array.isArray(cs) ? cs : [];
          const alvo = lista.filter((c: any) => c.agentId === AGENTE_RESUMO);
          if (!alvo.length) break;
          for (const c of alvo) {
            try { await gm(`/chat/${encodeURIComponent(c.id)}`, { method: "DELETE" }); apagadas++; } catch { /* segue */ }
            await rest(auth, "funil_whats?chat_id=eq." + encodeURIComponent(c.id), { method: "DELETE" });
          }
        }
        return json({ ok: true, apagadas });
      }
      case "situacao_canal": {
        const lista = await gm(`/workspace/${WORKSPACE}/chats?page=1&pageSize=5`);
        const canal = (Array.isArray(lista) ? lista : []).map((c: any) => c.channelId).find(Boolean);
        if (!canal) return json({ erro: "não achei o canal da Bia" }, 502);
        return json({ ok: true, canal, ...(await situacaoDoCanal(canal)) });
      }
      case "assumir":
      case "devolver": {
        if (!p.chatId) return json({ erro: "falta chatId" }, 400);
        const id = encodeURIComponent(p.chatId);
        await gm(`/chat/${id}/${p.acao === "assumir" ? "start-human" : "stop-human"}`, { method: "PUT" });
        await rest(auth, "funil_whats?chat_id=eq." + id, {
          method: "PATCH", body: JSON.stringify({ humano: p.acao === "assumir" }),
        });
        // devolveu para a Bia: ela lê o que ficou sem resposta e responde
        if (p.acao === "devolver") emSegundoPlano(biaRetoma(p.chatId, "Bia (retomou)"));
        return json({ ok: true });
      }
      default:
        return json({ erro: "ação desconhecida" }, 400);
    }
  } catch (e) {
    const msg = String((e as Error).message || e);
    return json({ erro: msg === "sem_chave" ? "sem_chave" : msg }, msg === "sem_chave" ? 503 : 502);
  }
});
