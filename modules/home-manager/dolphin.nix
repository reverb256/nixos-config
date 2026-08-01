{
  config,
  pkgs,
  lib,
  ...
}: let
  # Pull base16 surface color so Dolphin's folder-view background tracks
  # the active stylix scheme (not a stale hardcoded Breeze-Dark value).
  c = config.lib.stylix.colors or { base00 = "#111c18"; base01 = "#1d2b25"; base02 = "#23372b"; base03 = "#3a4f43"; base04 = "#8a9479"; base05 = "#c1c497"; base06 = "#e3e2c4"; base07 = "#f6f5dd"; base08 = "#ff5345"; base0A = "#e5c736"; base0B = "#549e6a"; base0C = "#2dd5b7"; base0D = "#509475"; base0E = "#d2689c"; base0F = "#d7c995"; };
  viewBg = "#" + c.base00;
  viewFg = "#" + c.base05;
  selBg = "#" + c.base0D;
  selFg = "#" + c.base00;
in {
  # ── Force Dolphin's folder-view colors (the unreadable symptom) ──
  # Dolphin reads [Colors:View] from kdeglobals. stylix's kde target writes
  # its kdeglobals into XDG_CONFIG_DIRS, but a stale ~/.config/kdeglobals
  # (April, Breeze-Dark) shadows it. We set the view colors explicitly here
  # AND remove the orphan kdeglobals at activation so stylix wins the merge.
  xdg.configFile."kdeglobals" = {
    # Force: a stale plain ~/.config/kdeglobals (pre-HM-managed, Breeze-Dark)
    # shadows this managed target and makes bare `home-manager switch` fail
    # with "Existing file ... would be clobbered". Force overwrites it so
    # Dolphin's view colors (below) take effect and switch needs no -b flag.
    force = true;
    text = ''
    [Colors:View]
    BackgroundNormal=${viewBg}
    BackgroundAlternate=${viewBg}
    ForegroundNormal=${viewFg}
    ForegroundActive=${selFg}

    [Colors:Selection]
    BackgroundNormal=${selBg}
    ForegroundNormal=${selFg}
  '';
};

  xdg.configFile."dolphinrc" = {
    force = true;
    text = ''
      [General]
      Version=202
      ViewPropsTimestamp=2026,4,17,0,0,0.0

      [IconsPanel]
      Size=22

      [KFileDialog Settings]
      Places Icons Auto-resize=false
      Places Icons Static Size=22

      [MainWindow]
      State=AAAA/wAAAAD9AAAAAAAABdkAAAK3AAAABAAAAAQAAAAIAAAACPwAAAABAAAAAgAAAAEAAAAOAFQAbwBvAGwAYgBhAHIBAAAAAP////8AAAAAAAAAAAAAABdkAAAK3AAAAAEAAAACAAAAAAAABdkAAAAA/AAAAAIAAAACAAAAAQAAABYAQQBjAHQAaQBvAG4AcwAAAACsAAAAAQAAAAAAAAAAAAAABdkAAAAAIAAAAP////8AAAAAAAAAAAAAABdkAAAAA

      [NavigatedWithTabs]
      12345678=false

      [PrimaryDialogView]
      ColumnWidth=250
      ColumnWidth=100
      ColumnWidth=100
      ColumnWidth=100
      ColumnWidth=100
      ColumnWidth=100
      ColumnWidth=100
      ColumnWidth=100
      ColumnWidth=100
      ColumnWidth=100
      ColumnWidth=100
      ColumnWidth=100
      DetailsModeExpanded=false
      DetailsModeScrollToNewItems=false
      HeaderWidth=250
      HeaderWidth=100
      HeaderWidth=100
      HeaderWidth=100
      HeaderWidth=100
      HeaderWidth=100
      HeaderWidth=100
      HeaderWidth=100
      HeaderWidth=100
      HeaderWidth=100
      HeaderWidth=100
      HeaderWidth=100
      Padding=4
      PreviewSize=22
      SortColumn=0
      SortOrder=0
      SortRole=0
      ViewMode=1
      VisibleRoles=CustomizedDetailsRole=0;CustomizedDetailsRole=1;CustomizedDetailsRole=2;CustomizedDetailsRole=3;CustomizedDetailsRole=4;CustomizedDetailsRole=5;CustomizedDetailsRole=6;CustomizedDetailsRole=7;CustomizedDetailsRole=8;CustomizedDetailsRole=9;CustomizedDetailsRole=10;CustomizedDetailsRole=11

      [Settings]
      AddedExtensions=
      ConfirmEmptyTrash=true
      ConfirmTrashDelete=true
      ContextMenu=v1
      CopyToGlobalContextMenu=false
      CreateTemplateBigThumb=true
      CreateTemplateThumbText=false
      EditableUrl=false
      GlobalUrlBar=false
      OpenArchivesInplace=false
      RenameInlineAdaptiveToSelection=false
      ShowCopyToOtherPlacesContextMenu=true
      ShowDeleteCommand=false
      ShowPasteToOtherPlacesContextMenu=true
      ShowSpaceInfo=false
      ShowFullPathInTitlebar=false
      ViewStartPage=home

      [SettingsDialog]
      PreferredSearchTool=0
      ShowToolTip=true
      UseGroupedSorting=false
      UseRelativeDateTime=true

      [Search]
      SearchLocation=Everywhere

      [DetailsMode]
      ExpandableFolders=true
      HoveredExpandRegion=0
      UseCompactMode=false

      [CompactMode]
      PreviewSize=22

      [ViewPropertiesDialog]
      UseCommonDirProperties=false
      ViewMode=0

      [MainWindow][Toolbar mainToolBar]
      IconSize=22
      Position=Top
      ToolButtonStyle=IconOnly

      [MainWindow][Toolbar editToolbar]
      IconSize=22
      Position=Top
      ToolButtonStyle=IconOnly

      [PreviewSettings]
      MaximumRemoteSize=5
      Plugins=directorythumbnail,fontthumbnail,imagethumbnail,jpegthumbnail,svgthumbnail,windowsexecutablethumbnail,ffmpegthumbnailer
      RemoteThumbnail=true

      [SortSettings]
      CaseSensitive=false
      FoldersFirst=true
      HiddenFirst=false
      SortDirectoriesFirst=true
      SortHiddenLast=false
      VersionSorting=false
    '';
  };
}
