# work — Hex voice dictation specifics.
#
# The module (modules/darwin/hex.nix) is fleet-wide and generic; this file is
# the per-machine data it consumes: the cask itself stays in the homebrew list
# in ./default.nix, and the paste-time corrections live here.
#
# Corrections are whole-phrase, case-insensitive swaps merged into Hex's Global
# mode at activation, for words the transcription engine cannot recover from
# vocabulary alone: terms under 5 letters (yadm) and phrases whose spelling is
# too far from the term ("remind cuddle" -> remindctl). Rules added by hand in
# Hex survive a rebuild. Verify with:
#   hex settings get dictation_processing.default_mode
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
  ];
}
