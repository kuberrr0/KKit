# Now Playing

What's playing in any app, in the Island. DESIGN.md §2.2 and §3.5.

- **Does:** while something plays, the compact Island shows its artwork on the left of
  the notch and moving bars on the right (priority normal). The Island page shows the
  artwork, title, artist and album, the app, a scrubber (click or drag to seek) and
  previous / play-pause / next. Paused tracks keep their page but leave the compact
  Island. Clicking the artwork brings the app to the front.
- **Surfaces:** Island activity `nowPlaying`, commands `nowPlaying.playPause`,
  `nowPlaying.next`, `nowPlaying.previous`, `nowPlaying.show`, Settings page with the
  helper's status.
- **APIs:** `NowPlayingService` (`MediaRemoteNowPlayingService`: Apple's private
  MediaRemote framework through KKit's helper library loaded into `/usr/bin/perl`,
  because MediaRemote only answers Apple's processes since macOS 15.4).
- **Permissions:** none.
- **Limits:** depends on a private framework; if macOS stops it working, Settings says
  the source is unavailable and the Island shows nothing. Apps that don't report to
  Control Center's Now Playing don't show.
