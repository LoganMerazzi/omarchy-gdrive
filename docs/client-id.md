# Usar seu próprio client_id do Google

**Português** · [English](client-id.en.md)

O plugin funciona sem nenhuma configuração no Google Cloud. Este guia explica quando vale a pena criar um client OAuth próprio e como fazer isso.

## O cenário

Para acessar o Google Drive, o rclone precisa de um **client OAuth**: um "app" registrado no Google, identificado por um `client_id` e um `client_secret`. Há duas opções:

| | Client padrão do rclone | Client próprio |
|---|---|---|
| Configuração | nenhuma: é o padrão do `gdrive setup` | ~10 min no Google Cloud Console |
| Cota da API | dividida com **todos os usuários do rclone no mundo** | só sua |
| Erros de limite (`403 rateLimitExceeded`) | frequentes em horários de pico | praticamente nunca |
| Futuro | o rclone avisa que ele está sendo aposentado e vai parar de funcionar durante 2026 | não depende do rclone |
| Custo | grátis | grátis: a Drive API não é cobrada e não precisa de cartão nem de faturamento |
| Tela de autorização | "rclone" verificado | aviso "O Google não verificou este app" (normal: o app é seu) |

Quando o client padrão atinge o limite, o mount fica lento ou falha, e o gerenciador de arquivos mostra a pasta como ilegível. O painel também pode deixar de atualizar o espaço usado e as pastas com estrela até a cota voltar.

**Recomendação:** use o client padrão para experimentar. Para uso diário, crie o seu.

### Por que o plugin não traz um client pronto?

Tecnicamente seria possível embutir um client no plugin, mas:

- o escopo `drive` é **restrito** para o Google, e um app não verificado aceita no máximo **100 usuários ao longo de toda a vida do projeto**;
- para verificar um app com escopo restrito, o Google exige uma auditoria de segurança paga (CASA);
- a cota seria dividida entre todos os usuários do plugin, e o problema do client compartilhado voltaria em menor escala.

Por isso cada pessoa cria o seu. O client é pessoal e fica só na sua máquina, em `~/.config/rclone/rclone.conf`.

## Passo a passo

### 1. Criar o projeto e ativar a API

1. Crie um projeto em https://console.cloud.google.com/projectcreate (ex.: `rclone-gdrive`).
2. Com o projeto selecionado no topo da página, ative a **Google Drive API**: https://console.cloud.google.com/apis/library/drive.googleapis.com → **Ativar**.

O console pode oferecer um "teste gratuito" ou pedir para ativar o faturamento. Ignore: nada aqui precisa disso.

### 2. Configurar o app (Google Auth Platform)

1. Abra https://console.cloud.google.com/auth/overview → **Começar**:
   - **Nome do app:** `rclone`
   - **E-mail de suporte:** o seu
   - **Público:** Externo
   - **Contato:** o seu e-mail
2. Em **Branding**, preencha também:
   - **Application home page:** qualquer página sua, por exemplo `https://github.com/LoganMerazzi/omarchy-gdrive`
   - **Application privacy policy link:** por exemplo `https://github.com/LoganMerazzi/omarchy-gdrive/blob/main/PRIVACY.md`

   Os dois links são **obrigatórios para publicar** o app. Sem eles, o botão **Publish app** fica cinza. Como o app não passa por verificação, o Google não analisa o conteúdo das páginas. Não envie logo: com logo, o Google exige verificação.
3. Clique em **Save**.

### 3. Publicar o app

Em **Audience**, clique em **Publish app** → **Confirmar**. O status deve mudar para **In production**.

> **Não deixe o app em modo "Testing".** Em teste, só os e-mails cadastrados em *Test users* conseguem autorizar, e **o token expira a cada 7 dias**: o Drive desmonta sozinho toda semana.

### 4. Criar o client

Em **Clients** → **Create client**:

- **Tipo:** Desktop app
- **Nome:** `rclone`

Copie o **Client ID** e o **Client secret**. Se aparecer o aviso *"OAuth access is restricted to the test users"*, o app ainda não foi publicado: volte ao passo 3.

### 5. Usar o client no plugin

- **Instalação nova:** rode `gdrive setup` (ou `extras/install.sh`) e cole o ID e o secret quando o script pedir.
- **Remote que já existe:** rode `gdrive client`. O script grava o ID e o secret, reautoriza no navegador e reinicia o mount.

Na autorização, o Google mostra **"O Google não verificou este app"**. Clique em **Avançado** → **Acessar rclone (não seguro)**, marque o acesso ao Drive e clique em **Continuar**.

Para conferir: `rclone about gdrive:` não deve mais mostrar o aviso sobre o *shared client_id*.

## Várias máquinas

Use o **mesmo** client em todas: rode `gdrive client` em cada uma, com o mesmo ID e secret. Cada máquina recebe o próprio token.

## Problemas comuns

| Sintoma | Causa | Solução |
|---|---|---|
| `Erro 403: access_denied` / "o app não concluiu o processo de verificação" | app em modo Testing | publicar o app (passo 3) |
| **Publish app** cinza | faltam a página inicial ou a política de privacidade no Branding | preencher os dois links (passo 2) |
| O Drive para de montar depois de uma semana | app em Testing: o token expira em 7 dias | publicar o app e rodar `gdrive client` de novo |
| `403 rateLimitExceeded` | ainda está usando o client padrão | conferir o `client_id` com `rclone config show gdrive` |

## Voltar ao client padrão

```bash
rclone config update gdrive client_id= client_secret=
rclone config reconnect gdrive:
systemctl --user restart rclone-gdrive
```

Para revogar o acesso de qualquer client: https://myaccount.google.com/permissions.
