# Zen Media Artwork

Zen Media Artwork adds album artwork to the native sidebar media controller. It reads the artwork supplied by the page through the Media Session API, updates when the track changes, and leaves the native card unchanged when no artwork is available.

The behavior uses a privileged userChrome script because a regular web extension cannot access Zen's browser-chrome media controller.

The mod does not add DRM support. Spotify artwork appears only when Spotify can play successfully and provides Media Session artwork to Zen.
