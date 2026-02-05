# Shared library functions for openclaw.nix
{ lib }:

{
  # Helper to resolve ~ paths
  resolvePath =
    homeDir: path:
    if lib.hasPrefix "~/" path then
      "${homeDir}/${lib.removePrefix "~/" path}"
    else if lib.hasPrefix "~" path then
      "${homeDir}${lib.removePrefix "~" path}"
    else
      path;

  # Convert absolute path to relative (for home.file)
  toRelative =
    homeDir: path:
    if lib.hasPrefix "${homeDir}/" path then lib.removePrefix "${homeDir}/" path else path;

  # Merge skill packages from multiple sources
  mergeSkillPackages = packageLists: lib.unique (lib.flatten packageLists);
}
