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

    buildInputs = with pkgs; [
      # - [nixpkgs dwm](https://github.com/NixOS/nixpkgs/blob/nixos-23.05/pkgs/applications/window-managers/dwm/default.nix#L34)
      xorg.libX11
      xorg.libXft
      xorg.xmodmap
      fontconfig


      # donno if necessary
      xorg.libXinerama
      xorg.libXi
      xorg.libXrandr
      xorg.libXcursor
      gcc
      libgccjit
      pkg-config
      unstable.cargo
      unstable.rustc
      # unstable.clippy
      glibc

      autoPatchelfHook
    ];

    # - [Rust | nixpkgs](https://ryantm.github.io/nixpkgs/languages-frameworks/rust/)
    # NOTE: buildInputs are runtime dependencies, nativeBuildInputs are compile time deps
    nativeBuildInputs = buildInputs;
    packages = buildInputs;

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

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

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
        defaultSession = "none+wmmw";
        # autoLogin = {
        #   user = "issac";
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

        # # Monitor the file for changes
        # while true; do
        #     ${pkgs.inotify-tools}/bin/inotifywait -e modify "$file_to_monitor"
        #     echo "Detected a change in $file_to_monitor"
    
        #     # Restart the command when a change is detected
        #     restart_command
        # done
      
        # while true; do
        #   # log out to a file
        #   /mnt/shared/target/debug/${wm.name} &> ~/.penrose.log
        #   # ${wm}/bin/${wm.name} &> ~/.penrose.log
        #   [[ $? > 0 ]] && mv ~/.penrose.log ~/prev-penrose.log
        #   export RESTARTED=true
        # done

        # ${wm}/bin/${wm.name} &
        # /mnt/shared/target/debug/${wm.name} &
        # waitPID=$!
      '';
    }];
  };  
  # systemd.services.mount-directory = {
  #   enable = true;
  #   description = "Mount shared directory in QEMU VM";
  #   wantedBy = ["default.target"];
  #   wants = [ "network.target" ];
  #   # after = [ "network.target" "qemu-guest-agent.service" "graphical.target" "display-manager.service" ];
  #   after = [ "network.target" ];
  #   # requires = [ "graphical.target" "display-manager.service" ];
  #   # before = [ "your-window-manager.service" ]; # Replace with your window manager's service name

  #   # preStart = ''
  #   #   ${pkgs.coreutils}/bin/sleep 10
  #   # '';
  #   script = ''
  #     #!/bin/sh

  #     echo "YOYOYOYOYOYOYOYOYOYOYOYOYYYOYOYOYO"

  #     mkdir -p /mnt/shared
  #     ${pkgs.mount}/bin/mount -t 9p -o trans=virtio,version=9p2000.L host0 /mnt/shared      

  #     # command="${pkgs.mount}/bin/mount -t 9p -o trans=virtio,version=9p2000.L host0 /mnt/shared"

  #     # # Mount the shared directory in the VM
  #     # while true; do
  #     #   output="$($command 2>&1)"
  #     #   exit_status=$?

  #     #   if [ $exit_status -eq 0 ]; then
  #     #       echo "Command executed successfully."
  #     #       break  # Exit the loop
  #     #   else
  #     #       echo "Command failed with exit status $exit_status. Retrying in 5 seconds..."
  #     #       echo "Error message: $output"
  #     #       echo "Command failed. Retrying in 5 seconds..."
  #     #       ${pkgs.coreutils}/bin/sleep 5
  #     #   fi
  #     # done
  #   '';

  #   # environment.SYSTEMD_LOG_LEVEL = "debug"; # Optional for debugging
  # };

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
        shared_wm = {
          source = "/home/issac/0Git/wmmw";
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
  # services.xserver.layout = "us";
  # services.xserver.xkbOptions = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.issac = {
    isNormalUser = true;
    # - [NixOS:nixos-rebuild build-vm](https://nixos.wiki/wiki/NixOS:nixos-rebuild_build-vm)
    initialPassword = "mypeasblue";
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
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
      llvmPackages_15.libcxxClang
      gcc
      libgccjit
      pkg-config
      unstable.cargo
      unstable.rustc
      glibc
      xorg.xmodmap
    ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
    wget
    mount
    inotify-tools
    
     wm
  ];

  system.stateVersion = "23.05";
}

