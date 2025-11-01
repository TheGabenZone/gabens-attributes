# Gaben's Custom Attributes for TF2 Classic

A collection of custom weapon attributes for Team Fortress 2 Classic, created by me, TheGabenZone!

## Overview

This repository contains some custom attributes that expand weapon customization possibilities in TF2 Classic. Each attribute is implemented as a separate plugin.

### Requirements
- Team Fortress 2 Classic Linux Server (Ubuntu 24.04 LTS)
- SourceMod 1.10 or newer
- [KOCWTools](https://github.com/Reagy/TF2Classic-KO-Custom-Weapons/blob/main/assets_sourcemod/source%20code/kocwtools.sp) plugin file
- [HUDFramework](https://github.com/Reagy/TF2Classic-KO-Custom-Weapons/blob/main/assets_sourcemod/source%20code/hudframework.sp) plugin file
- [TF2CTools](https://github.com/tf2classic/SM-TF2Classic-Tools/releases/tag/tf2ctools-2.2.0) plugin file  

### Server Installation

1. **Download the compiled plugins** (`.smx` files) from the releases page or compile from source

2. **Copy plugin files** to your server:
   ```
   addons/sourcemod/plugins/
   ```

3. **Copy asset files**:
   ```
   downloads/materials/ -> Your materials folder
   downloads/models/ -> Your models folder
   downloads/sound/ -> Your sounds folder
   downloads/particles/ -> Your particles folder
   ```

4. **Restart server** or load plugins manually:
   ```
   sm plugins load attr_banner_boost
   sm plugins load attr_blast_jump_miss_boost
   sm plugins load attr_bonk_consumption
   sm plugins load attr_dmg_vs_grounded
   sm plugins load attr_jump_while_charging
   sm plugins load attr_mult_minicrit
   sm plugins load attr_parachute
   etc.
   ```

**Example attribute usage:**
```
"custom_parachute_enabled" "1 0.5 1 0.2"
"custom_dmg_vs_grounded_players" "0.5"
"custom_mult_minicrit_dmg" "2.0"
```
## Credits

**Author:** TheGabenZone

## License

These plugins are provided as-is for use in Team Fortress 2 Classic servers. Feel free to modify and distribute with credit to the original author.

## Support

For issues, suggestions, or contributions, please open an issue on the GitHub repository.