# Google Drive

Plugin do [Omarchy shell](https://omarchy.org) para o Google Drive montado com o `rclone`. Mostra na barra se o Drive está montado e, no painel, o espaço usado, as pastas marcadas com estrela no Drive e as pastas da raiz. Pastas com estrela que estão no Meu Drive abrem no gerenciador de arquivos; as compartilhadas com você (fora do mount) abrem no navegador.

![Google Drive: painel com o status de montagem, o armazenamento, as pastas com estrela e as pastas da raiz (nomes borrados)](screenshots/gdrive.png)

## Instalação

```bash
omarchy plugin add https://github.com/LoganMerazzi/omarchy-gdrive.git --enable
~/.config/omarchy/plugins/logan.gdrive/extras/install.sh
```

O `extras/install.sh`:

1. instala o script `extras/gdrive` em `~/.local/bin/gdrive`, que o painel usa para montar, abrir e editar;
2. instala `extras/rclone-gdrive.service` em `~/.config/systemd/user/`. Ele monta o remote `gdrive:` em `~/GoogleDrive` com `--vfs-cache-mode full`;
3. roda `gdrive setup`: instala o `rclone` se faltar, cria o remote `gdrive` (abre o navegador para autorizar) e ativa o serviço.

A configuração do rclone, com o token, fica em `~/.config/rclone/rclone.conf`, fora do repositório.

## Requisitos

- `rclone`, `fuse3`
- `curl`, usado para montar o caminho das pastas com estrela
- um gerenciador de arquivos definido como padrão para `inode/directory` (Flea, Folio, Nautilus…). As pastas abrem com `xdg-open`, então trocar de gerenciador não exige mudança no plugin

## Atualizar

```bash
omarchy plugin update logan.gdrive && omarchy restart shell
```
