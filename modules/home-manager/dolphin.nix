{ config, pkgs, lib, ... }:
let
    # Pull base16 surface color so Dolphin's folder-view background tracks
    # the active stylix scheme (not a stale hardcoded Breeze-Dark value).
    c = config.lib.stylix.colors;
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
    xdg.configFile."kdeglobals".text = ''
      [Colors:View]
      BackgroundNormal=${viewBg}
      BackgroundAlternate=${viewBg}
      ForegroundNormal=${viewFg}
      ForegroundActive=${selFg}

      [Colors:Selection]
      BackgroundNormal=${selBg}
      ForegroundNormal=${selFg}
    '';

    # Remove the stale orphan kdeglobals so it cannot shadow stylix's generated
    # copy (stylix writes its kdeglobals into XDG_CONFIG_DIRS; the per-user file
    # in ~/.config takes merge precedence and was frozen on Breeze-Dark).
    home.activation.removeStaleKdeglobals = ''
      if [ -f "$HOME/.config/kdeglobals" ]; then
        rm -f "$HOME/.config/kdeglobals"
      fi
    '';

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
