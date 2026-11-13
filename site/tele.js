/* ============ Teleconsulta: criar a sala e mandar o link ============
   Usado no painel (equipe) e na área do médico. Só depende de FUNIL. */
async function teleSala(p, cirurgiao){
  // Usa SEMPRE a mesma sala do link que o paciente recebeu (confirmação do agendamento e lembrete de 15 min).
  // Antes, depois de 12 h a sala do agendamento não era achada e o médico abria outra: cada um ficava numa sala.
  const chave = p.dataConsulta && p.horaConsulta ? p.dataConsulta + " " + String(p.horaConsulta).slice(0,5) : "";
  const hojeSP = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" }).format(new Date());
  const desde = new Date(Date.now() - 30*864e5).toISOString();
  const { data: abertas } = await FUNIL.sb.from("funil_teleconsultas").select("id,consulta,criada_em")
    .eq("paciente_id", p.id).is("fim", null).gte("criada_em", desde).order("criada_em",{ascending:false}).limit(20);
  const l = abertas || [];
  const recente = t => Date.now() - new Date(t.criada_em).getTime() < 12*3600e3;
  const achada = (chave && l.find(t => t.consulta === chave))                       // a sala desta consulta
    || l.find(t => String(t.consulta || "").slice(0,10) === hojeSP)                 // a sala de uma consulta de hoje
    || l.find(t => !t.consulta && recente(t));                                      // uma aberta há pouco
  if(achada) return achada.id;
  const { data, error } = await FUNIL.sb.from("funil_teleconsultas")
    .insert({ paciente_id: p.id, paciente_nome: p.nome || "", cirurgiao: cirurgiao || p.cirurgiao || null, consulta: chave || null })
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

/* ---------- resumos das teleconsultas dentro da ficha do paciente ----------
   modo "painel" (equipe): fieldset com legenda · modo "medico": bloco com h3 */
function teleSecaoFicha(p, modo){
  const painel = modo !== "medico";
  const sec = document.createElement(painel ? "fieldset" : "div");
  if(!painel) sec.className = "bloco";
  const tit = document.createElement(painel ? "div" : "h3");
  if(painel) tit.className = "legend";
  tit.textContent = "🎥 Teleconsultas — resumo da IA";
  sec.appendChild(tit);
  const corpo = document.createElement("div"); corpo.className = "tele-lista";
  corpo.textContent = "Carregando…"; sec.appendChild(corpo);
  teleCarregarResumos(p, corpo);
  return sec;
}
async function teleCarregarResumos(p, corpo){
  const mk = (tag, cls, txt) => { const e = document.createElement(tag); if(cls) e.className = cls; if(txt != null) e.textContent = txt; return e; };
  const dt = s => { const d = new Date(s); return d.toLocaleDateString("pt-BR",{day:"2-digit",month:"2-digit"}) + " às " + d.toLocaleTimeString("pt-BR",{hour:"2-digit",minute:"2-digit"}); };
  const { data, error } = await FUNIL.sb.from("funil_teleconsultas")
    .select("id,criada_em,inicio,fim,consentimento,resumo_ia,resumo_em,transcricao,cirurgiao")
    .eq("paciente_id", p.id).order("criada_em", { ascending: false }).limit(20);
  corpo.textContent = "";
  if(error){ corpo.appendChild(mk("div","hint","Não consegui carregar as teleconsultas.")); return; }
  const lista = (data || []).filter(t => t.inicio || t.resumo_ia || t.transcricao);
  if(!lista.length){ corpo.appendChild(mk("div","hint","Nenhuma teleconsulta feita pela plataforma ainda.")); return; }
  for(const t of lista){
    const card = mk("div","tele-card");
    const min = t.inicio && t.fim ? Math.max(1, Math.round((new Date(t.fim) - new Date(t.inicio)) / 60000)) : null;
    card.appendChild(mk("div","tele-cab", dt(t.inicio || t.criada_em) + (min ? " · " + min + " min" : "") +
      (t.cirurgiao && typeof nomeCirurgiao === "function" ? " · " + nomeCirurgiao(t.cirurgiao) : "")));
    if(t.resumo_ia){
      card.appendChild(mk("div","tele-resumo", t.resumo_ia));
    }else{
      card.appendChild(mk("div","hint", t.consentimento === false || t.consentimento == null
        ? "Sem resumo: o paciente não autorizou a gravação do áudio."
        : (t.transcricao ? "O resumo ainda não foi gerado." : "Sem resumo: o áudio não chegou a ser transcrito.")));
    }
    const bts = mk("div","tele-bts");
    if(t.resumo_ia){
      const c = mk("button","btn btn-sm","Copiar resumo"); c.type = "button";
      c.addEventListener("click", ()=>{ navigator.clipboard?.writeText(t.resumo_ia).then(()=>{ c.textContent = "Copiado ✔"; setTimeout(()=>c.textContent = "Copiar resumo", 2000); }); });
      bts.appendChild(c);
    }
    if(t.transcricao){
      const v = mk("button","btn btn-sm btn-ghost","Ver o que foi falado"); v.type = "button";
      const tx = mk("div","tele-transc", t.transcricao); tx.hidden = true;
      v.addEventListener("click", ()=>{ tx.hidden = !tx.hidden; v.textContent = tx.hidden ? "Ver o que foi falado" : "Esconder transcrição"; });
      bts.appendChild(v);
      if(!t.resumo_ia){
        const g = mk("button","btn btn-sm btn-primary","Gerar resumo agora"); g.type = "button";
        g.addEventListener("click", async ()=>{
          g.disabled = true; g.textContent = "Gerando…";
          const r = await FUNIL.sb.functions.invoke("whats", { body: { acao:"resumir", sala: t.id } });
          if(r.error){ g.disabled = false; g.textContent = "Tentar de novo"; return; }
          teleCarregarResumos(p, corpo);
        });
        bts.appendChild(g);
      }
      card.append(bts, tx);
    }else if(bts.childNodes.length){ card.appendChild(bts); }
    corpo.appendChild(card);
  }
}
(function(){
  const css = document.createElement("style");
  css.textContent = `
  .tele-lista{display:flex;flex-direction:column;gap:10px}
  .tele-card{border:1px solid var(--line);border-radius:10px;padding:10px 12px;background:var(--surface);display:flex;flex-direction:column;gap:8px}
  .tele-cab{font-size:12.5px;font-weight:600;color:var(--ink-3)}
  .tele-resumo{white-space:pre-wrap;font-size:13.5px;line-height:1.5}
  .tele-bts{display:flex;gap:8px;flex-wrap:wrap}
  .tele-transc{white-space:pre-wrap;font-size:12.5px;line-height:1.5;color:var(--ink-2,var(--ink));background:var(--surface-2,#f4f5f7);border-radius:8px;padding:10px;max-height:320px;overflow:auto}`;
  document.head.appendChild(css);
})();
