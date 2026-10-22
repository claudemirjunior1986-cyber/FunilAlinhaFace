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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ erro: "use POST" }, 405);

  const auth = req.headers.get("Authorization") || "";
  SB_KEY = req.headers.get("apikey") || SB_KEY;   // a chave pública que o site já manda
  const u = await fetch(SB_URL + "/auth/v1/user", { headers: { apikey: SB_KEY, Authorization: auth } });
  if (!u.ok) return json({ erro: "faça login de novo" }, 401);
  const eu = await u.json();
  const adm = await rest(auth, "rpc/eh_admin", { method: "POST", body: "{}" });
  if (!adm.ok || (await adm.json()) !== true) return json({ erro: "só administradores" }, 403);

  let p: any = {};
  try { p = await req.json(); } catch { /* corpo vazio */ }

  try {
    switch (p.acao) {
      case "atualizar": {
        const paginas = Math.min(Math.max(Number(p.paginas) || 1, 1), 30);
        let total = 0;
        for (let pg = 1; pg <= paginas; pg++) {
          const lista = await gm(`/workspace/${WORKSPACE}/chats?page=${pg}&pageSize=100`);
          const arr = Array.isArray(lista) ? lista : [];
          await gravarChats(auth, arr.filter((c: any) => !c.isGroup && c.channelId).map(linhaDoChat));
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
          await gravarChats(auth, arr.filter((c: any) => !c.isGroup && c.channelId).map(linhaDoChat));
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
        try {
          await gm(`/agent/${AGENTE_RESUMO}/conversation`, { method: "POST", body: JSON.stringify({ contextId: "tele-" + sala + "-" + Date.now(), audio: url }) });
        } catch { /* o agente não responde a áudio; a transcrição fica na conversa */ }
        let texto = "", chatId = "";
        for (let t = 0; t < 25 && !texto; t++) {
          await espera(t ? 3000 : 1500);
          const cs = await gm(`/workspace/${WORKSPACE}/chats?page=1&pageSize=8&agentId=${AGENTE_RESUMO}`);
          for (const c of (Array.isArray(cs) ? cs : [])) {
            const ms = await gm(`/chat/${c.id}/messages?page=1&pageSize=5`);
            const a = (Array.isArray(ms) ? ms : []).find((m: any) => m.audioUrl === url);
            if (a) { chatId = c.id; if (a.midiaContent) texto = String(a.midiaContent); break; }
          }
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
        const r = await gm(`/agent/${AGENTE_RESUMO}/conversation`, {
          method: "POST",
          body: JSON.stringify({ contextId: "resumo-" + sala + "-" + Date.now(), prompt: "GERAR RESUMO\n\nTranscrição da consulta (em trechos, na ordem):\n" + tr.slice(0, 60000) }),
        });
        const resumo = String(r?.message || "").trim();
        if (!resumo) return json({ erro: "o resumo não veio" }, 502);
        await rest(auth, "funil_teleconsultas?id=eq." + sala, { method: "PATCH", body: JSON.stringify({ resumo_ia: resumo, resumo_em: new Date().toISOString() }) });
        // limpeza da conversa de resumo no GPT Maker
        try {
          const cs = await gm(`/workspace/${WORKSPACE}/chats?page=1&pageSize=5&agentId=${AGENTE_RESUMO}`);
          for (const c of (Array.isArray(cs) ? cs : [])) {
            if (String(c.conversation || "").slice(0, 25) === resumo.replace(/\s+/g, " ").slice(0, 25) || String(c.conversation || "").startsWith("QUEIXA")) {
              await gm(`/chat/${c.id}`, { method: "DELETE" }); break;
            }
          }
        } catch { /* ok */ }
        return json({ ok: true, resumo });
      }
      case "assumir":
      case "devolver": {
        if (!p.chatId) return json({ erro: "falta chatId" }, 400);
        const id = encodeURIComponent(p.chatId);
        await gm(`/chat/${id}/${p.acao === "assumir" ? "start-human" : "stop-human"}`, { method: "PUT" });
        await rest(auth, "funil_whats?chat_id=eq." + id, {
          method: "PATCH", body: JSON.stringify({ humano: p.acao === "assumir" }),
        });
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
