{ config, pkgs, ... }:

let
  # generally avoiding unstable but using it to keep up with some
  # particularly fast-moving programs like nushell
  pkgsUnstable = import <nixos-unstable> { };

  # directories to ignore in tree and fzf listings because they're
  # never what I'm looking for and make lists too big to navigate
  listIgnores = [
    ".git"
    "node_modules"
    "build"
    "target"
    "__pycache__"
    ".cache"
    ".pytest_cache"
    ".mypy_cache"
  ];
  # aliases for multiple shells in one place,
  # separated into abbrs and aliases for fish
  fishAbbrs = {
    l = "lsd -al";
    ltd = "lt --depth";
    nnp = "nnn -adHe -P p";
    docc = "docker-compose";
    clip = "xclip -sel clip";
    today = "date +%F";
    datetime = "date +%FT%T%z";
    shut = "sudo systemctl poweroff";
    rebo = "sudo systemctl reboot";
    # git
    ga = "git add";
    gc = "git commit -v";
    gl = "git pull";
    gf = "git fetch";
    gco = "git checkout";
    gs = "git switch";
    gre = "git restore";
    gd = "git diff";
    gsh = "git show";
    gsl = "git showl";
    gst = "git status";
    gb = "git branch";
    gsta = "git stash";
    gstp = "git stash pop";
    glg = "git log --stat";
    glga = "git log --stat --graph --all";
    glo = "git log --oneline";
    gloa = "git log --oneline --graph --all";
    grh = "git reset HEAD";
  };
  fishAliases = {
    lt = builtins.concatStringsSep " " (
      [ "lsd --tree -a" ] ++
      (map (i: "-I " + i) listIgnores)
    );
  };
  shellAliases = fishAbbrs // fishAliases;
  nuAliases = shellAliases // {
    today = "(date now | date format \"%F\")";
    datetime = "(date now | date format \"%FT%T%z\")";
  };
  nuAliasesStr = builtins.concatStringsSep "\n"
    (pkgs.lib.mapAttrsToList (k: v: "alias ${k} = ${v}") nuAliases);

  # helper script because I always forget the exact way to nix-prefetch-url from github
  prefetchGithub = pkgs.writeScriptBin "nix-prefetch-github" ''
    #! /usr/bin/env bash
    if [ "$#" -ne 3 ]; then
      echo "usage: nix-prefetch-github <owner> <repo> <rev>"
      exit 1
    fi
    nix-prefetch-url --unpack "https://github.com/$1/$2/archive/$3.tar.gz"
  '';
in
{
  nixpkgs.config.allowUnfree = true;
  programs = {
    #
    # GIT
    #
    git = {
      enable = true;
      userName = "Mikael Myyrä";
      userEmail = "mikael.myyrae@gmail.com";
      signing.signByDefault = true;
      signing.key = "EBDEF166B95A3FB8";
      ignores = [
        "*.nogit*"
        ".envrc"
        ".direnv"
        ".vscode"
        ".vim"
        "Session.vim"
        "compile_commands.json"
        ".cache"
      ];
      lfs.enable = true;
      delta.enable = true;
      extraConfig = {
        pull = { rebase = true; };
        fetch = { prune = true; };
        diff = { colorMoved = "zebra"; };
        init = { defaultBranch = "main"; };
      };
      aliases = {
        fixup = pkgs.lib.concatStrings [
          "!git log -n 50 --pretty=format:'%h %s' --no-merges "
          "| fzf | cut -c -7 "
          "| xargs -o git commit --fixup"
        ];
        chpick = pkgs.lib.concatStrings [
          "!git log --all -n 50 --pretty=format:'%h %s' --no-merges "
          "| fzf | cut -c -7 "
          "| xargs -o git cherry-pick"
        ];
        showl = pkgs.lib.concatStrings [
          "!git log --all -n 50 --pretty=format:'%h %s' --no-merges "
          "| fzf | cut -c -7 "
          "| xargs -o git show"
        ];
      };
    };
    #
    # FISH
    #
    fish = {
      enable = true;
      interactiveShellInit = ''
        if not set -q TMUX
          exec tmux
        end
      '';
      shellAbbrs = fishAbbrs;
      shellAliases = fishAliases;
    };
    #
    # NUSHELL
    #
    nushell = {
      # nushell is not set as login shell because it doesn't have the right
      # environment variable setup and making it by hand is cumbersome.
      # instead, fish is login shell, set up to automatically start tmux,
      # and the tmux default command is set to "exec nu"
      enable = true;
      # changes come frequently enough and make big enough changes to online docs
      # to warrant getting the version on unstable
      package = pkgsUnstable.nushell;
      configFile.text =
        ''
          let-env config = {
            show_banner: false
            edit_mode: vi
            cursor_shape: {
              vi_insert: line
              vi_normal: block
            }
            completions: {
              external: {
                enable: true
                max_results: 100
                completer: {|spans|
                  carapace $spans.0 nushell $spans | from json
                }
              }
            }
            keybindings: [
              {
                name: fzf_file
                modifier: control
                keycode: char_f
                mode: [emacs, vi_insert, vi_normal]
                event: {
                  send: executehostcommand
                  # big messy command to wrap the result in ticks only if it has spaces or quotes
                  cmd: `commandline --insert (fzf --height=50% | str trim | do { let res = $in; if (["'", '"', " "] | any { $in in $res }) { $'`($res)`' } else { $res }})`
                }
              },
              {
                name: fzf_dir
                modifier: alt
                keycode: char_f
                mode: [emacs, vi_insert, vi_normal]
                event: {
                  send: executehostcommand
                  cmd: `commandline --insert (fd --type d | fzf --height=50% | str trim | do { let res = $in; if (["'", '"', " "] | any { $in in $res }) { $'`($res)`' } else { $res }})`
                }
              },
            ]
          }

          ${nuAliasesStr}

          # direnv
          # taken from home-manager git master; TODO: remove once it lands on stable
          let-env config = ($env | default {} config).config
          let-env config = ($env.config | default {} hooks)
          let-env config = ($env.config | update hooks ($env.config.hooks | default [] pre_prompt))
          let-env config = ($env.config | update hooks.pre_prompt ($env.config.hooks.pre_prompt | append {
            code: "
              let direnv = (${pkgs.direnv}/bin/direnv export json | from json)
              let direnv = if ($direnv | length) == 1 { $direnv } else { {} }
              $direnv | load-env
              "
          }))

          # zoxide (generated with `zoxide init nushell`
          # since home-manager doesn't currently have automation for this)

          let-env config = ($env | default {} config).config
          let-env config = ($env.config | default {} hooks)
          let-env config = ($env.config | update hooks ($env.config.hooks | default {} env_change))
          let-env config = ($env.config | update hooks.env_change ($env.config.hooks.env_change | default [] PWD))
          let-env config = ($env.config | update hooks.env_change.PWD ($env.config.hooks.env_change.PWD | append {|_, dir|
            zoxide add -- $dir
          }))

          # Jump to a directory using only keywords.
          def-env __zoxide_z [...rest:string] {
            let arg0 = ($rest | append '~').0
            let path = if (($rest | length) <= 1) and ($arg0 == '-' or ($arg0 | path expand | path type) == dir) {
              $arg0
            } else {
              (zoxide query --exclude $env.PWD -- $rest | str trim -r -c "\n")
            }
            cd $path
          }

          # Jump to a directory using interactive search.
          def-env __zoxide_zi  [...rest:string] {
            cd $'(zoxide query -i -- $rest | str trim -r -c "\n")'
          }

          alias z = __zoxide_z
          alias zi = __zoxide_zi
        '';
      envFile.text = ''
        # starship

        let-env STARSHIP_SHELL = "nu"

        def create_left_prompt [] {
            starship prompt --cmd-duration $env.CMD_DURATION_MS $'--status=($env.LAST_EXIT_CODE)'
        }

        let-env PROMPT_COMMAND = { create_left_prompt }
        let-env PROMPT_COMMAND_RIGHT = ""

        # starship brings its own indicator char
        let-env PROMPT_INDICATOR_VI_INSERT = ""
        let-env PROMPT_INDICATOR_VI_NORMAL = ""
        let-env PROMPT_MULTILINE_INDICATOR = "| "
      '';
    };
    #
    # STARSHIP
    #
    starship = {
      enable = true;
      # get from unstable to ensure compatibility with nushell from unstable
      package = pkgsUnstable.starship;
      settings = {
        format = pkgs.lib.concatStrings [
          "$username"
          "$hostname"
          "$directory"
          "$git_branch"
          "$git_state"
          "$git_status"
          "$rust"
          "$cmd_duration"
          "$line_break"
          "$jobs"
          "$battery"
          "$nix_shell"
          "$character"
        ];
        cmd_duration.min_time = 1;
        directory.fish_style_pwd_dir_length = 1;
        git_status = {
          ahead = "⇡$count";
          diverged = "⇕⇡$ahead_count⇣$behind_count";
          behind = "⇣$count";
          modified = "*";
        };
        nix_shell = {
          format = "[$state ]($style)";
          impure_msg = "λ";
          pure_msg = "λλ";
        };
        package.disabled = true;
      };
    };
    #
    # KITTY
    #
    kitty = {
      enable = true;
      font = {
        name = "JetBrains Mono Medium Nerd Font Complete";
        package = pkgs.jetbrains-mono;
      };
      settings = {
        font_size = 11;
        disable_ligatures = "cursor";
        # theme from https://github.com/bluz71/vim-nightfly-colors
        background = "#011627";
        foreground = "#acb4c2";
        cursor = "#9ca1aa";
        color0 = "#1d3b53";
        color1 = "#fc514e";
        color2 = "#a1cd5e";
        color3 = "#e3d18a";
        color4 = "#82aaff";
        color5 = "#c792ea";
        color6 = "#7fdbca";
        color7 = "#a1aab8";
        color8 = "#7c8f8f";
        color9 = "#ff5874";
        color10 = "#21c7a8";
        color11 = "#ecc48d";
        color12 = "#82aaff";
        color13 = "#ae81ff";
        color14 = "#7fdbca";
        color15 = "#d6deeb";
        selection_background = "#b2ceee";
        selection_foreground = "#080808";
      };
    };
    #
    # TMUX
    #
    tmux = {
      enable = true;
      shortcut = "t";
      terminal = "screen-256color";
      keyMode = "vi";
      escapeTime = 0;
      extraConfig = ''
        # run nushell through fish (not as login shell)
        # to get necessary environment variables.
        # exec required to have new panes created in the current directory
        set -g default-command "exec nu"

        # navigate panes with alt-arrow
        bind -n M-Right select-pane -R
        bind -n M-Up select-pane -U
        bind -n M-Left select-pane -L
        bind -n M-Down select-pane -D

        # navigate tabs
        bind -n M-C-NPage next-window
        bind -n M-C-PPage previous-window

        # splits & tabs
        bind > split-window -h -c "#{pane_current_path}"
        bind v split-window -v -c "#{pane_current_path}"
        bind t new-window -c "#{pane_current_path}"
        # send pane to other existing window
        bind \" choose-window "join-pane -h -t '%%'"

        # vim-style copy-paste
        bind u copy-mode
        bind p paste-buffer
        bind -T copy-mode-vi v send-keys -X begin-selection
        bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel
        bind -T copy-mode-vi r send-keys -X rectangle-toggle
        # copy also to clipboard
        bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "xclip -sel clip -i"

        set -g mouse on
        set -g focus-events on

        # bells off
        set -g visual-activity off
        set -g visual-bell off
        set -g visual-silence off
        setw -g monitor-activity off
        set -g bell-action none

        # theming (only tmux-specific parts, rest done via kitty)

        # pane borders
        set -g pane-border-style 'fg=black'
        set -g pane-active-border-style 'fg=green'

        # statusbar
        set -g status-style 'bg=black fg=white'
        set -g status-left ""
        set -g status-right '%d.%m. %H:%M '
        set -g status-left-length 20
        setw -g window-status-style 'bg=black fg=white'
        setw -g window-status-current-style 'bg=green fg=black bold'
        setw -g window-status-format ' #I:#W#F '
        setw -g window-status-current-format ' #I:#W#F '
      '';
    };
    #
    # NNN
    #
    nnn = {
      enable = true;
      package = pkgs.nnn.override ({ withNerdIcons = true; });
      extraPackages = with pkgs; [
        tabbed
        catimg
        ffmpegthumbnailer
        mediainfo
        sxiv
        mpv
        zathura
      ];
      plugins.src = (pkgs.fetchFromGitHub {
        owner = "jarun";
        repo = "nnn";
        rev = "v4.4";
        sha256 = "15w7jjhzyj1fq1c8f956pj7s729w8h3dih2ghxiann68rw4rmlc3";
      }) + "/plugins";
      plugins.mappings = {
        p = "preview-tui";
        P = "preview-tabbed";
        i = "imgview";
        # need the escaped backslash or the $nnn variable disappears during build
        C = "!convert \\$nnn jpeg:- | xclip -sel clip -t image/jpeg*";
        c = "cat \\$nnn | xclip -sel clip*";
      };
    };
    #
    # VIM
    #
    neovim = {
      enable = true;
      vimAlias = true;
      #
      # non-plugin configs
      #
      extraConfig = ''
        nnoremap <space> <Nop>
        map <space> <leader>
        map <space> <localleader>

        set autoread
        set hidden
        " buffer controls replaced with bufferline-nvim
        " (in the plugins -> visual section of the config)
        " nnoremap <silent><C-PageUp> :bp<cr>
        " nnoremap <silent><C-PageDown> :bn<cr>
        nnoremap <silent><leader>w :bdelete<cr>

        " netrw off
        let loaded_netrwPlugin = 1

        set mouse=a
        set scrolloff=15
        set clipboard=unnamedplus
        " reload file if it's been changed on disk
        au FocusGained,BufEnter * :checktime
        nnoremap <Home> ^

        set nobackup
        set nowritebackup

        set cursorline
        set cursorcolumn
        set conceallevel=1
        set concealcursor=
        set ignorecase
        set smartcase
      '';
      plugins = with pkgs.vimPlugins; [
        #
        # LSP and utilities
        #
        {
          plugin = nvim-lspconfig;
          config = ''
            lua << EOF
            -- keybinds

            local opts = { noremap=true, silent=true }
            vim.keymap.set('n', '<leader>d', vim.diagnostic.open_float, opts)
            vim.keymap.set('n', 'gN', vim.diagnostic.goto_prev, opts)
            vim.keymap.set('n', 'gn', vim.diagnostic.goto_next, opts)

            -- using telescope for anything that produces lists
            local tel = require('telescope.builtin')

            vim.keymap.set('n', '<C-p>', tel.find_files, opts)
            vim.keymap.set('n', '<leader>f', tel.live_grep, opts)
            vim.keymap.set('n', '<leader>.', tel.resume, opts)
            vim.keymap.set('n', 'gr', tel.lsp_references, opts)
            vim.keymap.set('n', 'gi', tel.lsp_implementations, opts)
            vim.keymap.set('n', '<leader>s', tel.lsp_document_symbols, opts)
            vim.keymap.set('n', '<leader>S', tel.lsp_workspace_symbols, opts)
            vim.keymap.set('n', 'gd', tel.lsp_definitions, opts)
            vim.keymap.set('n', '<leader>gd', tel.lsp_type_definitions, opts)
            vim.keymap.set('n', '<leader>M', tel.diagnostics, opts)
            vim.keymap.set('n', '<leader>m', function() tel.diagnostics({bufnr=0}) end, opts)

            local on_attach = function(client, bufnr)
              vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
              local bufopts = { noremap=true, silent=true, buffer=bufnr }
              vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, bufopts)
              vim.keymap.set('n', '<leader>h', vim.lsp.buf.hover, bufopts)
              vim.keymap.set('n', '<F2>', vim.lsp.buf.rename, bufopts)
              vim.keymap.set('n', '<leader>,', vim.lsp.buf.code_action, bufopts)
              vim.keymap.set('n', 'gq', vim.lsp.buf.range_formatting, bufopts)

              -- override tsserver formatting with prettier from null-ls
              if client.name == 'tsserver' then
                client.server_capabilities.document_formatting = false
              end
            end

            -- format on save
            vim.cmd [[autocmd BufWritePre * lua vim.lsp.buf.format()]]

            -- completion using cmp-nvim
            local capabilities = require('cmp_nvim_lsp').default_capabilities()
            local enable = function(lsp_name, args)
              local args = args or {}
              args["on_attach"] = on_attach
              args["capabilities"] = capabilities
              require('lspconfig')[lsp_name].setup(args)
            end
              
            -- enable servers

            enable('rust_analyzer', {
              cmd = { "${pkgs.rust-analyzer}/bin/rust-analyzer" },
              settings = {
                ["rust-analyzer"] = {
                  checkOnSave = { command = "clippy" },
                }
              },
            })
            enable('clangd', {
              cmd = { "${pkgs.clang-tools}/bin/clangd" },
            })
            enable('tsserver', {
              cmd = {
                "${pkgs.nodePackages.typescript-language-server}/bin/typescript-language-server",
                "--stdio",
                "--tsserver-path",
                "${pkgs.nodePackages.typescript}/lib/node_modules/typescript/lib/",
              },
            })
            enable('jsonls', {
              cmd = {
                "${pkgs.nodePackages.vscode-json-languageserver}/bin/vscode-json-languageserver",
                "--stdio",
              },
            })
            enable('rnix', {
              cmd = { "${pkgs.rnix-lsp}/bin/rnix-lsp" },
            })
            enable('pyright', {
              cmd = { "${pkgs.pyright}/bin/pyright-langserver", "--stdio" },
            })

            -- nicer diagnostic icons

            local signs = {
                Error = " ",
                Warn = " ",
                Hint = " ",
                Info = " "
            }
            for type, icon in pairs(signs) do
                local hl = "DiagnosticSign" .. type
                vim.fn.sign_define(hl, {text = icon, texthl = hl, numhl = hl})
            end
            vim.diagnostic.config({
              -- prioritize errors and warnings in the sign column, otherwise everything looks like hints
              severity_sort = true,
              virtual_text = {
                prefix = "●",
                source = "if_many",
              },
            })
            EOF
          '';
        }
        # null-ls for formatters that don't come with lspconfig
        {
          plugin = null-ls-nvim;
          config = ''
            lua << EOF
            local null_ls = require('null-ls')
            null_ls.setup {
              debug = true,
              sources = {
                null_ls.builtins.formatting.isort,
                null_ls.builtins.formatting.black,
                null_ls.builtins.formatting.prettier,
              },
            }
            EOF
          '';
        }
        {
          # bindings for telescope defined in the LSP section above
          plugin = telescope-nvim;
          config = ''
            lua << EOF
            local actions = require('telescope.actions')
            require('telescope').setup {
              defaults = {
                mappings = {
                  i = {
                    ["<esc>"] = actions.close
                  },
                },
                layout_config = {
                  vertical = { width = 0.6, height = 0.9 },
                },
                layout_strategy = "vertical",
              },
              pickers = {
                find_files = {
                  layout_strategy = "horizontal",
                  -- remove leading ./, include gitignored and hidden files
                  -- (except the stuff in listIgnores which is big and doesn't need to be seen)
                  find_command = {
                    "fd", "--type", "f", "--strip-cwd-prefix", "--no-ignore", "--hidden",
                    ${pkgs.lib.strings.concatMapStrings (i: ''"--exclude","${i}",'') listIgnores}
                  },
                },
              },
            }
            EOF
          '';
        }
        # completions with cmp-nvim
        cmp-nvim-lsp
        cmp-nvim-ultisnips
        cmp-omni
        {
          plugin = nvim-cmp;
          # from https://github.com/hrsh7th/nvim-cmp
          config = ''
            set completeopt=menu,menuone,noselect
            lua <<EOF
              require("cmp_nvim_ultisnips").setup {
                -- fixes snippets not working inside markdown math blocks
                filetype_source = "ultisnips_default",
              }

              local cmp = require('cmp')
              cmp.setup({
                snippet = {
                  expand = function(args)
                    vim.fn["UltiSnips#Anon"](args.body)
                  end,
                },
                window = {
                  -- completion = cmp.config.window.bordered(),
                  -- documentation = cmp.config.window.bordered(),
                },
                mapping = cmp.mapping.preset.insert({
                  ['<C-u>'] = cmp.mapping.scroll_docs(-8),
                  ['<C-d>'] = cmp.mapping.scroll_docs(8),
                  ['<C-Space>'] = cmp.mapping.complete(),
                  ['<C-e>'] = cmp.mapping.abort(),
                  ['<CR>'] = cmp.mapping.confirm({ select = true }),
                }),
                sources = cmp.config.sources({
                  { name = 'nvim_lsp' },
                  { name = 'omni' },
                  { name = 'ultisnips' },
                }, {
                  { name = 'buffer' },
                })
              })

              -- Use buffer source for `/` (if you enabled `native_menu`, this won't work anymore).
              cmp.setup.cmdline('/', {
                mapping = cmp.mapping.preset.cmdline(),
                sources = {
                  { name = 'buffer' }
                }
              })

              -- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
              cmp.setup.cmdline(':', {
                mapping = cmp.mapping.preset.cmdline(),
                sources = cmp.config.sources({
                  { name = 'path' }
                }, {
                  { name = 'cmdline' }
                })
              })
            EOF
          '';
        }

        #
        # non-LSP language utilities
        #

        {
          plugin = vim-markdown;
          config = ''
            let g:vim_markdown_folding_disabled = 1
            let g:vim_markdown_math = 1
            let g:vim_markdown_toml_frontmatter = 1
          '';
        }
        {
          plugin = vimtex;
          config = ''
            let g:tex_flavor = 'latex'
            let g:tex_conceal = 'abdmg'
            autocmd FileType tex,markdown set conceallevel=1
            " for some reason this is empty by default, copied from docs
            let g:vimtex_compiler_latexmk_engines = {
              \ '_'                : '-pdf',
              \ 'pdflatex'         : '-pdf',
              \ 'dvipdfex'         : '-pdfdvi',
              \ 'lualatex'         : '-lualatex',
              \ 'xelatex'          : '-xelatex -shell-escape',
              \ 'context (pdftex)' : '-pdf -pdflatex=texexec',
              \ 'context (luatex)' : '-pdf -pdflatex=context',
              \ 'context (xetex)'  : '-pdf -pdflatex=""texexec --xtx""',
              \}
            let g:vimtex_view_method='zathura'
          '';
        }
        {
          # requires a `jupytext` executable in the path,
          # can be installed as a python package from nixpkgs
          plugin = pkgs.vimUtils.buildVimPlugin {
            name = "jupytext-vim";
            pname = "jupytext-vim";
            src = pkgs.fetchFromGitHub {
              owner = "goerz";
              repo = "jupytext.vim";
              rev = "32c1e37b2edf63a7e38d0deb92cc3f1462cc4dcd";
              sha256 = "1jmimir6d0vz5cs0hcpa8v5ay7jm5xj91qkk0y4mbgms47bd43na";
            };
          };
        }

        #
        # visuals
        #
        {
          # custom fork of the oceanic-material theme
          plugin = pkgs.vimUtils.buildVimPlugin {
            name = "oceanic-material";
            pname = "oceanic-material";
            src = ../nvim/oceanic-material;
          };
          config = ''
            set termguicolors
            let g:oceanic_material_allow_bold=1
            let g:oceanic_material_allow_italic=1
            let g:oceanic_material_allow_underline=1
            let g:oceanic_material_allow_undercurl=1
            " not using this right now but leaving this in to easily switch back
            " color oceanic_material
          '';
        }
        {
          plugin = pkgs.vimUtils.buildVimPlugin {
            name = "nightfly";
            pname = "nightfly";
            src = pkgs.fetchFromGitHub {
              owner = "bluz71";
              repo = "vim-nightfly-guicolors";
              rev = "33d094aa4c5864796615af20026ab3d792cfd482";
              sha256 = "0l02wgzr7nz50ns1azxpkrm2hnv2dc84vyb04r8sxyynahlh9b7b";
            };
            # swap colors around for more green
            preInstall = ''
              substituteInPlace ./colors/nightfly.vim \
                --replace "highlight NightflyGreen" "__TMP__" \
                --replace "highlight NightflyBlue" "highlight NightflyGreen" \
                --replace "__TMP__" "highlight NightflyBlue" \
            '';
          };
          config = ''
            lua << EOF
            -- overrides
            local custom_highlight = vim.api.nvim_create_augroup("CustomHighlight", {})
            vim.api.nvim_create_autocmd("ColorScheme", {
              pattern = "nightfly",
              callback = function()
                vim.api.nvim_set_hl(0, "DiagnosticVirtualTextError", { link = "DiagnosticError" })
                vim.api.nvim_set_hl(0, "DiagnosticVirtualTextWarn", { link = "DiagnosticWarn" })
                vim.api.nvim_set_hl(0, "DiagnosticVirtualTextInfo", { link = "DiagnosticInfo" })
                vim.api.nvim_set_hl(0, "DiagnosticVirtualTextHint", { link = "DiagnosticHint" })
              end,
              group = custom_highlight,
            })
            EOF
            let g:nightflyCursorColor=1
            colorscheme nightfly
          '';
        }
        {
          plugin = indent-blankline-nvim;
          config = ''
            let g:indent_blankline_char_highlight_list = [
              \'NightflySlateBlue',
              \'NightflyRegalBlue',
            \]
          '';
        }
        {
          plugin = nvim-web-devicons;
          config = ''
            lua require("nvim-web-devicons").setup()
          '';
        }
        {
          plugin = gitsigns-nvim;
          config = ''
            " signcolumn flickers when no git signs if this isn't set
            set signcolumn=yes
            lua require("gitsigns").setup()
          '';
        }
        {
          plugin = feline-nvim;
          config = ''
            lua require("feline").setup()
          '';
        }
        {
          plugin = bufferline-nvim;
          config = ''
            lua << EOF
            require("bufferline").setup {
              options = {
                show_buffer_close_icons = false,
                separator_style = "slant",
                right_mouse_command = nil,
                middle_mouse_command = "bdelete %d",
              }
            }
            EOF
            nnoremap <silent><C-PageDown> :BufferLineCycleNext<CR>
            nnoremap <silent><C-PageUp> :BufferLineCyclePrev<CR>
            nnoremap <silent><leader><C-PageDown> :BufferLineMoveNext<CR>
            nnoremap <silent><leader><C-PageUp> :BufferLineMovePrev<CR>
          '';
        }

        # tree-sitter based highlighting

        nvim-ts-rainbow
        {
          plugin = nvim-treesitter.withPlugins (p: [
            p.tree-sitter-nix
            p.tree-sitter-rust
            p.tree-sitter-c
            p.tree-sitter-cpp
            p.tree-sitter-typescript
            p.tree-sitter-javascript
            p.tree-sitter-tsx
            p.tree-sitter-elm
            p.tree-sitter-haskell
            p.tree-sitter-python
            p.tree-sitter-markdown
            p.tree-sitter-markdown-inline
            p.tree-sitter-html
            p.tree-sitter-scss
            p.tree-sitter-css
            p.tree-sitter-make
            p.tree-sitter-bash
            p.tree-sitter-lua
            p.tree-sitter-latex
            p.tree-sitter-bibtex
            p.tree-sitter-toml
            p.tree-sitter-yaml
            p.tree-sitter-json
            p.tree-sitter-dockerfile
          ]);
          config = ''
            lua << EOF
            require'nvim-treesitter.configs'.setup {
              highlight = {
                enable = true,
                additional_vim_regex_highlighting = false,
              },
              rainbow = {
                enable = true,
                extended_mode = true,
                max_file_lines = nil,
              },
            }
            EOF
          '';
        }

        #
        # QOL / editing utilities
        #

        {
          plugin = pkgs.vimUtils.buildVimPlugin {
            name = "trailblazer";
            pname = "trailblazer";
            src = pkgs.fetchFromGitHub {
              owner = "LeonHeidelbach";
              repo = "trailblazer.nvim";
              rev = "65f073be8faf6189add5090d73e42830ed11447c";
              sha256 = "1bd3b8qkcwrm9255j86cabdjqah3kwwss062v1qjblkyhyx7zs4q";
            };
          };
          config = ''
            lua << EOF
            require("trailblazer").setup({
              trail_options = {
                available_trail_mark_modes = {
                  "global_chron",
                  "buffer_local_line_sorted",
                },
                trail_mark_symbol_line_indicators_enabled = true,
              },
              mappings = {
                nv = {
                  motions = {
                    new_trail_mark = '<A-l>',
                    track_back = '<A-L>',
                    peek_move_next_down = '<A-n>',
                    peek_move_previous_up = '<A-N>',
                    toggle_trail_mark_list = '<A-m>',
                  },
                  actions = {
                    delete_all_trail_marks = '<A-d>',
                    paste_at_last_trail_mark = '<A-p>',
                    paste_at_all_trail_marks = '<A-P>',
                    set_trail_mark_select_mode = '<A-t>',
                  },
                },
              },
            })
            EOF
          '';
        }
        {
          plugin = ultisnips;
          config = ''
            let g:UltiSnipsSnippetDirectories = [$HOME . '/.config/nvim/ultisnips']
            let g:UltiSnipsExpandTrigger = '<tab>'
            let g:UltiSnipsJumpForwardTrigger = '<tab>'
            let g:UltiSnipsJumpBackwardTrigger = '<s-tab>'
          '';
        }
        {
          plugin = git-messenger-vim;
          config = ''
            nmap <silent> gm <Plug>(git-messenger)
          '';
        }
        {
          plugin = hop-nvim;
          config = ''
            lua << EOF
            local hop = require('hop')
            hop.setup {
              -- colemak-friendly keys
              keys = "tsradneiohpfwqgluyjkbcxzvm,"
            }
            local opts = { noremap=true, silent=true }
            vim.keymap.set("", 'm', hop.hint_char1, opts)
            vim.keymap.set("", 'L', hop.hint_lines, opts)
            EOF
          '';
        }
        {
          plugin = vim-move;
          config = ''
            let g:move_map_keys = 0
            vmap <C-Up> <Plug>MoveBlockUp
            vmap <C-Down> <Plug>MoveBlockDown
            nmap <C-Up> <Plug>MoveLineUp
            nmap <C-Down> <Plug>MoveLineDown
            vmap <C-Left> <Plug>MoveBlockLeft
            vmap <C-Right> <Plug>MoveBlockRight
          '';
        }
        vim-smoothie # smooth scroll
        {
          # sessions fully automatically
          plugin = pkgs.vimUtils.buildVimPlugin {
            name = "auto-session";
            pname = "auto-session";
            src = pkgs.fetchFromGitHub {
              owner = "rmagatti";
              repo = "auto-session";
              rev = "9c302e01ebb474f9b19998488060d9f110ef75c5";
              sha256 = "0m9jjbrqvlhgzp8gcif678f6315jy1qrs86sc712q3ban9zs2ykw";
            };
          };
          config = ''
            lua require("auto-session").setup()
          '';
        }
        vim-commentary
        vim-surround
        vim-sleuth # autodetect tab settings

        {
          # discord rich presence, but opt-in with an environment variable
          plugin = presence-nvim;
          config = ''
            lua << EOF
            if vim.env.VIM_DISCORD_PRESENCE ~= nil then
              require("presence"):setup({
                neovim_image_text = "The text editor whomst is good",
                log_level = "error",
              })
            else
              -- setup with everything blacklisted, otherwise presence will setup itself
              require("presence"):setup({
                blacklist = {".*"}
              })
            end
            EOF
          '';
        }
      ];
    };
    #
    # MISC
    #
    firefox = {
      enable = true;
      package = (pkgs.firefox.override { extraNativeMessagingHosts = [ pkgs.passff-host ]; });
    };
    fzf = {
      enable = true;
      defaultCommand = pkgs.lib.strings.concatStrings (
        [ "rg --files --follow --no-ignore-vcs --hidden -g '!{" ]
        ++ (pkgs.lib.strings.intersperse "," (map (i: "**/" + i + "/*") listIgnores))
        ++ [ "}'" ]
      );
    };
    zathura.enable = true;
    zoxide.enable = true;
    lsd.enable = true;
    feh.enable = true;
    direnv.enable = true;
    home-manager.enable = true;
    nix-index.enable = true;
  };

  services = {
    lorri.enable = true;
    #
    # PICOM
    #
    picom = {
      enable = true;
      shadow = false;
      fade = true;
      fadeDelta = 4;
      inactiveOpacity = 0.90;
      opacityRules = [
        # Opaque at all times
        "100:class_g = 'firefox'"
        "100:class_g = 'feh'"
        "100:class_g = 'Sxiv'"
        "100:class_g = 'Zathura'"
        "100:class_g = 'Octave'"
        "100:class_g = 'vlc'"
        "100:class_g = 'mpv'"
        "100:class_g = 'obs'"
        "100:class_g = 'Wine'"
        "100:class_g = 'Microsoft Teams - Preview'"
        "100:class_g = 'zoom'"
        "100:class_g = 'krita'"
        "100:class_g = 'PureRef'"
        "100:class_g = 'tabbed'"
        "100:class_g = 'game'"
        # Slightly transparent even when focused
        "95:class_g = 'VSCodium' && focused"
        "95:class_g = 'discord' && focused"
        "95:class_g = 'Spotify' && focused"
        "95:class_g = 'kitty' && focused"
      ];
      settings = {
        blur =
          {
            method = "gaussian";
            size = 10;
            deviation = 5.0;
          };
        blur-background-exclude = [
          "name *= 'rect-overlay'" # teams screenshare overlay
          "name *= 'Peek'"
        ];
      };
      # fixes flickering problems with glx backend
      backend = "xrender";
    };
    unclutter.enable = true;
    redshift = {
      enable = true;
      temperature = {
        day = 6500;
        night = 5000;
      };
      latitude = "62.24";
      longitude = "25.70";
    };
  };

  # extra stuff not in programs and/or config files managed manually
  home.packages = with pkgs; [
    # cli/dev utils
    carapace
    bat
    less
    du-dust
    procs
    killall
    bottom
    fd
    tokei
    git-quick-stats
    ripgrep
    xclip
    entr
    file
    jq
    zip
    unzip
    prefetchGithub
    # general helpful stuff
    et
    pass
    safeeyes
    networkmanagerapplet
    # TODO: add yubioath-flutter once it's on nixpkgs stable (yubioath-desktop doesn't work anymore)
    obsidian
    zotero
    # multimedia
    pdftk
    pulsemixer
    moreutils
    ffmpeg
    sxiv
    vlc
    mpv
    pcmanfm
    notify-desktop
    # script/WM dependencies
    maim
    xbindkeys
    xdotool
  ];
  home.file = {
    "awesome" = {
      source = ../awesome;
      target = "./.config/awesome";
    };
    # trackball customization
    "xprofile" = {
      source = ../.xprofile;
      target = "./.xprofile";
    };
    "xbindkeysrc" = {
      source = ../.xbindkeysrc;
      target = "./.xbindkeysrc";
    };
    "ultisnips" = {
      source = ../nvim/snippets;
      target = ".config/nvim/ultisnips";
    };
  };

  xsession = {
    windowManager.awesome.enable = true;
  };
  home.pointerCursor = {
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    x11.enable = true;
  };

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "19.09";
}
