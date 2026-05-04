{lib, ...}: {
  xdg.dataFile = {
    "applications/tui-lazydocker.desktop".text = ''
      [Desktop Entry]
      Version=1.0
      Name=LazyDocker
      Comment=Terminal UI for Docker
      Exec=alacritty -e lazydocker
      Icon=docker
      Terminal=false
      Type=Application
      Categories=System;ConsoleOnly;Docker;
    '';

    "applications/tui-btop.desktop".text = ''
      [Desktop Entry]
      Version=1.0
      Name=btop
      Comment=System monitor
      Exec=alacritty -e btop
      Icon=utilities-system-monitor
      Terminal=false
      Type=Application
      Categories=System;ConsoleOnly;
    '';

    "applications/tui-lazygit.desktop".text = ''
      [Desktop Entry]
      Version=1.0
      Name=LazyGit
      Comment=Terminal UI for Git
      Exec=alacritty -e lazygit
      Icon=git
      Terminal=false
      Type=Application
      Categories=Development;ConsoleOnly;
    '';

    "applications/tui-dust.desktop".text = ''
      [Desktop Entry]
      Version=1.0
      Name=Disk Usage
      Comment=Disk usage analyzer
      Exec=alacritty -e dust
      Icon=folder
      Terminal=false
      Type=Application
      Categories=System;ConsoleOnly;
    '';
  };
}
