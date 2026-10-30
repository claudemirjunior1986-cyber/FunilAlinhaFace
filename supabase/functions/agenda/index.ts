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
//   - Presencial no RS        -> segue com a Ana Clara, como já é feito
//   - Presencial em outros estados -> só existe em SP e Salvador; a Bia oferece online

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

// quem atende este paciente
function rota(estado: string, mod: string) {
  if (!estado) return { tipo: "perguntar", instrucao: "Mande no campo estado a SIGLA do estado (UF) da cidade que a pessoa disse (ex.: Ilhéus = BA, Campinas = SP, Caxias do Sul = RS) e use esta intenção de novo, sem perguntar nada à pessoa. Só pergunte o estado se a cidade não foi dita." };
  if (!mod) return { tipo: "perguntar", instrucao: "Pergunte se a pessoa prefere a consulta online (por vídeo) ou presencial." };
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
  let p: Record<string, string> = Object.fromEntries(url.searchParams.entries());
  if (req.method === "POST") {
    try {
      const b = await req.json();
      if (b && typeof b === "object") p = { ...p, ...Object.fromEntries(Object.entries(b).map(([k, v]) => [k, v == null ? "" : String(v)])) };
    } catch { /* corpo vazio */ }
  } else if (req.method !== "GET") return json({ erro: "use GET ou POST" }, 405);

  const tk = req.headers.get("x-agenda-token") || p.token || "";
  if (!TOKEN || tk !== TOKEN) return json({ erro: "acesso negado" }, 401);

  const acao = semAcento(p.acao || (p.hora ? "agendar" : "horarios"));
  const est = uf(p.estado || p.uf || p.cidade || "");
  const mod = modalidade(p.modalidade || "");
  const r: any = rota(est, mod);

  try {
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
