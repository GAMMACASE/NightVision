# NightVision
SourceMod plugin that allows players to enable custom "night vision".

# Features:
This plugin was created to light up dark maps and help players navigate on them. There's no green night vision, as it wasn't it's purpose, but you can look at **Creating custom templates** section, and create your own variation of night vision template, as this plugin has support for that.

# Examples:
Before:
![Before](https://i.imgur.com/An9LQrP.png)
After (using 3rd default template):
![After](https://i.imgur.com/I6agg4D.png)

# Installing notices:
Install plugin like you normally would, don't forget about cfg file (``addons/sourcemod/configs/nightvision.cfg``) and .raw files (``materials/gammacase/nightvision/*.raw``) (**don't forget to add these files to fastdl to!**). If you satisfied with default template presets then you are done with installing it, if not, then take a look at **Creating custom templates** section for more information!

# Usage:
Use ``sm_nightvision`` (``sm_nv`` for short) to toggle the nightvision.
Use ``sm_nightvisionsettings`` (``sm_nvs`` for short) to open settings menu, where you can configure your night vision (Note: it can be configured in real time, just enable it and then open settings menu).

# Creating custom templates:
To create and use custom templates you need to create .raw files (which are color correction files used by color_correction entity), which can be created and configured in game ([here's video tutorial on how to create them](https://www.youtube.com/watch?v=Y9Qnr2N9joE)). After you've done creating them you need to add them into ``addons/sourcemod/configs/nightvision.cfg``, follow the description added to ``Template1``, after you've done with cfg file, you should be able to see and use it in game.

# Special thanks:
* mbhound#0001 - for helping me to test this plugin before release.
