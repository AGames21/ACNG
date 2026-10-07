-- Lab only. Never include in the player mod.
if FS:fileExists('/acng-lap-restart-expect.json') then
  extensions.load('acng_laprestart')
else
  extensions.load('acng_laparchive')
end
