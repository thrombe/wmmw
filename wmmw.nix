{ pkgs, ... }:

let
  unstable-overlays = self: super: {
  };
  stable-overlays = self: super: {
  };

  pinnedPkgs = pkgs.fetchFromGitHub {
    owner  = "NixOS";
    repo   = "nixpkgs";
    rev    = "2ab91c8d65c00fd22a441c69bbf1bc9b420d5ea1";
    sha256 = "sha256-wrsPjsIx2767909MPGhSIOmkpGELM9eufqLQOPxmZQg";
  };
  unstablePinned = pkgs.fetchFromGitHub {
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "e7f38be3775bab9659575f192ece011c033655f0";
    sha256 = "sha256-vYGY9bnqEeIncNarDZYhm6KdLKgXMS+HA2mTRaWEc80";
  };
  stable = import pinnedPkgs { overlays = [ stable-overlays ]; };
  unstable = import unstablePinned { overlays = [ unstable-overlays ]; };

  wm = pkgs.stdenv.mkDerivation rec {
  # wm = unstable.rustPlatform.buildRustPackage rec {
    name = "wmmw";
    src = ./.;
    # cargoLock.lockFile = "${src}/Cargo.lock";

    # - [nixpkgs dwm](https://github.com/NixOS/nixpkgs/blob/nixos-23.05/pkgs/applications/window-managers/dwm/default.nix#L34)
    buildInputs = with pkgs; [
      pkg-config
      xorg.libX11
      xorg.libXft
      xorg.xmodmap
      fontconfig
      unstable.rustc

      autoPatchelfHook
    ];

    # - [Rust | nixpkgs](https://ryantm.github.io/nixpkgs/languages-frameworks/rust/)
    # NOTE: buildInputs are runtime dependencies, nativeBuildInputs are compile time deps
    nativeBuildInputs = buildInputs;
    packages = buildInputs;

    # TODO: wrap xmodmap in PATH
    installPhase = ''
      mkdir -p $out/bin
      cp ${src}/target/debug/${name} $out/bin/${name}
      chmod +x $out/bin/${name}
    '';
  };
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Set your time zone.
  # time.timeZone = "Europe/Amsterdam";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkbOptions in tty.
  # };

  environment.pathsToLink = [ "/libexec" ]; # links /libexec from derivations to /run/current-system/sw 
  services.spice-vdagentd.enable = true;
  services.qemuGuest.enable = true;
  services.xserver = {
    enable = true;

    desktopManager = {
      xterm.enable = true;
    };
   
    displayManager = {
        defaultSession = "none+${wm.name}";
        # autoLogin = {
        #   user = "${wm.name}";
        #   enable = true;
        # };
    };

    # qemuGuest.enable = true;
    # - [Adding qemu-guest-agent to a nixos VM](https://discourse.nixos.org/t/adding-qemu-guest-agent-to-a-nixos-vm/5931)
    videoDrivers = [ "qxl" "cirrus" "vmware" "vesa" "modesetting" ];

    windowManager.session = [{
      name = wm.name;
      start = ''
        wm_bin="/mnt/shared/target/debug/${wm.name}"
        wm_log="/mnt/shared/target/log.log"
        wm_prev_log="/mnt/shared/target/prev.log"
        stat=${pkgs.coreutils}/bin/stat

        wm_command() {
          mv "$wm_log" "$wm_prev_log"
          "$wm_bin" &> "$wm_log"
        }

        is_command_running() {
            pgrep -f "$wm_bin" > /dev/null
        }
        
        wm_command

        last_modified=$(stat -c %Y "$wm_bin")

        while true; do
          sleep 1

          if ! is_command_running; then
            wm_command
            continue
          fi

          current_modified=$(stat -c %Y "$wm_bin")

          if [ $last_modified -ne $current_modified ]; then
            echo "restarting"
            pkill "${wm.name}"
            wm_command
            last_modified="$current_modified"
          fi
        done
      '';
    }];
  };  

  virtualisation = {
    virtualbox.guest.enable = true;
    vmware.guest.enable = true;
  };
  virtualisation.vmVariant = {
    # - [nixpkgs/nixos/modules/virtualisation/qemu-vm.nix at nixos-23.05 · NixOS/nixpkgs · GitHub](https://github.com/NixOS/nixpkgs/blob/nixos-23.05/nixos/modules/virtualisation/qemu-vm.nix)
    virtualisation = {
      # qemu.guestAgent.enable = true;
      # virtualisation.vmware.guest.enable = true;
      # virtualisation.virtualbox.guest.enable = true;
      memorySize = 2048;
      cores = 2;
      sharedDirectories = {
        project_dir = {
          source = builtins.toString wm.src;
          target = "/mnt/shared";
        };
      };
    };
  };
  # environment.variables = {
  #   # NOTE: does not work. this env var should be set up in the host. not in the vm :P
  #   # - https://github.com/NixOS/nixpkgs/issues/59219#issuecomment-481571469
  #   # QEMU_OPTS = "-enable-kvm -display sdl";
  #   # QEMU_OPTS = "-enable-kvm -display sdl -virtfs local,path=/home/issac/0Git/wmmw,mount_tag=host0,security_model=passthrough,id=host0";
  # };
  

  # Configure keymap in X11
  services.xserver.layout = "us";

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  services.xserver.libinput.enable = true;

  users.users."${wm.name}" = {
    isNormalUser = true;
    # - [NixOS:nixos-rebuild build-vm](https://nixos.wiki/wiki/NixOS:nixos-rebuild_build-vm)
    initialPassword = "${wm.name}";
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    # packages = with pkgs; [];
  };

  environment.systemPackages = with pkgs; [
    alacritty
    polybarFull
    dmenu-rs
    helix
    git
    rofi
    feh
    zsh
    bluez
    dunst
    picom
    lf
    du-dust
    file
    patchelf
    vim
    wget
    mount

    xorg.xmodmap

    wm
  ];

  system.stateVersion = "23.05";
}

