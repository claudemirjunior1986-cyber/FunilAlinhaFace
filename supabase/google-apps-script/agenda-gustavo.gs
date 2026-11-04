/**
 * Alinha Face — agenda do Google do Dr. Gustavo <-> funil (só casos Alinha Face).
 * Roda no Google Apps Script (script.google.com) de uma conta que EDITA a agenda gu.martins00@gmail.com.
 *
 * Instalação (uma vez):
 *  1. Cole este código num projeto novo do Apps Script.
 *  2. Em "Configurações do projeto" > "Propriedades do script", crie TOKEN com a senha da agenda
 *     (a mesma do cabeçalho x-agenda-token da intenção da Bia no GPT Maker). Quem cola é a pessoa, não o Claude.
 *  3. Rode "simular" uma vez (autorize o acesso à agenda) e confira o registro.
 *  4. Rode "instalar" para ligar a sincronização a cada 5 minutos.
 *
 * Eventos da Alinha Face = título com o id da conversa da Bia (3F6791F1...-55...) ou com "Alinha Face".
 * Os demais compromissos da agenda nunca são lidos nem alterados.
 */
const URL_AGENDA = 'https://odamgyzklsndepklmicl.supabase.co/functions/v1/agenda';
const AGENDA_ID = 'gu.martins00@gmail.com';
const PREFIXO_CHAT = '3F6791F13320F0B1D9489ADC800E9477-';
const DIAS_ANTES = 3, DIAS_DEPOIS = 60;

function ehAlinhaFace_(ev) {
  const t = ev.getTitle() || '';
  return t.indexOf(PREFIXO_CHAT) === 0 || /alinha\s*face/i.test(t);
}

function chamar_(corpo) {
  const token = PropertiesService.getScriptProperties().getProperty('TOKEN');
  if (!token) throw new Error('Falta a propriedade TOKEN nas configurações do projeto.');
  const r = UrlFetchApp.fetch(URL_AGENDA, {
    method: 'post', contentType: 'application/json', muteHttpExceptions: true,
    headers: { 'x-agenda-token': token }, payload: JSON.stringify(corpo),
  });
  if (r.getResponseCode() !== 200) throw new Error('Funil respondeu ' + r.getResponseCode() + ': ' + r.getContentText().slice(0, 300));
  return JSON.parse(r.getContentText());
}

function eventosAlinhaFace_(cal, de, ate) {
  return cal.getEvents(de, ate)
    .filter(function (ev) { return !ev.isAllDayEvent() && !ev.isRecurringEvent() && ehAlinhaFace_(ev); })
    .map(function (ev) {
      return { id: ev.getId(), titulo: ev.getTitle(), desc: (ev.getDescription() || '').slice(0, 1500),
               local: ev.getLocation() || '', inicio: ev.getStartTime().toISOString(), fim: ev.getEndTime().toISOString() };
    });
}

function normaliza_(s) { return String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase(); }

function rodar_(simular) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(1000)) return;            // já tem uma rodada em andamento
  try {
    const cal = CalendarApp.getCalendarById(AGENDA_ID);
    if (!cal) throw new Error('Esta conta não enxerga a agenda ' + AGENDA_ID);
    const agora = new Date();
    const de = new Date(agora.getTime() - DIAS_ANTES * 864e5), ate = new Date(agora.getTime() + DIAS_DEPOIS * 864e5);
    const eventos = eventosAlinhaFace_(cal, de, ate);
    const res = chamar_({ acao: 'google', eventos: eventos, de: de.toISOString(), ate: ate.toISOString(), simular: simular ? 'true' : '' });
    if (simular) { Logger.log(JSON.stringify(res, null, 2)); return res; }

    const vinculos = [];
    (res.criar || []).forEach(function (c) {
      const ini = new Date(c.inicio), fim = new Date(c.fim);
      // já existe evento nesse horário com o nome do paciente? liga em vez de duplicar
      const nome = normaliza_(c.titulo.replace(/^Alinha Face\s*[—-]\s*/, '').replace(/\s*\(.*\)\s*$/, '')).split(/\s+/).filter(function (w) { return w.length >= 3; }).slice(0, 2);
      const igual = nome.length ? cal.getEvents(ini, fim).filter(function (ev) {
        const t = normaliza_(ev.getTitle());
        return ev.getStartTime().getTime() === ini.getTime() && nome.every(function (w) { return t.indexOf(w) >= 0; });
      })[0] : null;
      const ev = igual || cal.createEvent(c.titulo, ini, fim, { description: c.desc, location: c.local });
      vinculos.push({ paciente_id: c.paciente_id, evento_id: ev.getId(), inicio: ev.getStartTime().toISOString() });
    });
    (res.mover || []).forEach(function (m) {
      const ev = cal.getEventById(m.evento_id);
      if (ev) ev.setTime(new Date(m.inicio), new Date(m.fim));
    });
    (res.apagar || []).forEach(function (id) {
      const ev = cal.getEventById(id);
      if (ev && ehAlinhaFace_(ev)) ev.deleteEvent();   // só apaga evento da Alinha Face
    });
    if (vinculos.length) chamar_({ acao: 'google_vincular', vinculos: vinculos });
    Logger.log('eventos lidos: %s | criados: %s | movidos: %s | apagados: %s | fichas atualizadas: %s | fichas novas: %s',
      eventos.length, vinculos.length, (res.mover || []).length, (res.apagar || []).length, res.fichas_atualizadas, res.fichas_novas);
  } finally { lock.releaseLock(); }
}

function sincronizar() { rodar_(false); }
function simular() { return rodar_(true); }

function instalar() {
  ScriptApp.getProjectTriggers().forEach(function (t) { if (t.getHandlerFunction() === 'sincronizar') ScriptApp.deleteTrigger(t); });
  ScriptApp.newTrigger('sincronizar').timeBased().everyMinutes(5).create();
  sincronizar();
}
