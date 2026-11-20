# work — Hex voice dictation specifics.
#
# The module (modules/darwin/hex.nix) is fleet-wide and generic; this file is
# the per-machine data it consumes: the cask itself stays in the homebrew list
# in ./default.nix, and the paste-time corrections live here.
#
# Corrections are whole-phrase, case-insensitive swaps merged into Hex's Global
# mode at activation; rules added by hand in Hex survive a rebuild. Verify with:
#   hex settings get dictation_processing.default_mode
#
# Almost everything belongs in the vocabulary first: a `sounds_like` spelling
# returns rank 0.0 before any length check, so short terms work once the miss is
# spelled out. `rank_of()`'s 5-letter floor and 2x length ratio govern only the
# fuzzy path. Keep this list for joins and splits where word-boundary matching
# defeats the vocabulary path.
{
  fleet.hex.enable = true;

  fleet.hex.corrections = [
    { matched_phrase = "remind cuddle"; output = "remindctl"; }
    { matched_phrase = "remind ctl"; output = "remindctl"; }
    { matched_phrase = "remind cuttle"; output = "remindctl"; }
    { matched_phrase = "yeah dum"; output = "yadm"; }
    { matched_phrase = "yad m"; output = "yadm"; }
    { matched_phrase = "yadam"; output = "yadm"; }
    # David Lu (not Liu): Parakeet hears the name as "liu"/"lou" and the
    # vocabulary term alone does not always win, so pin the swap too.
    { matched_phrase = "david liu"; output = "David Lu"; }
    { matched_phrase = "david lou"; output = "David Lu"; }
    { matched_phrase = "david loo"; output = "David Lu"; }
    { matched_phrase = "david l u"; output = "David Lu"; }
    { matched_phrase = "david lue"; output = "David Lu"; }
    # jgoon: heard as "jagoon". Also a vocabulary term with that spelling; the
    # swap is what actually guarantees the paste.
    { matched_phrase = "jagoon"; output = "jgoon"; }
    # Observed join (id 289): "Venmoselle" for "Venmo Zelle".
    { matched_phrase = "venmoselle"; output = "Venmo Zelle"; }
    # Observed (id 447): "NT3 code" for "T3 code".
    { matched_phrase = "nt3 code"; output = "T3 code"; }
  ];
}
