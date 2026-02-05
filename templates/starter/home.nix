{ config, pkgs, ... }:

{
  home.username = "youruser";
  home.homeDirectory = "/home/youruser";
  home.stateVersion = "24.05";

  # Enable openclaw
  services.openclaw = {
    enable = true;

    # Gateway configuration
    settings = {
      gateway.mode = "local";

      # Telegram channel example
      channels.telegram = {
        enable = true;
        # Bot token comes from secretFiles below
      };

      # Model configuration
      # agent.model = "anthropic/claude-sonnet-4-20250514";
    };

    # Secrets - paths to files containing the secret values
    # Works with agenix, sops-nix, or plain files
    secretFiles = {
      ANTHROPIC_API_KEY = config.age.secrets.anthropic-api-key.path;
      TELEGRAM_BOT_TOKEN = config.age.secrets.telegram-bot-token.path;
    };

    # CLI tools available to skills
    skillPackages = with pkgs; [
      jq
      curl
      ripgrep
    ];

    # Custom skills - markdown files teaching the AI how to use tools
    skills = {
      # example = ./skills/example.md;
    };
  };
}
