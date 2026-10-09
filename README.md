# Funil Alinha Face

Painel de acompanhamento de pacientes da Alinha Face (DTM/ATM e cirurgia ortognática).
Página única, sem build: todo o HTML, CSS e JavaScript ficam em `index.html`.

## Abas

- **Novos** — pacientes que falaram com a gente e ainda não têm próxima ação definida.
- **Dr. Gustavo** — casos que dependem de um retorno dele. Entram sozinhos quando a ficha
  tem a palavra "gustavo" nas observações ou na próxima ação.
- **Rotina do dia** — o que a aprendiz precisa fazer hoje: consultas de hoje e amanhã,
  régua pós-consulta, vouchers Blume, cirurgias em andamento, ações marcadas e leads parados.
- **Funil** — quadro por etapa, com arrastar e soltar entre colunas.
- **Tabela** — a mesma base em lista, ordenável.
- **Relatórios** — indicadores por período, com exportação em PDF.

## Etapas do funil

`triagem` · `lead` · `agendou` · `compareceu` · `exames_sol` · `exames_ok` · `retorno` ·
`proposta` · `docs_conv` · `autorizacao` · `autorizado` · `cir_marcada` · `cir_feita` ·
`posop` · `noshow` · `perdido`

## Dados

A página roda publicada como artifact no claude.ai e usa a capability `db` para guardar
as coleções `pacientes`, `encaminhamentos` e `ignorados`. Aberta fora desse ambiente, ela
entra em modo local: funciona para ver a interface, mas nada é salvo.

Uma tarefa agendada diária lê as conversas do WhatsApp no GPT Maker e atualiza as fichas,
casando os registros pelos 8 últimos dígitos do telefone. Ela nunca rebaixa a etapa de um
paciente nem mexe em histórico, voucher ou próxima ação — esses campos são da equipe.

## Como rodar localmente

Qualquer servidor estático serve:

```
python3 -m http.server 8000
```

E abrir `http://localhost:8000`. Sem a capability `db`, a página avisa que está em modo local.

## Publicação

O arquivo é publicado como artifact no claude.ai. O conteúdo de `index.html` é a página
inteira — não há etapa de build, bundler ou dependência externa além da fonte do Google
Fonts e do jsPDF (usado só para o PDF dos relatórios).
