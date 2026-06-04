# Little Anti-Cheat - SourceTV
This plugin will automatically start recording SourceTV demos upon cheater detections by Little Anti-Cheat.

Little Anti-Cheat: https://github.com/J-Tanzanite/Little-Anti-Cheat

## Configuration:
This plugin will automatically generate a file when loaded, to **cfg/sourcemod/lilac_sourcetv.cfg**\
You can change settings there.

**lilac_stv_enable**: Enables and disables auto recording.\
**lilac_stv_autojoin**: Automatically restart the map if SourceTV bot is missing.\
**lilac_stv_log**: Log to **addons/sourcemod/logs/lilac_stv.log** when players are added & removed from a recording.\
**lilac_stv_tickrate**: Set the SourceTV demo tickrate to the most optimal settings for best quality recordings.

## Build local

```bash
make deps-smx
make build-smx
make package-smx
make release
```

El contenido publicado se describe en [plugin-package-map.json](C:\GitHub\Lilac-SourceTV\plugin-package-map.json) y el flujo completo está documentado en [docs/BUILD_SYSTEM.md](C:\GitHub\Lilac-SourceTV\docs\BUILD_SYSTEM.md).
