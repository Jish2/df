# Remote Login (sshd) and Screen Sharing, declared on. Adopted from mini's
# live state 2026-10-20 — the services, the ssh access list and the
# com.apple.RemoteManagement prefs as they were, nothing tightened.
#
# One-way by design: activation only ever turns a service ON or ADDS an
# access-list member; nothing here can switch sshd off or lock a user out
# (fleet-ssh-safety hard rule 3). Not services.openssh.enable — its
# activation keys off `systemsetup -getremotelogin`, which needs Full Disk
# Access and silently no-ops without it; `launchctl print` needs neither.
#
# sshd_config stays stock: nix-darwin already owns sshd_config.d/099-101
# (host keys, empty extraConfig, AuthorizedKeysCommand) and nothing is
# added to them. Not declared, by hand:
#   authorized_keys       — imperative, see modules/home/ssh-aliases.nix
#   VNC password          — /Library/Preferences/com.apple.VNCSettings.txt is
#                           a secret (System Settings → Sharing → Screen
#                           Sharing → "VNC viewers may control screen…")
#   Screen Sharing ACL    — all users (com.apple.access_screensharing-disabled)
{
  config,
  lib,
  ...
}:
let
  cfg = config.fleet.remoteAccess;

  ensureLoaded = label: plist: ''
    if ! launchctl print system/${label} >/dev/null 2>&1; then
      echo "remote-access: loading ${label}" >&2
      launchctl enable system/${label}
      launchctl bootstrap system ${plist} \
        || echo "remote-access: !! could not load ${label} — enable it in System Settings → Sharing" >&2
    fi
  '';

  addSshUser = u: ''
    if ! dseditgroup -o checkmember -m ${u} com.apple.access_ssh >/dev/null 2>&1; then
      dseditgroup -o edit -a ${u} -t user com.apple.access_ssh
    fi
  '';
in
{
  options.fleet.remoteAccess = {
    enable = lib.mkEnableOption "Remote Login and Screen Sharing, kept on";

    sshAllowUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Users added to Remote Login's "Only these users" list
        (com.apple.access_ssh) alongside Administrators. Only applies when
        that list exists — with "All users" there is nothing to add to, and
        creating the list would narrow access.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    system.activationScripts.postActivation.text = ''
      ${ensureLoaded "com.openssh.sshd" "/System/Library/LaunchDaemons/ssh.plist"}
      ${ensureLoaded "com.apple.screensharing" "/System/Library/LaunchDaemons/com.apple.screensharing.plist"}

      if dscl . -read /Groups/com.apple.access_ssh >/dev/null 2>&1; then
        adminGuid=$(dscl . -read /Groups/admin GeneratedUID | awk '{print $2}')
        if ! dscl . -read /Groups/com.apple.access_ssh NestedGroups 2>/dev/null | grep -q "$adminGuid"; then
          dseditgroup -o edit -a admin -t group com.apple.access_ssh
        fi
        ${lib.concatMapStrings addSshUser cfg.sshAllowUsers}
      fi
    '';

    # full path: CustomSystemPreferences passes the domain to `defaults
    # write` verbatim, and a bare name would land in root's home
    system.defaults.CustomSystemPreferences."/Library/Preferences/com.apple.RemoteManagement" = {
      VNCLegacyConnectionsEnabled = true; # VNC viewers may control screen with password
      ScreenSharingReqPermEnabled = true; # anyone may request permission to control screen
      allowInsecureDH = true; # older VNC clients' key exchange
      AllowSRPForNetworkNodes = false;
      DisableKerberos = false;
      LoadRemoteManagementMenuExtra = true;
      # Remote Management (ARD) is off; these only matter if it comes back
      ARD_AllLocalUsers = false;
      ARD_AllLocalUsersPrivs = 255;
    };
  };
}
