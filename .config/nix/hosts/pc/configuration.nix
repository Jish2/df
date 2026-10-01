{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."luks-5fa656db-87e7-4454-9cc7-9d8ce7014ce8".device =
    "/dev/disk/by-uuid/5fa656db-87e7-4454-9cc7-9d8ce7014ce8";
  networking.hostName = "pc";

  networking.networkmanager.enable = true;

  time.timeZone = "America/Los_Angeles";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # NVIDIA proprietary driver (needed for Zotac SPECTRA / OpenRGB I2C)
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;
  hardware.nvidia = {
    modesetting.enable = true;
    # Ampere 3070 Ti: NixOS recommends open kernel modules on Turing+
    open = true;
    nvidiaSettings = true;
  };

  # OpenRGB: udev rules + i2c-dev/i2c-piix4 + SDK server
  services.hardware.openrgb = {
    enable = true;
    motherboard = "amd";
  };

  services.printing.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  users.users."jgoon" = {
    isNormalUser = true;
    description = "Joshua Goon";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    shell = pkgs.zsh;
  };

  # Flatpak (Roblox via Sober, etc.)
  services.flatpak.enable = true;

  programs.firefox.enable = true;

  programs.zsh.enable = true;

  # run the t3 CLI (self-contained binary needing libatomic/libstdc++) and
  # other unpackaged linux binaries without packaging them
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [ stdenv.cc.cc ];
  };

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    git
    yadm
    gh
    openssh
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # SSH — key-only; reach this box over the headscale/tailnet
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Tailscale client → join existing headscale control plane (on mini).
  # After rebuild: sudo tailscale up --login-server=<url> --ssh=false
  # (we use openssh, not Tailscale SSH).
  services.tailscale.enable = true;
  # do not accept the control plane resolver (global nameservers would
  # hijack non-tailnet DNS; see vault note re: VPN DNS conflict)
  services.tailscale.extraSetFlags = [ "--accept-dns=false" ];

  # Keep the machine awake so SSH over the tailnet always works.
  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowHibernation = false;
    AllowHybridSleep = false;
    AllowSuspendThenHibernate = false;
  };

  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    IdleAction = "ignore";
  };

  services.desktopManager.gnome.extraGSettingsOverrides = ''
    [org.gnome.settings-daemon.plugins.power]
    sleep-inactive-ac-type='nothing'
    sleep-inactive-battery-type='nothing'
    power-button-action='nothing'
  '';

  # Allow SSH once on the tailnet; LAN SSH stays closed unless you open it.
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
  };

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "26.05";

}
