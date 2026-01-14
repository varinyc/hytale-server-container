# hytale-server-container
Work In Progress

Downloads hytale-downloader on first run, there is a volume to store credentials so you don't have to download it every time.

Container stores game version for skipping downloads every run for server files.

NOTE: The first run IS interactive for both the downloader and server authentication. Afterwards it will still be interactive if your refresh token expires.
