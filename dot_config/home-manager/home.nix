{ config, lib, pkgs, ... }:

let
  codexAgentCliTools = [
    (pkgs.writeShellScriptBin "linearx" ''
      set -euo pipefail

      api_url="''${LINEAR_API_URL:-https://api.linear.app/graphql}"
      api_key="''${LINEAR_API_KEY:-}"

      usage() {
        cat <<'EOF'
linearx - Linear GraphQL CLI for Codex skills

Usage:
  linearx auth status
  linearx viewer
  linearx query '<graphql>' ['<variables-json>']
  linearx issue <identifier-or-id>
  linearx search <text> [limit]
  linearx team <team-key>
  linearx create <team-id> <title> [description]

Environment:
  LINEAR_API_KEY  Linear personal API key
EOF
      }

      require_key() {
        if [ -z "$api_key" ]; then
          echo "LINEAR_API_KEY is not set" >&2
          exit 2
        fi
      }

      gql() {
        require_key
        query="$1"
        vars="''${2:-{}}"
        ${pkgs.jq}/bin/jq -nc --arg query "$query" --argjson variables "$vars" \
          '{query:$query, variables:$variables}' |
          ${pkgs.curl}/bin/curl -fsS "$api_url" \
            -H "Authorization: $api_key" \
            -H "Content-Type: application/json" \
            --data-binary @-
      }

      cmd="''${1:-}"
      case "$cmd" in
        -h|--help|help|"")
          usage
          ;;
        auth)
          sub="''${2:-}"
          if [ "$sub" = "status" ]; then
            if [ -n "$api_key" ]; then
              echo '{"ok":true,"auth":"LINEAR_API_KEY"}'
            else
              echo '{"ok":false,"missing":"LINEAR_API_KEY"}'
              exit 2
            fi
          else
            usage
            exit 2
          fi
          ;;
        viewer)
          gql 'query { viewer { id name email } }'
          ;;
        query)
          shift
          gql "$1" "''${2:-{}}"
          ;;
        issue)
          id="''${2:?issue identifier or id required}"
          gql 'query($id:String!) { issues(filter:{or:[{identifier:{eq:$id}},{id:{eq:$id}}]}, first:1) { nodes { id identifier title description url state { name } assignee { name email } team { key name } labels { nodes { name } } } } }' \
            "$(${pkgs.jq}/bin/jq -nc --arg id "$id" '{id:$id}')"
          ;;
        search)
          text="''${2:?search text required}"
          limit="''${3:-20}"
          gql 'query($text:String!, $limit:Int!) { issues(filter:{or:[{title:{containsIgnoreCase:$text}},{description:{containsIgnoreCase:$text}}]}, first:$limit) { nodes { id identifier title url state { name } team { key name } assignee { name email } } } }' \
            "$(${pkgs.jq}/bin/jq -nc --arg text "$text" --argjson limit "$limit" '{text:$text,limit:$limit}')"
          ;;
        team)
          key="''${2:?team key required}"
          gql 'query($key:String!) { teams(filter:{key:{eq:$key}}, first:1) { nodes { id key name } } }' \
            "$(${pkgs.jq}/bin/jq -nc --arg key "$key" '{key:$key}')"
          ;;
        create)
          team_id="''${2:?team id required}"
          title="''${3:?title required}"
          description="''${4:-}"
          gql 'mutation($teamId:String!, $title:String!, $description:String) { issueCreate(input:{teamId:$teamId,title:$title,description:$description}) { success issue { id identifier title url } } }' \
            "$(${pkgs.jq}/bin/jq -nc --arg teamId "$team_id" --arg title "$title" --arg description "$description" '{teamId:$teamId,title:$title,description:$description}')"
          ;;
        *)
          usage
          exit 2
          ;;
      esac
    '')

    (pkgs.writeShellScriptBin "ntn" ''
      set -euo pipefail
      exec ${pkgs.nodejs}/bin/npm exec --yes ntn@0.17.0 -- "$@"
    '')

    (pkgs.writeShellScriptBin "ddx" ''
      set -euo pipefail

      site="''${DD_SITE:-datadoghq.com}"
      api_key="''${DD_API_KEY:-}"
      app_key="''${DD_APP_KEY:-}"
      base="https://api.$site"

      usage() {
        cat <<'EOF'
ddx - Datadog HTTP API CLI for Codex skills

Usage:
  ddx auth status
  ddx logs search <query> [from] [to] [limit]
  ddx spans search <query> [from] [to] [limit]
  ddx api <METHOD> <PATH> [json-body]

Environment:
  DD_API_KEY
  DD_APP_KEY
  DD_SITE      default: datadoghq.com
EOF
      }

      require_keys() {
        if [ -z "$api_key" ] || [ -z "$app_key" ]; then
          echo "DD_API_KEY and DD_APP_KEY are required" >&2
          exit 2
        fi
      }

      request() {
        require_keys
        method="$1"
        path="$2"
        body="''${3:-}"
        if [ -n "$body" ]; then
          ${pkgs.curl}/bin/curl -fsS -X "$method" "$base$path" \
            -H "DD-API-KEY: $api_key" \
            -H "DD-APPLICATION-KEY: $app_key" \
            -H "Content-Type: application/json" \
            --data-binary "$body"
        else
          ${pkgs.curl}/bin/curl -fsS -X "$method" "$base$path" \
            -H "DD-API-KEY: $api_key" \
            -H "DD-APPLICATION-KEY: $app_key"
        fi
      }

      cmd="''${1:-}"
      case "$cmd" in
        -h|--help|help|"")
          usage
          ;;
        auth)
          if [ "''${2:-}" = "status" ]; then
            if [ -n "$api_key" ] && [ -n "$app_key" ]; then
              echo '{"ok":true,"auth":"DD_API_KEY/DD_APP_KEY"}'
            else
              echo '{"ok":false,"missing":"DD_API_KEY or DD_APP_KEY"}'
              exit 2
            fi
          else
            usage
            exit 2
          fi
          ;;
        logs)
          [ "''${2:-}" = "search" ] || { usage; exit 2; }
          query="''${3:?query required}"
          from="''${4:-now-15m}"
          to="''${5:-now}"
          limit="''${6:-20}"
          body="$(${pkgs.jq}/bin/jq -nc --arg query "$query" --arg from "$from" --arg to "$to" --argjson limit "$limit" \
            '{filter:{query:$query,from:$from,to:$to},page:{limit:$limit},sort:"-timestamp"}')"
          request POST "/api/v2/logs/events/search" "$body"
          ;;
        spans)
          [ "''${2:-}" = "search" ] || { usage; exit 2; }
          query="''${3:?query required}"
          from="''${4:-now-15m}"
          to="''${5:-now}"
          limit="''${6:-20}"
          body="$(${pkgs.jq}/bin/jq -nc --arg query "$query" --arg from "$from" --arg to "$to" --argjson limit "$limit" \
            '{filter:{query:$query,from:$from,to:$to},page:{limit:$limit},sort:"-timestamp"}')"
          request POST "/api/v2/spans/events/search" "$body"
          ;;
        api)
          shift
          request "$1" "$2" "''${3:-}"
          ;;
        *)
          usage
          exit 2
          ;;
      esac
    '')

    (pkgs.writeShellScriptBin "context7x" ''
      set -euo pipefail

      usage() {
        cat <<'EOF'
context7x - Context7 HTTP CLI for Codex skills

Usage:
  context7x search <query>
  context7x docs <library-id> [topic] [tokens]

Examples:
  context7x search react
  context7x docs /reactjs/react.dev useState 2000
EOF
      }

      cmd="''${1:-}"
      case "$cmd" in
        -h|--help|help|"")
          usage
          ;;
        search)
          query="''${2:?query required}"
          ${pkgs.curl}/bin/curl -fsS --get "https://context7.com/api/v1/search" --data-urlencode "query=$query"
          ;;
        docs)
          library="''${2:?library id required}"
          topic="''${3:-}"
          tokens="''${4:-5000}"
          library="''${library#/}"
          url="https://context7.com/api/v1/$library?tokens=$tokens"
          if [ -n "$topic" ]; then
            ${pkgs.curl}/bin/curl -fsS --get "$url" --data-urlencode "topic=$topic"
          else
            ${pkgs.curl}/bin/curl -fsS "$url"
          fi
          ;;
        *)
          usage
          exit 2
          ;;
      esac
    '')

    (pkgs.writeShellScriptBin "chromex" ''
      set -euo pipefail

      base="''${CHROME_DEBUG_URL:-http://127.0.0.1:9222}"

      usage() {
        cat <<'EOF'
chromex - Chrome DevTools Protocol HTTP helper for Codex skills

Usage:
  chromex version
  chromex tabs
  chromex open <url>
  chromex activate <target-id>
  chromex close <target-id>

Environment:
  CHROME_DEBUG_URL  default: http://127.0.0.1:9222
EOF
      }

      cmd="''${1:-}"
      case "$cmd" in
        -h|--help|help|"")
          usage
          ;;
        version)
          ${pkgs.curl}/bin/curl -fsS "$base/json/version"
          ;;
        tabs)
          ${pkgs.curl}/bin/curl -fsS "$base/json/list"
          ;;
        open)
          url="''${2:?url required}"
          ${pkgs.curl}/bin/curl -fsS -X PUT "$base/json/new?$url"
          ;;
        activate)
          id="''${2:?target id required}"
          ${pkgs.curl}/bin/curl -fsS "$base/json/activate/$id"
          ;;
        close)
          id="''${2:?target id required}"
          ${pkgs.curl}/bin/curl -fsS "$base/json/close/$id"
          ;;
        *)
          usage
          exit 2
          ;;
      esac
    '')

    (pkgs.writeShellScriptBin "memolix" ''
      set -euo pipefail

      if [ "''${1:-}" = "serve" ]; then
        echo "memolix intentionally does not expose the memoli MCP server. Use memoli CLI subcommands instead." >&2
        exit 2
      fi

      exec memoli "$@"
    '')
  ];
in

{
  home.username = "fujitanisora";
  home.homeDirectory = "/Users/fujitanisora";
  home.stateVersion = "24.11";

  programs.home-manager.enable = true;

  programs.lazygit = {
    enable = true;
    settings = {
      activeBorderColor = [ "cyan" "bold" ];
      inactiveBorderColor = [ "default" ];
      searchingActiveBorderColor = [ "cyan" "bold" ];
      optionsTextColor = [ "blue" ];
      selectedLineBgColor = [ "reverse" ];
      inactiveViewSelectedLineBgColor = [ "default" ];
      cherryPickedCommitFgColor = [ "blue" ];
      cherryPickedCommitBgColor = [ "cyan" ];
      markedBaseCommitFgColor = [ "blue" ];
      markedBaseCommitBgColor = [ "yellow" ];
      unstagedChangesColor = [ "red" ];
      defaultFgColor = [ "default" ];
      gui = {
        nerdFontsVersion = "3";
      };
      customCommands = [
        {
          key = "<c-g>";
          context = "files";
          output = "terminal";
          command = ''
            MSG=$(git diff --cached | claude --no-session-persistence --print --model haiku \
              'Generate ONLY a one-line Git commit message following Conventional Commits format \
              (type(scope): description). Types: feat, fix, docs, style, refactor, test, chore. \
              Based strictly on the diff from stdin. Output ONLY the message, nothing else.') \
              && git commit -e -m "$MSG"
          '';
        }
      ];
    };
  };

  # batch 3: programs.* lightweight tools
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.bat.enable = true;

  programs.zoxide.enable = true;

  # batch 4: programs.* with config
  programs.git = {
    enable = true;
    lfs.enable = true;
    settings = {
      user.name = "fujitani sora";
      user.email = "fujitanisora0414@gmail.com";
      ghq.root = [ "~/ghq" ];
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    config.global.hide_env_diff = true;
    config.global.log_format = "";
    # ghq 配下を一律 whitelist (direnv allow 不要 / unloading ログ抑制は log_format で)
    config.whitelist.prefix = [
      "/Users/fujitanisora/ghq"
      "/Users/fujitanisora/.config"
    ];
  };

  programs.gh = {
    enable = true;
    settings = {
      version = 1;
      git_protocol = "https";
      prompt = "enabled";
    };
  };

  programs.htop = {
    enable = true;
    settings = {
      hide_kernel_threads = 1;
      highlight_megabytes = 1;
      tree_view = 0;
    };
  };

  home.activation.installCodexCliSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -euo pipefail

    install_skill() {
      name="$1"
      source="$2"
      target="$HOME/.agents/skills/$name/SKILL.md"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$HOME/.agents/skills/$name"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$target"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 "$source" "$target"
    }

    install_skill datadog-cli ${./skills/datadog-cli/SKILL.md}
    install_skill notion-cli ${./skills/notion-cli/SKILL.md}
    install_skill context7-cli ${./skills/context7-cli/SKILL.md}
    install_skill chrome-cli ${./skills/chrome-cli/SKILL.md}
    install_skill memoli-cli ${./skills/memoli-cli/SKILL.md}
    install_skill linear ${./skills/linear-cli/SKILL.md}
  '';

  home.packages = (with pkgs; [
    nodejs
    uv
    # batch 1: simple CLI tools
    ripgrep
    fd
    jq
    peco
    ghq
    lazydocker
    ast-grep
    mkcert
    tree-sitter
    # batch 2: GNU tools
    coreutils
    gawk
    gnused
    gnugrep
    # batch 5: neovim + language servers + sheldon
    neovim
    lua-language-server
    markdown-oxide
    sheldon
    # batch 6: media/build tools
    imagemagick
    ffmpeg
    cmake
    # batch 7: misc tools
    goreleaser
    go-task
    usage
    # additional migrations
    awscli2
    tmux
    luarocks
    curl
    libyaml
    _1password-cli
  ]) ++ codexAgentCliTools ++ [
    (pkgs.writeShellScriptBin "hereby" ''
      exec npx --yes hereby "$@"
    '')
  ];
}
