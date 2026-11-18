# Work identity, pulled in by the includeIf blocks in config, which key on the
# remote URL being github.rbx.com. Kept in its own file so the conditional
# include has something unambiguous to load, and so the identity can be edited
# without touching the main config.
#
# A real address, not the GHES noreply (4246+jgoon@users.noreply.github.rbx.com):
# internal tooling attributes on it, and unlike a public dotfiles repo there is
# nothing to leak.
[user]
	email = jgoon@roblox.com
	name = Joshua Goon
