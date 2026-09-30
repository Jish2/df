# df — fleet config (5 machines; mini is remote — SSH breakage = physical visit)

Before switching any machine, or touching tailscale, sshd, or brew services
anywhere in the fleet, read `.config/nix/FLEET.md`: hard rules + the
remote-switch protocol live there. Switches go through `.config/nix/Makefile`
(`make here` only); `make doctor` verifies the invariants.
