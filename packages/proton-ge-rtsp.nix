# Proton-GE-RTSP — Proton-GE fork with hardware-accelerated video decode
# (h264/RTMP) for in-world video players (VRChat, etc.).
#
# Mirrors nixpkgs proton-ge-bin: prebuilt tarball, compatibilitytool.vdf
# renamed so multiple proton-ge variants can coexist in Steam's compat list.
#
# Why RTSP and not stock proton-ge-bin: stock Proton lacks the h264/RTMP
# path that VRChat/Unity use for YouTube/Twitch/ProTV. Without RTSP, video
# players either show audio-only or crash the game. See:
#   https://github.com/SpookySkeletons/proton-ge-rtsp
#   https://www.protondb.com/app/438100
#
# NOTE: after installing, also run `steam steam://unlockh264/` once while
# Steam is running (see modules/gaming/gaming-vr-unlock.nix). The RTSP video
# path stays disabled until that command is issued.
{
  lib,
  stdenvNoCC,
  fetchzip,
  writeScript,
  # Override to alter the display name shown in Steam's compat dropdown.
  steamDisplayName ? "GE-Proton-RTSP",
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "proton-ge-rtsp";
  version = "proton-rtsp-11.0-20260609-1";

  src = fetchzip {
    url = "https://github.com/SpookySkeletons/proton-ge-rtsp/releases/download/${finalAttrs.version}/${finalAttrs.version}.tar.gz";
    hash = "sha512-3f8/rb8iMIg4bGuywxqlP4IkGOpyZDWUaa03iCrWzaEXqZjONgO9BsM2HUOgcfv81b3LNjzBWXziYw0fq6/oEw==";
    # Upstream tarball internal dir is `proton-rtsp-11.0-20260609-1/`;
    # fetchzip strips the wrapper so $src holds the unpacked tree directly.
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  outputs = [
    "out"
    "steamcompattool"
  ];

  installPhase = ''
    runHook preInstall

    # Make it impossible to add to an environment. Use programs.steam.extraCompatPackages.
    echo "${finalAttrs.pname} should not be installed into environments. Please use programs.steam.extraCompatPackages instead." > $out

    mkdir $steamcompattool
    ln -s $src/* $steamcompattool
    rm $steamcompattool/compatibilitytool.vdf
    cp $src/compatibilitytool.vdf $steamcompattool

    runHook postInstall
  '';

  preFixup = ''
    substituteInPlace "$steamcompattool/compatibilitytool.vdf" \
      --replace-fail "${finalAttrs.version}" "${steamDisplayName}"
  '';

  passthru.updateScript = writeScript "update-proton-ge-rtsp" ''
    #!/usr/bin/env nix-shell
    #!nix-shell -i bash -p curl jq common-updater-scripts
    repo="https://api.github.com/repos/SpookySkeletons/proton-ge-rtsp/releases"
    version="$(curl -sL "$repo" | jq 'map(select(.prerelease == false)) | .[0].tag_name' --raw-output)"
    update-source-version proton-ge-rtsp "$version"
  '';

  meta = {
    description = ''
      Proton-GE fork with hardware-accelerated video decode for Steam Play
      (VRChat in-world video players). Intended for
      `programs.steam.extraCompatPackages` only.
    '';
    homepage = "https://github.com/SpookySkeletons/proton-ge-rtsp";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
