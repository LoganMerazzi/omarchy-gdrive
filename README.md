# Google Drive

**Português** · [English](README.en.md)

Plugin do [Omarchy shell](https://omarchy.org) para o Google Drive montado com o `rclone`. Mostra na barra se o Drive está montado e, no painel, o espaço usado, as pastas marcadas com estrela no Drive e as pastas da raiz. Pastas com estrela que estão no Meu Drive abrem no gerenciador de arquivos; as compartilhadas com você (fora do mount) abrem no navegador.

![Google Drive: painel com o status de montagem, o armazenamento, as pastas com estrela e as pastas da raiz (nomes borrados)](screenshots/gdrive.png)

O script `gdrive` segue o idioma do sistema: português para `pt*`, inglês nos outros casos.

## Instalação

```bash
omarchy plugin add https://github.com/LoganMerazzi/omarchy-gdrive.git --enable
~/.config/omarchy/plugins/logan.gdrive/extras/install.sh
```

O `extras/install.sh`:

1. instala o script `extras/gdrive` em `~/.local/bin/gdrive`, que o painel usa para montar, abrir e editar;
2. instala `extras/rclone-gdrive.service` em `~/.config/systemd/user/`. Ele monta o remote `gdrive:` em `~/GoogleDrive` com `--vfs-cache-mode full`;
3. roda `gdrive setup`: instala o `rclone` se faltar, pergunta (opcionalmente) por um client OAuth próprio, cria o remote `gdrive` (abre o navegador para autorizar) e ativa o serviço.

A configuração do rclone, com o token, fica em `~/.config/rclone/rclone.conf`, fora do repositório.

## Client do Google: padrão ou próprio?

Sem nenhuma configuração extra, o plugin usa o client OAuth padrão do rclone. Basta apertar Enter quando o `gdrive setup` pedir o Client ID. Esse client é compartilhado por todos os usuários do rclone, por isso:

- erros de limite da API são comuns, e o Drive fica lento ou mostra pastas como ilegíveis;
- o rclone avisa que ele vai parar de funcionar durante 2026.

Para uso diário, o recomendado é criar um client seu no Google Cloud. É grátis, leva uns 10 minutos e dá cota própria. O guia [docs/client-id.md](docs/client-id.md) explica os prós e contras, o passo a passo e os erros comuns (app em modo Testing, botão "Publish app" desabilitado etc.).

Para trocar o client de uma instalação que já existe:

```bash
gdrive client
```

## Requisitos

- `rclone`, `fuse3`
- `curl`, usado para montar o caminho das pastas com estrela
- um gerenciador de arquivos definido como padrão para `inode/directory` (Flea, Folio, Nautilus…). As pastas abrem com `xdg-open`, então trocar de gerenciador não exige mudança no plugin

## Atualizar

```bash
omarchy plugin update logan.gdrive && omarchy restart shell
```

Se o `extras/gdrive` mudou na atualização, rode `extras/install.sh` de novo para atualizar o `~/.local/bin/gdrive`. Ele não recria o remote se ele já existir.

## Privacidade

Veja [PRIVACY.md](PRIVACY.md).
