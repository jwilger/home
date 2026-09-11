{
  config,
  jwilgerInputs,
  pkgs,
  lib,
  ...
}:
let
  unstableSmallPkgs = jwilgerInputs.nixpkgs-small.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  # Conservative ad-hoc-editor toolset only. Project-specific toolchains
  # and LSPs (rust-analyzer, gopls, elixir-ls, haskell-language-server,
  # terraform-ls, texlab, typescript-language-server, zls, etc.) and the
  # corresponding compilers (go, ruby, elixir, terraform, cargo) come
  # from each project's flake.nix via direnv. nodejs and a small Python
  # runtime live globally because agent hooks and skill validators shell
  # out to them.
  agentPython = pkgs.python312.withPackages (
    python-pkgs: with python-pkgs; [
      pyyaml
    ]
  );
  helixTooling = with pkgs; [
    awk-language-server
    bash-language-server
    basedpyright
    black
    clang-tools
    cmake-format
    docker-compose-language-service
    dockerfile-language-server
    graphql-language-service-cli
    jq-lsp
    lua-language-server
    markdown-oxide
    neocmakelsp
    nixfmt
    prettier
    shfmt
    socat
    sql-formatter
    sqls
    stylua
    taplo
    vscode-langservers-extracted
    yaml-language-server
    yamlfmt
  ];
  helixToolingLinux = with pkgs; [
    # macOS uses Homebrew for these tools
    lldb
    marksman
  ];
in
{
  home.packages =
    (
      with pkgs;
      [
        # Cross-platform packages.
        # Toolchains (cargo, etc.) intentionally dropped: they live in
        # per-project flake.nix files and are activated by direnv. For
        # one-off scripts use `nix run nixpkgs#<pkg> -- ...`.
        # nodejs + agentPython stay global — Claude Code/Codex hooks and
        # skill validators need them.
        _1password-cli
        agentPython
        man-pages
        cbonsai # terminal screensaver
        cmatrix
        curl
        delta
        entr # perform action when file change
        eza # ls replacement
        fd # find replacement
        ffmpeg
        file # Show file information
        fzf # fuzzy finder
        gh
        git-crypt
        glab
        glow
        gnumake
        jq # JSON processor
        ncdu # disk space
        nil
        nix-prefetch-github
        nodejs_22 # Claude Code hooks
        openssl
        ripgrep
        rtk # reduce token use by llm cli tools
        statix
        tdf # cli pdf viewer
        tree
        unzip
        uv
        yq-go
        zip
      ]
      # Linux-only packages
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        bc # calculator for audio processing
        bubblewrap
        codeql
        cliphist # clipboard manager (Wayland)
        dwt1-shell-color-scripts
        gcc
        gparted # partition manager
        gtrash # rm replacement, put deleted files in system trash
        libnotify
        nerd-fonts.jetbrains-mono
        nerd-fonts.noto
        nitch # systhem fetch util
        pamixer # command-line audio mixer
        unstableSmallPkgs.pipx # Python package installer for Piper TTS
        pre-commit
        poweralertd
        pulseaudio # provides paplay for audio playback
        sox # audio effects processing
        twemoji-color-font
        wl-clipboard # clipboard utils for wayland (wl-copy, wl-paste)
        wlogout
        xdg-utils
      ]
      ++ lib.optionals (config.jwilger.hostProfile == "gregor") [
        telegram-desktop
      ]
    )
    ++ helixTooling
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux helixToolingLinux;
}
