// Função "agenda": a porta por onde a Bia (GPT Maker, Intenções) consulta e marca horários
// do Dr. Afonso e do Dr. Victor no funil. O Dr. Gustavo continua no Google Agenda.
//
// Proteção: toda chamada precisa do token guardado como segredo AGENDA_TOKEN no Supabase,
// no cabeçalho "x-agenda-token" (ou ?token= na URL). Publicar com "Verify JWT" DESLIGADO.
//
// Aceita GET (parâmetros na URL) ou POST (JSON). Campos:
//   acao        "horarios" | "agendar"
//   estado      UF ou nome do estado onde o paciente mora (SP, BA, "Bahia"...)
//   modalidade  "online" | "presencial"
//   data        (agendar) dia escolhido: 2026-10-29, 29/10 ou 29/10/2026
//               (horarios) opcional: a partir de que dia procurar
//   hora        (agendar) horário escolhido: 14:00, 14h...
//   nome        (agendar) nome do paciente
//   telefone    (agendar) WhatsApp do paciente (variável do contato no GPT Maker)
//   chat_id     (agendar) id da conversa no GPT Maker (opcional)
//   observacao  (agendar) queixa principal, em poucas palavras (opcional)
//
// Regra de distribuição (decidida pelo Claudemir, out/2026):
//   - Bahia e todo o Nordeste -> Dr. Victor (online ou presencial em Salvador)
//   - São Paulo presencial    -> Dr. Afonso, sempre
//   - SP (online e presencial)  -> Dr. Afonso, nesta agenda
//   - Online de RS e demais estados -> Dr. Gustavo (agenda do Google, como já é feito)
//   - PRESENCIAL (nov/2026): a Bia não marca. acao=presencial manda o caso por WhatsApp ao cirurgião
//     (Nordeste -> Victor; SP -> Afonso, ou Gustavo se Moema; RS -> Gustavo) e a secretária dele marca.
//     Campos: estado, local (unidade), nome, preferencia (dias/períodos), resumo, telefone, chat_id
//   - Presencial em outros estados -> não existe; a Bia oferece online

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SR = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const TOKEN = Deno.env.get("AGENDA_TOKEN") || "";

const NORDESTE = ["BA", "SE", "AL", "PE", "PB", "RN", "CE", "PI", "MA"];
const ESTADOS: Record<string, string> = {
  acre: "AC", alagoas: "AL", amapa: "AP", amazonas: "AM", bahia: "BA", ceara: "CE",
  "distrito federal": "DF", brasilia: "DF", "espirito santo": "ES", goias: "GO", maranhao: "MA",
  "mato grosso": "MT", "mato grosso do sul": "MS", "minas gerais": "MG", minas: "MG", para: "PA",
  paraiba: "PB", parana: "PR", pernambuco: "PE", piaui: "PI", "rio de janeiro": "RJ",
  "rio grande do norte": "RN", "rio grande do sul": "RS", rondonia: "RO", roraima: "RR",
  "santa catarina": "SC", "sao paulo": "SP", sergipe: "SE", tocantins: "TO",
  // capitais que costumam vir no lugar do estado
  salvador: "BA", recife: "PE", fortaleza: "CE", natal: "RN", "joao pessoa": "PB", maceio: "AL",
  aracaju: "SE", teresina: "PI", "sao luis": "MA", "porto alegre": "RS", poa: "RS",
};
const SIGLAS = new Set(Object.values(ESTADOS).concat(["AC","AP","AM","ES","GO","MT","MS","MG","PA","PR","RJ","RO","RR","SC","TO"]));
const DIAS = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"];

const semAcento = (s: string) => String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { "Content-Type": "application/json; charset=utf-8" } });

function uf(v: string): string {
  const s = semAcento(v).replace(/[^a-z ]/g, " ").replace(/\s+/g, " ").trim();
  if (!s) return "";
  if (s.length === 2 && SIGLAS.has(s.toUpperCase())) return s.toUpperCase();
  if (ESTADOS[s]) return ESTADOS[s];
  // "salvador ba", "moro em sao paulo capital"...
  const sig = s.split(" ").reverse().find((w) => w.length === 2 && SIGLAS.has(w.toUpperCase()));
  if (sig) return sig.toUpperCase();
  const nome = Object.keys(ESTADOS).sort((a, b) => b.length - a.length).find((k) => s.includes(k));
  return nome ? ESTADOS[nome] : "";
}
const modalidade = (v: string) => {
  const s = semAcento(v);
  if (!s) return "";
  return s.startsWith("presen") || s.includes("consultorio") || s.includes("pessoalmente") ? "Presencial" : "Online";
};

function hojeSP(): string {
  return new Date(Date.now() - 3 * 3600 * 1000).toISOString().slice(0, 10);
}
// "2026-10-29", "29/10", "29/10/2026", "29-10" -> "2026-10-29"
function data(v: string): string {
  const s = String(v || "").trim();
  let m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) return `${m[1]}-${m[2]}-${m[3]}`;
  m = s.match(/^(\d{1,2})[\/\-.](\d{1,2})(?:[\/\-.](\d{2,4}))?/);
  if (!m) return "";
  const hoje = hojeSP();
  let ano = m[3] ? Number(m[3].length === 2 ? "20" + m[3] : m[3]) : Number(hoje.slice(0, 4));
  let iso = `${ano}-${m[2].padStart(2, "0")}-${m[1].padStart(2, "0")}`;
  if (!m[3] && iso < hoje) { ano += 1; iso = `${ano}-${m[2].padStart(2, "0")}-${m[1].padStart(2, "0")}`; }
  return iso;
}
const quando = (d: string, h: string) => {
  const dt = new Date(d + "T12:00:00Z");
  return `${DIAS[dt.getUTCDay()]}, ${d.slice(8, 10)}/${d.slice(5, 7)} às ${h}`;
};

// presencial: a Bia não marca; o caso vai por WhatsApp para o cirurgião, que passa à secretária
const MEDICOS: Record<string, { nome: string; email: string; unidades: string }> = {
  victor: { nome: "Dr. Victor", email: "admvictorssa@gmail.com", unidades: "Salvador" },
  afonso: { nome: "Dr. Afonso", email: "dr.aptrindadefilho@gmail.com", unidades: "Mooca ou Vila Mariana" },
  gustavo: { nome: "Dr. Gustavo", email: "gu.martins00@gmail.com", unidades: "Porto Alegre ou Moema (SP)" },
};
function medicoPresencial(estado: string, local: string): string | null {
  if (NORDESTE.includes(estado)) return "victor";
  if (estado === "SP") return /moema/.test(semAcento(local)) ? "gustavo" : "afonso";
  if (estado === "RS") return "gustavo";
  return null;
}
function unidadesDe(estado: string) {
  if (NORDESTE.includes(estado)) return "Salvador";
  if (estado === "SP") return "Mooca, Vila Mariana (Dr. Afonso) ou Moema (Dr. Gustavo)";
  if (estado === "RS") return "Porto Alegre";
  return "";
}
// mensagem de avaliação do site ("*Principal incômodo:* ... *Há quanto tempo...:* ...") -> linhas "• campo: valor"
function quizDe(textos: string[]): string {
  const t = textos.find((x) => /avalia[cç][aã]o no site|avalia[cç][aã]o do site|site da alinha face/i.test(x));
  if (!t) return "";
  const linhas: string[] = [];
  for (const m of t.matchAll(/\*([^*:]{2,60}):\*\s*([^*]+)/g)) {
    const campo = m[1].trim(), valor = m[2].replace(/\s+/g, " ").trim();
    if (!valor || /^nome$/i.test(campo)) continue;
    linhas.push("• " + campo + ": " + valor.replace(/\s*(Gostaria de|Olá|Oi)\b.*$/i, "").trim());
  }
  if (linhas.length) return linhas.join("\n");
  return t.replace(/\s+/g, " ").slice(0, 500);
}
async function textosDoPaciente(chatId: string): Promise<string[]> {
  const tk = Deno.env.get("GPTMAKER_TOKEN");
  if (!tk || !chatId) return [];
  try {
    const r = await fetch(`https://api.gptmaker.ai/v2/chat/${encodeURIComponent(chatId)}/messages?page=1&pageSize=50`,
      { headers: { Authorization: "Bearer " + tk } });
    const l = r.ok ? await r.json() : [];
    return (Array.isArray(l) ? l : []).filter((m: any) => m.role === "user" && m.text).map((m: any) => String(m.text));
  } catch { return []; }
}
async function chatPorTelefone(tel: string): Promise<string> {
  const t8 = String(tel || "").replace(/\D/g, "").slice(-8);
  if (t8.length < 8) return "";
  const r = await fetch(`${SB_URL}/rest/v1/funil_whats?select=chat_id&tel8=eq.${t8}&limit=1`,
    { headers: { apikey: SR, Authorization: `Bearer ${SR}` } });
  return r.ok ? ((await r.json())[0]?.chat_id || "") : "";
}

// ================= Agenda do Google do Dr. Gustavo <-> funil (só casos Alinha Face) =================
// Um Apps Script na conta Google que edita a agenda do Gustavo chama acao=google a cada 5 minutos com os
// eventos da Alinha Face (título = id da conversa da Bia, ou título com "Alinha Face"). Aqui:
//  - evento novo da Bia/equipe -> ficha ganha data, hora e cirurgião (cria a ficha se não existir);
//  - evento mudou de horário no Google -> ficha acompanha; ficha mudou no funil -> evento é movido;
//  - consulta do Gustavo lançada no funil sem evento -> o script cria o evento no Google;
//  - evento apagado no Google -> a ficha perde a data (e fica avisado na próxima ação);
//  - ficha perdeu a data / foi para "perdido" / trocou de cirurgião -> o evento é apagado.
const GUSTAVO = "gu.martins00@gmail.com";
const PREFIXO_CHAT = "3F6791F13320F0B1D9489ADC800E9477-";
function quandoSP(iso: string) {
  const f = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo", year: "numeric", month: "2-digit",
    day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(new Date(iso));
  const g = (t: string) => f.find((x) => x.type === t)!.value;
  return { data: `${g("year")}-${g("month")}-${g("day")}`, hora: `${g("hour")}:${g("minute")}` };
}
// "2026-11-05" + "10:15" (hora de Brasília) -> ISO em UTC
function isoSP(d: string, h: string, somaMin = 0) {
  const x = new Date(`${d}T${(h || "09:00").slice(0, 5)}:00-03:00`);
  return new Date(x.getTime() + somaMin * 60000).toISOString();
}
const dbg = (path: string, init: RequestInit = {}) => fetch(`${SB_URL}/rest/v1/${path}`, {
  ...init, headers: { apikey: SR, Authorization: `Bearer ${SR}`, "Content-Type": "application/json", ...(init.headers || {}) },
});
const semAc2 = (s: string) => String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
function histAdd(d: any, texto: string) {
  const h = Array.isArray(d.historico) ? d.historico : [];
  h.push({ data: new Date().toISOString().slice(0, 10), texto });
  d.historico = h.slice(-40);
}
function eventoDaFicha(p: any) {
  const d = p.dados, online = (d.modalidade || "Online") !== "Presencial";
  const conv = d.convenio === "Sim" ? (d.nomeConvenio || "sim") : d.convenio === "Não" ? "particular" : "a confirmar";
  return {
    paciente_id: p.id,
    titulo: `Alinha Face — ${d.nome || "Paciente"} (${online ? "on-line" : "presencial"})`,
    inicio: isoSP(d.dataConsulta, d.horaConsulta), fim: isoSP(d.dataConsulta, d.horaConsulta, online ? 15 : 30),
    local: online ? "Online" : (d.local || "Presencial"),
    desc: [`Paciente: ${d.nome || ""}`, d.telefone ? `WhatsApp: ${d.telefone}` : "", `Convênio: ${conv}`,
      d.tratamento ? `Queixa/tratamento: ${d.tratamento}` : "", d.resumoCaso ? `Resumo: ${d.resumoCaso}` : "",
      "", `Ficha: ${p.id}`, "Lançado pelo funil Alinha Face (sincronizado)."].filter((x) => x !== null).join("\n"),
  };
}
let SIMULAR = false;   // acao=google com simular=true: só diz o que faria, não grava
async function salvarFicha(id: string, dados: any) {
  if (SIMULAR) return;
  dados.atualizadoEm = new Date().toISOString();
  const r = await dbg(`funil_pacientes?id=eq.${encodeURIComponent(id)}`, { method: "PATCH", body: JSON.stringify({ dados }) });
  if (!r.ok) throw new Error("salvar ficha " + id + ": " + (await r.text()).slice(0, 200));
}
async function googleSync(p: any) {
  const eventos: any[] = Array.isArray(p.eventos) ? p.eventos : [];
  const hoje = quandoSP(new Date().toISOString()).data;
  const de = quandoSP(p.de).data, ate = quandoSP(p.ate).data;
  const out = { criar: [] as any[], mover: [] as any[], apagar: [] as string[], fichas_atualizadas: 0, fichas_novas: 0, avisos: [] as string[] };

  // fichas do Gustavo + todas que já têm evento ligado
  const rf = await dbg(`funil_pacientes?select=id,dados,cirurgiao_email&or=(cirurgiao_email.eq."${GUSTAVO}",dados->>googleEventId.not.is.null)`);
  const fichas: any[] = rf.ok ? await rf.json() : [];
  const porEvento = new Map<string, any>();
  for (const f of fichas) if (f.dados.googleEventId) porEvento.set(f.dados.googleEventId, f);
  let todosNomes: any[] | null = null;
  const vistos = new Set<string>();
  const ligados = new Set<string>();
  const idsRecebidos = new Set<string>(eventos.map((e: any) => e.id));
  SIMULAR = String(p.simular || "") === "true";

  for (const ev of eventos) {
    vistos.add(ev.id);
    const q = quandoSP(ev.inicio);
    const titulo = String(ev.titulo || ""), desc = String(ev.desc || "");
    const online = !/presencial/i.test(titulo + " " + (ev.local || "")) ;
    let f = porEvento.get(ev.id);
    let nova = false;
    if (!f) {
      // 1) evento criado pelo funil: "Ficha: ID" na descrição
      const mf = desc.match(/Ficha:\s*([\w-]+)/);
      if (mf) { const r = await dbg(`funil_pacientes?select=id,dados,cirurgiao_email&id=eq.${encodeURIComponent(mf[1])}`); f = r.ok ? (await r.json())[0] : null; }
      // 2) evento da Bia: título = id da conversa, que termina no telefone
      const tel = titulo.startsWith(PREFIXO_CHAT) ? titulo.slice(PREFIXO_CHAT.length).replace(/\D/g, "") : (desc.match(/(?:whats\w*|tel\w*)\D{0,3}([\d ()+-]{10,})/i)?.[1] || "").replace(/\D/g, "");
      if (!f && tel.length >= 8) {
        const r = await dbg(`funil_pacientes?select=id,dados,cirurgiao_email&dados->>telefone=like.*${tel.slice(-8)}&order=atualizado_em.desc&limit=1`);
        f = r.ok ? (await r.json())[0] : null;
      }
      // 3) lançado à mão com "Alinha Face" no título: procura pelo nome (só se for único)
      if (!f && !titulo.startsWith(PREFIXO_CHAT)) {
        if (!todosNomes) { const r = await dbg("funil_pacientes?select=id,nome:dados->>nome&limit=5000"); todosNomes = r.ok ? await r.json() : []; }
        const t = semAc2(titulo);
        const cands = todosNomes!.filter((x) => {
          const pal = semAc2(x.nome).split(/\s+/).map((w: string) => w.replace(/[^a-z0-9]/g, "")).filter((w: string) => w.length >= 3);
          return pal.length >= 2 && pal.slice(0, 2).every((w: string) => new RegExp(`\\b${w}\\b`).test(t));
        });
        if (cands.length === 1) { const r = await dbg(`funil_pacientes?select=id,dados,cirurgiao_email&id=eq.${encodeURIComponent(cands[0].id)}`); f = r.ok ? (await r.json())[0] : null; }
      }
      // ligado a outro evento? não mexe (evita duas consultas brigando pela mesma ficha)
      // ligada a outro evento que ainda existe? não mexe. Se o outro sumiu, foi remarcação: liga neste.
      if (f && f.dados.googleEventId && f.dados.googleEventId !== ev.id && idsRecebidos.has(f.dados.googleEventId)) { out.avisos.push(`ficha ${f.id} já ligada a outro evento`); continue; }
      if (!f) {
        if (q.data < hoje) continue;                    // não importa o passado
        const t8 = tel.slice(-8);
        const nome = titulo.startsWith(PREFIXO_CHAT)
          ? ((desc.match(/nome[^:\n]*:\s*([^\n]+)/i)?.[1] || desc.split("\n")[0] || "Paciente").trim())
          : titulo.replace(/alinha\s*face/ig, "").replace(/(^|\s)(1a|1º|1°|1ª|c|r|retorno|online|on-line|consulta|sem custo|dd)(?=\s|$)/ig, " ").replace(/[-–—|]+/g, " ").replace(/\s+/g, " ").trim();
        const id = "gc" + q.data.replace(/-/g, "") + "-" + (t8 || Math.random().toString(36).slice(2, 10));
        f = { id, dados: { nome: nome || "Paciente", telefone: tel || "", etapa: "lead", tratamento: "A definir", convenio: "Não sabe",
          pagamento: "A definir", origem: "Outro", fonte: "Agenda Google (Dr. Gustavo)", opme: 0, valorProposta: 0, historico: [],
          observacoes: "⚠ ficha criada pela agenda do Google do Dr. Gustavo; conferir nome e telefone" + (desc ? "\n" + desc.slice(0, 400) : ""),
          criadoEm: new Date().toISOString() } };
        nova = true;
      }
      // liga e copia o horário do Google
      const d = f.dados;
      d.googleEventId = ev.id; d.googleQuando = `${q.data} ${q.hora}`; delete d.googleApagado;
      if (/^(Consulta apagada|Paciente desmarcou)/.test(String(d.proximaAcao || ""))) { d.proximaAcao = ""; d.dataProximaAcao = ""; }
      if (d.dataConsulta !== q.data || (d.horaConsulta || "").slice(0, 5) !== q.hora) histAdd(d, `Consulta na agenda do Google do Dr. Gustavo: ${q.data.split("-").reverse().join("/")} às ${q.hora}`);
      d.dataConsulta = q.data; d.horaConsulta = q.hora; d.cirurgiao = GUSTAVO;
      if (!d.modalidade || d.modalidade === "Online" || online) d.modalidade = online ? "Online" : "Presencial";
      if (online) d.local = "Online";
      if (["triagem", "lead", "noshow", "perdido", undefined, ""].includes(d.etapa) && q.data >= hoje) d.etapa = "agendou";
      ligados.add(f.id);
      if (nova && SIMULAR) { out.fichas_novas++; out.avisos.push("nova ficha: " + d.nome + " " + q.data + " " + q.hora); }
      else if (nova) {
        const r = await dbg("funil_pacientes", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ id: f.id, dados: d }) });
        if (!r.ok) { out.avisos.push("criar ficha: " + (await r.text()).slice(0, 150)); continue; }
        out.fichas_novas++;
      } else { await salvarFicha(f.id, d); out.fichas_atualizadas++; }
      porEvento.set(ev.id, f);
      continue;
    }

    // já ligado: quem mudou?
    ligados.add(f.id);
    const d = f.dados;
    const doGoogle = `${q.data} ${q.hora}`;
    const doFunil = d.dataConsulta && d.horaConsulta ? `${d.dataConsulta} ${String(d.horaConsulta).slice(0, 5)}` : "";
    const ultimo = d.googleQuando || "";
    const valida = doFunil && f.cirurgiao_email === GUSTAVO && d.etapa !== "perdido";
    if (!valida) {
      // o funil desmarcou (sem data, perdido ou outro cirurgião): apaga o evento futuro
      if (q.data >= hoje) out.apagar.push(ev.id);
      delete d.googleEventId; delete d.googleQuando;
      histAdd(d, "Consulta tirada da agenda do Google do Dr. Gustavo (desmarcada no funil)");
      await salvarFicha(f.id, d); out.fichas_atualizadas++;
      continue;
    }
    if (doGoogle !== ultimo && (doFunil === ultimo || doFunil === doGoogle)) {
      // mudou no Google
      d.dataConsulta = q.data; d.horaConsulta = q.hora; d.googleQuando = doGoogle;
      histAdd(d, `Consulta remarcada na agenda do Google: ${q.data.split("-").reverse().join("/")} às ${q.hora}`);
      await salvarFicha(f.id, d); out.fichas_atualizadas++;
    } else if (doFunil !== ultimo && doGoogle === ultimo) {
      // mudou no funil: move o evento
      const e = eventoDaFicha(f);
      out.mover.push({ evento_id: ev.id, paciente_id: f.id, inicio: e.inicio, fim: e.fim, titulo: e.titulo });
      d.googleQuando = doFunil;
      await salvarFicha(f.id, d); out.fichas_atualizadas++;
    } else if (doGoogle !== doFunil) {
      // os dois mudaram: vale o Google
      d.dataConsulta = q.data; d.horaConsulta = q.hora; d.googleQuando = doGoogle;
      histAdd(d, `Consulta ajustada pela agenda do Google: ${q.data.split("-").reverse().join("/")} às ${q.hora}`);
      await salvarFicha(f.id, d); out.fichas_atualizadas++;
    }
  }

  // fichas ligadas cujo evento sumiu do Google (apagado lá) e fichas do Gustavo sem evento (criar no Google)
  for (const f of fichas) {
    if (ligados.has(f.id)) continue;
    const d = f.dados;
    const temData = d.dataConsulta && d.horaConsulta && d.dataConsulta >= hoje && d.dataConsulta <= ate;
    if (d.googleEventId && !vistos.has(d.googleEventId)) {
      const [gd] = String(d.googleQuando || "").split(" ");
      if (eventos.length && gd && gd >= hoje && gd >= de && gd <= ate) {
        histAdd(d, `Consulta apagada da agenda do Google do Dr. Gustavo (era ${gd.split("-").reverse().join("/")} ${String(d.googleQuando).split(" ")[1] || ""})`);
        delete d.googleEventId; delete d.googleQuando;
        if (d.dataConsulta === gd) { d.dataConsulta = ""; d.horaConsulta = ""; }
        d.googleApagado = true;
        d.proximaAcao = "Consulta apagada da agenda do Google do Dr. Gustavo — confirmar com o paciente / remarcar";
        d.dataProximaAcao = hoje;
        await salvarFicha(f.id, d); out.fichas_atualizadas++;
      }
      continue;
    }
    if (!d.googleEventId && !d.googleApagado && f.cirurgiao_email === GUSTAVO && temData && !["perdido", "noshow"].includes(d.etapa)) {
      out.criar.push(eventoDaFicha(f));
    }
  }
  return { ...out, simulado: SIMULAR };
}
function vistosOuFuturo(f: any) { return !!f.dados.googleQuando; }
async function googleVincular(p: any) {
  SIMULAR = false;
  const lista: any[] = Array.isArray(p.vinculos) ? p.vinculos : [];
  let n = 0;
  for (const v of lista) {
    const r = await dbg(`funil_pacientes?select=id,dados&id=eq.${encodeURIComponent(v.paciente_id)}`);
    const f = r.ok ? (await r.json())[0] : null;
    if (!f) continue;
    const q = quandoSP(v.inicio);
    f.dados.googleEventId = v.evento_id; f.dados.googleQuando = `${q.data} ${q.hora}`;
    histAdd(f.dados, `Consulta lançada na agenda do Google do Dr. Gustavo: ${q.data.split("-").reverse().join("/")} às ${q.hora}`);
    await salvarFicha(f.id, f.dados); n++;
  }
  return { ok: true, ligados: n };
}

// quem atende este paciente
function rota(estado: string, mod: string) {
  if (!estado) return { tipo: "perguntar", instrucao: "Mande no campo estado a SIGLA do estado (UF) da cidade que a pessoa disse (ex.: Ilhéus = BA, Campinas = SP, Caxias do Sul = RS) e use esta intenção de novo, sem perguntar nada à pessoa. Só pergunte o estado se a cidade não foi dita." };
  if (!mod) return { tipo: "perguntar", instrucao: "Pergunte se a pessoa prefere a consulta online (por vídeo) ou presencial." };
  if (mod === "Presencial") {
    if (!medicoPresencial(estado, "")) return { tipo: "perguntar", instrucao: "Consulta presencial existe em São Paulo, Salvador e Porto Alegre. Pergunte se a pessoa prefere a consulta online (sem sair de casa) ou se consegue ir a uma dessas cidades." };
    return { tipo: "presencial", instrucao:
      "Consulta presencial NÃO é marcada por você e não tem horário para oferecer. "
      + `Unidades para esta pessoa: ${unidadesDe(estado)}. Se ainda não souber, pergunte qual unidade e quais dias e períodos ela prefere. `
      + "Depois use a intenção \"Agendar consulta on-line ou encaminhar presencial ao cirurgião\" com modalidade presencial, SEM data e hora, nome, local (unidade), preferencia e em observacao um resumo curto da conversa. "
      + "Não envie link da Ana Clara e não transfira." };
  }
  if (NORDESTE.includes(estado)) {
    if (mod === "Presencial" && estado !== "BA") {
      return { tipo: "funil", medico: "victor", aviso: "A consulta presencial do Nordeste é em Salvador (BA). Confirme se a pessoa consegue ir até Salvador; se não, ofereça a consulta online." };
    }
    return { tipo: "funil", medico: "victor" };
  }
  // São Paulo: online e presencial com o Dr. Afonso (presencial em Moema é com o Dr. Gustavo, via Ana Clara)
  if (estado === "SP") return { tipo: "funil", medico: "afonso" };
  if (mod === "Online") {
    return { tipo: "gustavo", instrucao: "Siga como sempre: ofereça os horários online da agenda do Dr. Gustavo (Google Agenda). Não use esta consulta para esse paciente." };
  }
  if (estado === "RS") {
    return { tipo: "ana_clara", instrucao: "Consulta presencial em Porto Alegre: siga como sempre e envie o link do WhatsApp da Ana Clara para ela marcar." };
  }
  return { tipo: "perguntar", instrucao: "Consulta presencial existe em São Paulo, Salvador e Porto Alegre. Pergunte se a pessoa prefere a consulta online (sem sair de casa) ou se consegue ir a uma dessas cidades." };
}

async function rpc(fn: string, body: unknown) {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { apikey: SR, Authorization: `Bearer ${SR}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const t = await r.text();
  if (!r.ok) throw new Error(`${fn}: ${r.status} ${t.slice(0, 300)}`);
  return t ? JSON.parse(t) : null;
}

function min(h: string) { const [a, b] = h.split(":").map(Number); return a * 60 + (b || 0); }
function hm(m: number) { const h = Math.floor(m / 60), x = m % 60; return x ? `${h}h${String(x).padStart(2, "0")}` : `${h}h`; }
// faixas contínuas do dia: ["08:00","08:15",...,"13:45"] -> "das 8h às 14h"
function faixas(hs: string[]) {
  const ms = hs.map(min).sort((a, b) => a - b);
  let passo = 60;
  for (let i = 1; i < ms.length; i++) if (ms[i] - ms[i - 1] > 0) passo = Math.min(passo, ms[i] - ms[i - 1]);
  const blocos: [number, number][] = [];
  for (const m of ms) {
    const u = blocos[blocos.length - 1];
    if (u && m - u[1] <= passo) u[1] = m; else blocos.push([m, m]);
  }
  return blocos.map(([a, b]) => a === b ? `às ${hm(a)}` : `das ${hm(a)} às ${hm(b + passo)}`).join(" e ");
}

// até 6 horários em até 3 dias, espalhados ao longo do dia (manhã, tarde, noite) para a Bia oferecer
function escolher(slots: { data: string; hora: string }[]) {
  const porDia = new Map<string, string[]>();
  // o banco nem sempre devolve em ordem: ordena por dia e hora antes de escolher
  const ord = [...slots].sort((x, y) => (x.data + x.hora).localeCompare(y.data + y.hora));
  for (const s of ord) {
    if (!porDia.has(s.data)) { if (porDia.size >= 3) continue; porDia.set(s.data, []); }
    porDia.get(s.data)!.push(s.hora);
  }
  const out: { data: string; hora: string; texto: string }[] = [];
  for (const [d, hs] of porDia) {
    const pega: string[] = [];
    // em cada período pega o horário mais perto de um "bom horário" (não o primeiro, que dava sempre 8h e 12h)
    for (const [de, ate, alvo] of [["00:00", "12:00", "10:00"], ["12:00", "17:00", "14:30"], ["17:00", "24:00", "18:30"]]) {
      const cand = hs.filter((x) => x >= de && x < ate && !pega.includes(x));
      if (!cand.length) continue;
      cand.sort((a, b) => Math.abs(min(a) - min(alvo)) - Math.abs(min(b) - min(alvo)));
      pega.push(cand[0]);
    }
    for (const h of pega.slice(0, 2)) out.push({ data: d, hora: h, texto: quando(d, h) });
  }
  return out;
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  let p: Record<string, any> = Object.fromEntries(url.searchParams.entries());
  if (req.method === "POST") {
    try {
      const b = await req.json();
      if (b && typeof b === "object") p = { ...p, ...Object.fromEntries(Object.entries(b).map(([k, v]) => [k, v == null ? "" : (typeof v === "object" ? v : String(v))])) } as any;
    } catch { /* corpo vazio */ }
  } else if (req.method !== "GET") return json({ erro: "use GET ou POST" }, 405);

  const tk = req.headers.get("x-agenda-token") || p.token || "";
  if (!TOKEN || tk !== TOKEN) return json({ erro: "acesso negado" }, 401);

  let acao = semAcento(p.acao || (p.hora ? "agendar" : "horarios"));
  const est = uf(p.estado || p.uf || p.cidade || "");
  const mod = modalidade(p.modalidade || "");
  // a intenção de agendar também serve para DESMARCAR (cancelar = "sim")
  if (/^s/i.test(String(p.cancelar || "").trim()) || acao === "cancelar") {
    const tel = p.telefone || p.contact_phone || p.phone || "";
    const res = await rpc("cancelar_consulta", { p_telefone: tel, p_motivo: p.observacao || p.motivo || "" });
    if (!res?.ok) return json({ ok: false, motivo: res?.motivo,
      instrucao: res?.motivo === "sem_consulta_marcada" ? "Não encontrei consulta futura marcada para esse número. Pergunte o nome completo e a data da consulta e diga que a equipe vai conferir." : "Não consegui desmarcar agora. Diga que a equipe vai confirmar o cancelamento." });
    return json({ ok: true, desmarcada: res.era, medico: res.medico,
      instrucao: `Consulta de ${res.era} desmarcada no sistema (o cirurgião é avisado automaticamente). Confirme o cancelamento com gentileza e pergunte se a pessoa quer remarcar agora. Se quiser, use "Consultar horários livres de consulta" e depois esta intenção com a nova data e hora.` });
  }
  // a intenção de agendar também serve para o presencial (sem data e hora): vira encaminhamento ao cirurgião
  if (acao === "agendar" && mod === "Presencial") acao = "presencial";
  const r: any = rota(est, mod);

  try {
    if (acao === "google") return json({ ok: true, ...(await googleSync(p)) });
    if (acao === "google_vincular") return json(await googleVincular(p));
    if (acao === "presencial") {
      const local = p.local || p.unidade || "";
      const chave = medicoPresencial(est, local);
      if (!chave) return json({ ok: false, instrucao: rota(est, "Presencial").instrucao });
      const med = MEDICOS[chave];
      const tel = p.telefone || p.contact_phone || p.phone || "";
      if (!tel) return json({ ok: false, instrucao: "Faltou o telefone do contato na configuração da intenção. Transfira para a Ana Clara." });
      const chatId = p.chat_id || await chatPorTelefone(tel);
      const quiz = quizDe(await textosDoPaciente(chatId));
      const res = await rpc("encaminhar_presencial", {
        p_email: med.email, p_medico: med.nome, p_nome: p.nome || "", p_telefone: tel, p_chat_id: chatId || null,
        p_local: local, p_preferencia: p.preferencia || p.preferencia_horario || "", p_resumo: p.resumo || p.observacao || "", p_quiz: quiz,
      });
      if (!res?.ok) return json({ ok: false, motivo: res?.motivo, instrucao: "Não consegui encaminhar agora. Transfira para a Ana Clara." });
      return json({ ok: true, medico: med.nome,
        instrucao: `Pronto, o caso foi enviado ao ${med.nome}. Diga à pessoa: "Passei seu caso para o ${med.nome}. `
          + "A secretária dele vai entrar em contato para marcar o melhor dia e horário da sua consulta presencial.\" "
          + "Não ofereça horários nem envie link da Ana Clara." });
    }
    if (r.tipo !== "funil") return json({ ok: false, encaminhar: r.tipo, instrucao: r.instrucao, estado: est, modalidade: mod });

    if (acao === "horarios") {
      const de = data(p.data || p.data_preferida || "") || null;
      const slots: { data: string; hora: string; endereco: string }[] = (await rpc("agenda_slots", { p_chave: r.medico, p_modalidade: mod, p_de: de })) || [];
      const ord = [...slots].sort((x, y) => (x.data + x.hora).localeCompare(y.data + y.hora));
      const opcoes = escolher(ord);
      const local = mod === "Presencial" && ord[0] ? ord[0].endereco : null;
      // TODOS os horários livres dos 3 primeiros dias: se a pessoa pedir um horário que está aqui, ele serve
      const porDia = new Map<string, string[]>();
      for (const s of ord) {
        if (!porDia.has(s.data)) { if (porDia.size >= 3) continue; porDia.set(s.data, []); }
        porDia.get(s.data)!.push(s.hora);
      }
      const livres = [...porDia].map(([d, hs]) => ({ data: d, dia: quando(d, "").replace(/ às $/, ""), faixa: faixas(hs), horas: hs.join(", ") }));
      // a pessoa já disse um horário? confere esse horário exato
      const hp = String(p.hora || p.hora_preferida || "").replace(/h$/i, ":00").replace(/^(\d{1,2})$/, "$1:00").replace(/^(\d):/, "0$1:");
      const diaPedido = de || (ord[0] ? ord[0].data : "");
      const pedidoLivre = /^\d{2}:\d{2}$/.test(hp) ? ord.some((s) => s.data === diaPedido && s.hora === hp) : null;
      return json({
        ok: true, medico: r.medico === "afonso" ? "Dr. Afonso" : "Dr. Victor", modalidade: mod, estado: est,
        horarios: opcoes, livres, endereco: local,
        horario_pedido: pedidoLivre === null ? undefined : { data: diaPedido, hora: hp, livre: pedidoLivre },
        instrucao: !ord.length
          ? "Não há horário livre nas próximas duas semanas. Avise que a equipe vai entrar em contato para encaixar e transfira para a Ana Clara."
          : "Ofereça pela FAIXA do dia (campo 'faixa' em 'livres'), não só 2 horários soltos. Ex.: 'Amanhã, sábado, tenho horários das 8h às 14h. Qual horário fica melhor para você?'. "
            + "Se a pessoa pediu um dia/horário, procure em 'livres' (campo 'horas' tem todos os horários livres): se estiver lá, ESTÁ DISPONÍVEL — confirme esse horário. "
            + "Nunca diga que um horário não existe se ele aparece em 'livres'. Se a pessoa pedir OUTRO horário, nunca repita os que já ofereceu: diga a faixa inteira do dia ou outros horários de 'horas'. "
            + "Os exemplos em 'horarios' são só sugestões. "
            + "Confirme com a pessoa antes de marcar. "
            + (mod === "Online" ? "Consulta online por vídeo, 15 minutos." : "Consulta presencial no endereço informado.")
            + (r.aviso ? " " + r.aviso : ""),
      });
    }

    if (acao === "agendar") {
      const d = data(p.data || "");
      const tel = p.telefone || p.contact_phone || p.phone || "";
      if (!d || !p.hora) return json({ ok: false, instrucao: "Faltou o dia ou o horário escolhido. Confirme com a pessoa e tente de novo." });
      if (!tel) return json({ ok: false, instrucao: "Faltou o telefone do contato na configuração da intenção." });
      const res = await rpc("agenda_agendar", {
        p_chave: r.medico, p_modalidade: mod, p_data: d, p_hora: p.hora,
        p_nome: p.nome || "", p_telefone: tel, p_chat_id: p.chat_id || null, p_obs: p.observacao || null,
      });
      if (res?.ok) {
        return json({
          ...res,
          instrucao: `Consulta marcada: ${res.quando} (${res.modalidade.toLowerCase()}) com ${res.medico}. `
            + (res.modalidade === "Presencial" ? `Envie o endereço: ${res.endereco}. ` : "O link da chamada é enviado pouco antes do horário. ")
            + "Confirme para a pessoa com o assunto \"Avaliação Alinha Face\" e reforce que é uma cortesia.",
        });
      }
      const sug = (res?.sugestoes || []).slice(0, 3).map((s: any) => quando(s.data, s.hora));
      return json({
        ok: false, motivo: res?.motivo || "erro",
        sugestoes: sug,
        instrucao: res?.motivo === "horario_indisponivel"
          ? "Esse horário acabou de ser ocupado. Peça desculpas e ofereça: " + (sug.join("; ") || "outro horário (consulte de novo)") + "."
          : "Não consegui marcar. Transfira para a Ana Clara.",
      });
    }
    return json({ ok: false, erro: "acao desconhecida" }, 400);
  } catch (e) {
    console.error(e);
    return json({ ok: false, erro: "falha interna", instrucao: "Não consegui consultar a agenda agora. Transfira para a Ana Clara." }, 500);
  }
});
