// Login e perfil compartilhados por todas as páginas do site.
// Depende de config.js e do @supabase/supabase-js carregado antes.
(function(){
  const cfg = window.FUNIL_CONFIG || {};
  const sb = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
  });

  async function sessao(){
    const { data } = await sb.auth.getSession();
    return data.session || null;
  }

  async function perfil(){
    const s = await sessao();
    if(!s) return null;
    const email = (s.user.email || "").toLowerCase();
    const { data, error } = await sb.from("perfis").select("email,nome,papel").eq("email", email).maybeSingle();
    if(error || !data) return { email, nome: email, papel: null };
    return data;
  }

  // Garante login e o papel certo; senão manda para a tela de entrada.
  async function exigir(papeisAceitos){
    const p = await perfil();
    if(!p){ location.replace("index.html"); return new Promise(()=>{}); }
    if(!p.papel){ location.replace("index.html?semacesso=1"); return new Promise(()=>{}); }
    if(papeisAceitos && !papeisAceitos.includes(p.papel)){
      location.replace(p.papel === "admin" ? "painel.html" : "medico.html");
      return new Promise(()=>{});
    }
    return p;
  }

  async function sair(){
    await sb.auth.signOut();
    location.replace("index.html");
  }

  // Caixa simples para a pessoa trocar a própria senha (sem depender de e-mail).
  function trocarSenha(){
    document.getElementById("trocaSenha")?.remove();
    const fundo = document.createElement("div");
    fundo.id = "trocaSenha";
    fundo.style.cssText = "position:fixed;inset:0;background:rgba(10,18,32,.45);z-index:90;display:grid;place-items:center;padding:16px";
    fundo.innerHTML =
      '<form style="background:var(--surface);color:var(--ink);border-radius:12px;padding:22px;width:100%;max-width:360px;display:flex;flex-direction:column;gap:12px;box-shadow:var(--shadow);font-family:var(--font-body)">' +
      '<strong style="font-size:17px">Trocar minha senha</strong>' +
      '<label style="display:flex;flex-direction:column;gap:5px;font-size:13px">Nova senha (mínimo 8 caracteres)' +
      '<input type="password" name="s1" minlength="8" required autocomplete="new-password" style="border:1px solid var(--line-strong);border-radius:8px;padding:10px;background:var(--surface);color:var(--ink)"></label>' +
      '<label style="display:flex;flex-direction:column;gap:5px;font-size:13px">Repita a nova senha' +
      '<input type="password" name="s2" minlength="8" required autocomplete="new-password" style="border:1px solid var(--line-strong);border-radius:8px;padding:10px;background:var(--surface);color:var(--ink)"></label>' +
      '<div class="ts-msg" style="font-size:13px;color:var(--crit)"></div>' +
      '<div style="display:flex;gap:8px;justify-content:flex-end"><button type="button" class="btn btn-sm ts-cancel">Cancelar</button><button class="btn btn-sm btn-primary">Salvar senha</button></div>' +
      '</form>';
    document.body.appendChild(fundo);
    const f = fundo.querySelector("form"), msg = fundo.querySelector(".ts-msg");
    fundo.querySelector(".ts-cancel").onclick = ()=>fundo.remove();
    fundo.addEventListener("click", e=>{ if(e.target === fundo) fundo.remove(); });
    f.s1.focus();
    f.onsubmit = async e=>{
      e.preventDefault();
      if(f.s1.value !== f.s2.value){ msg.textContent = "As duas senhas não são iguais."; return; }
      const { error } = await sb.auth.updateUser({ password: f.s1.value });
      if(error){ msg.textContent = "Não consegui trocar. Use uma senha diferente da atual, com 8 ou mais caracteres."; return; }
      fundo.remove();
      const t = document.createElement("div"); t.className = "toast"; t.textContent = "Senha trocada.";
      document.body.appendChild(t); setTimeout(()=>t.remove(), 2600);
    };
  }

  window.FUNIL = { sb, sessao, perfil, exigir, sair, trocarSenha };
})();
