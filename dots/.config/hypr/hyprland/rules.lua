-- ######## Window rules ########

-- Disable blur for xwayland context menus
hl.window_rule({match = {class = "^()$", title = "^()$" },                   no_blur = true })

-- Disable blur for every window
hl.window_rule({match = {class = ".*" }, no_blur = true })

-- ...except the shell's own translucent toplevels (e.g. the Settings window,
-- class org.quickshell). The catch-all above would otherwise leave sharp
-- wallpaper showing through them instead of the frosted look the panels have.
hl.window_rule({match = {class = "^(org.quickshell)$" },                     no_blur = false })

-- Floating
hl.window_rule({match = {title = "^(Open File)(.*)$" },                      center = true})
hl.window_rule({match = {title = "^(Open File)(.*)$" },                      float = true})
hl.window_rule({match = {title = "^(Select a File)(.*)$" },                  center = true})
hl.window_rule({match = {title = "^(Select a File)(.*)$" },                  float = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               center = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               float = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               size = {"(monitor_w*0.60)", "(monitor_h*0.65)"} })
hl.window_rule({match = {title = "^(Open Folder)(.*)$" },                    center = true})
hl.window_rule({match = {title = "^(Open Folder)(.*)$" },                    float = true})
hl.window_rule({match = {title = "^(Save As)(.*)$" },                        center = true})
hl.window_rule({match = {title = "^(Save As)(.*)$" },                        float = true})
hl.window_rule({match = {title = "^(Library)(.*)$" },                        center = true})
hl.window_rule({match = {title = "^(Library)(.*)$" },                        float = true})
hl.window_rule({match = {title = "^(File Upload)(.*)$" },                    center = true})
hl.window_rule({match = {title = "^(File Upload)(.*)$" },                    float = true})
hl.window_rule({match = {title = "^(.*)(wants to save)$" },                  center = true})
hl.window_rule({match = {title = "^(.*)(wants to save)$" },                  float = true})
hl.window_rule({match = {title = "^(.*)(wants to open)$" },                  center = true})
hl.window_rule({match = {title = "^(.*)(wants to open)$" },                  float = true})
hl.window_rule({match = {class = "^(blueberry\\.py)$" },                     float = true})
hl.window_rule({match = {class = "^(guifetch)$" },                           float = true}) -- FlafyDev/guifetch
hl.window_rule({match = {class = "^(pavucontrol)$" },                        float = true})
hl.window_rule({match = {class = "^(pavucontrol)$" },                        size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(pavucontrol)$" },                        center = true})
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         float = true})
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         center = true})
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               float = true})
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               center = true})
hl.window_rule({match = {class = ".*plasmawindowed.*" },                     float = true})
hl.window_rule({match = {class = "kcm_.*" },                                  float = true})
hl.window_rule({match = {class = ".*bluedevilwizard" },                      float = true})
hl.window_rule({match = {title = ".*Welcome" },                              float = true})
hl.window_rule({match = {title = "^(Settings)$" },                           float = true})
hl.window_rule({match = {title = ".*Shell conflicts.*" },                    float = true})
hl.window_rule({match = {class = "org.freedesktop.impl.portal.desktop.kde" }, float = true})
hl.window_rule({match = {class = "org.freedesktop.impl.portal.desktop.kde" }, size = {"(monitor_w*0.60)", "(monitor_h*0.65)"} })
hl.window_rule({match = {class = "^(Zotero)$" },                             float = true})
hl.window_rule({match = {class = "^(Zotero)$" },                             size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })

-- Move
-- kde-material-you-colors spawns a window when changing dark/light theme. This is to make sure it doesn't interfere at all.
hl.window_rule({match = {class = "^(plasma-changeicons)$" }, float = true})
hl.window_rule({match = {class = "^(plasma-changeicons)$" }, no_initial_focus = true})
hl.window_rule({match = {class = "^(plasma-changeicons)$" }, move = {999999, 999999}})
-- stupid dolphin copy
hl.window_rule({match = {title = "^(Copying — Dolphin)$" }, move = {40, 80}})

-- Tiling
hl.window_rule({match = {class = "^dev\\.warp\\.Warp$" }, tile = true})

-- Picture-in-Picture
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, float = true})
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, keep_aspect_ratio = true})
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, move = {"(monitor_w*0.73)", "(monitor_h*0.72)"} })
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, size = {"(monitor_w*0.25)", "(monitor_h*0.25)"} })
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, float = true})
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, pin = true})

-- Screen sharing
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, float = true})
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, pin = true})
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, move = {"(monitor_w*.5-window_w*.5)", "(monitor_h-window_h-12)"} })

-- --- Tearing ---
hl.window_rule({match = {title = ".*\\.exe" }, immediate = true})
hl.window_rule({match = {title = ".*minecraft.*" }, immediate = true})
hl.window_rule({match = {class = "^(steam_app).*" }, immediate = true})

-- No shadow for tiled windows
hl.window_rule({match = {float = 0 }, no_shadow = true})

-- ######## Workspace rules ########
hl.workspace_rule({ workspace = "special:special", gaps_out = 30 })

-- ######## Layer rules ########
hl.layer_rule({ match = { namespace = ".*" }, xray = false})
hl.layer_rule({ match = { namespace = "walker" }, no_anim = true})
hl.layer_rule({ match = { namespace = "selection" }, no_anim = true})
hl.layer_rule({ match = { namespace = "overview" }, no_anim = true})
hl.layer_rule({ match = { namespace = "anyrun" }, no_anim = true})
hl.layer_rule({ match = { namespace = "indicator.*" }, no_anim = true})
hl.layer_rule({ match = { namespace = "osk" }, no_anim = true})
hl.layer_rule({ match = { namespace = "hyprpicker" }, no_anim = true})

hl.layer_rule({ match = { namespace = "noanim" }, no_anim = true})
hl.layer_rule({ match = { namespace = "gtk-layer-shell" }, blur = true})
hl.layer_rule({ match = { namespace = "gtk-layer-shell" }, ignore_alpha = 0})
hl.layer_rule({ match = { namespace = "launcher" }, blur = true})
hl.layer_rule({ match = { namespace = "launcher" }, ignore_alpha = 0.5})
hl.layer_rule({ match = { namespace = "notifications" }, blur = true})
hl.layer_rule({ match = { namespace = "notifications" }, ignore_alpha = 0.69})
hl.layer_rule({ match = { namespace = "logout_dialog" }, blur = true}) -- wlogout

-- ags
hl.layer_rule({ match = { namespace = "sideleft.*" }, animation = "slide left"})
hl.layer_rule({ match = { namespace = "sideright.*" }, animation = "slide right"})
hl.layer_rule({ match = { namespace = "session[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "bar[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "bar[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "barcorner.*" }, blur = true})
hl.layer_rule({ match = { namespace = "barcorner.*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "dock[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "dock[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "indicator.*" }, blur = true})
hl.layer_rule({ match = { namespace = "indicator.*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "overview[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "overview[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "cheatsheet[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "cheatsheet[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "sideright[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "sideright[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "sideleft[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "sideleft[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "indicator.*" }, blur = true})
hl.layer_rule({ match = { namespace = "indicator.*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "osk[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "osk[0-9]*" }, ignore_alpha = 0.6})

-- Quickshell
-- Quickshell: immaterial-impulse
hl.layer_rule({ match = { namespace = "quickshell:.*" }, blur_popups = true})
hl.layer_rule({ match = { namespace = "quickshell:.*" }, blur = true})
-- Low threshold: pixels below it are left unblurred, so a high value skipped
-- blur on the shell's own translucent panel backgrounds and let the sharp
-- wallpaper show straight through the bar/dock/sidebars. Namespace-specific
-- overrides below (popup/mediaControls/session/...) still set their own.
hl.layer_rule({ match = { namespace = "quickshell:.*" }, ignore_alpha = 0.05})
hl.layer_rule({ match = { namespace = "quickshell:bar" }, animation = "slide"})
hl.layer_rule({ match = { namespace = "quickshell:actionCenter" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:cheatsheet" }, animation = "slide bottom"})
-- The subject selector: a full-screen surface that is transparent everywhere
-- except one toolbar, because the wallpaper and the widgets it is judging are
-- the real ones underneath it. Under the catch-all above that is the worst
-- possible case - a screen-sized surface asking the compositor to blur the
-- entire screen behind it - so its blur is scoped to the toolbar's own rect
-- through a region, the same way the bar's and the sidebars' are. It also opens
-- and closes on a button, so a map animation on something this size reads as
-- the desktop lurching.
hl.layer_rule({ match = { namespace = "quickshell:clockDepthSelect" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:clockDepthSelect" }, blur = false})
-- Bare `slide`, like the bar above: the compositor slides toward whichever
-- edge the surface is anchored to, so the dock's exit and entry follow its
-- configured edge. Naming the edge here pinned it to the bottom, and a top
-- dock then slid downward, into the screen, to leave.
hl.layer_rule({ match = { namespace = "quickshell:dock" }, animation = "slide"})
-- Edit Mode's chrome: another full-screen surface that is transparent
-- everywhere except two opaque toolbars, because the desktop it frames is the
-- real one underneath it. Same hazard as the subject selector above - under the
-- catch-all 0.05 its transparent pixels clear the threshold and the compositor
-- is asked to blur the whole screen - answered the other way round, because the
-- toolbar bodies are m3surfaceContainer and therefore fully opaque: at
-- ignore_alpha = 1 the bodies are the only thing blurred, and their shadows and
-- everything else on the surface are left alone. That is the treatment
-- quickshell:overlay and quickshell:recordingRegion already carry for this
-- shape. The surface is created and destroyed by a toggle, so a map animation
-- on something screen-sized reads as the desktop lurching.
hl.layer_rule({ match = { namespace = "quickshell:editMode" }, ignore_alpha = 1})
hl.layer_rule({ match = { namespace = "quickshell:editMode" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:screenCorners" }, animation = "popin 120%"})
hl.layer_rule({ match = { namespace = "quickshell:lockWindowPusher" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:notificationPopup" }, animation = "fade"})
hl.layer_rule({ match = { namespace = "quickshell:overlay" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:overlay" }, ignore_alpha = 1})
-- The overview owns its own entrance and exit in QML (Overview.qml: the
-- card unfurls from its top edge on one scalar, and the window outlives
-- the open flag by exactly that exit animation). A compositor map
-- animation on top of it would animate the whole screen-sized surface
-- underneath the card that is already animating, so the layerrule stays
-- off. Removing this line does not give the overview an animation - it
-- gives it two, one of them the desktop lurching.
hl.layer_rule({ match = { namespace = "quickshell:overview" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:osk" }, animation = "slide bottom"})
hl.layer_rule({ match = { namespace = "quickshell:polkit" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:popup" }, xray = false}) -- No weird color for bar tooltips (this in theory should suffice)
hl.layer_rule({ match = { namespace = "quickshell:popup" }, ignore_alpha = 1}) -- No weird color for bar tooltips (but somehow this is necessary)
hl.layer_rule({ match = { namespace = "quickshell:mediaControls" }, ignore_alpha = 1}) -- Same as above
hl.layer_rule({ match = { namespace = "quickshell:reloadPopup" }, animation = "slide"})
-- The recording controls are a small toolbar in a window that is mostly
-- transparent: the extra room is for the toolbar's own shadow. The
-- catch-all above blurs anything over 5% alpha, which frosts that shadow
-- into a haze the size of the window. Same treatment as the popup and
-- overlay surfaces, and for the same reason.
hl.layer_rule({ match = { namespace = "quickshell:recordingRegion" }, ignore_alpha = 1})
hl.layer_rule({ match = { namespace = "quickshell:recordingRegion" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:regionSelector" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:screenshot" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:session" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:session" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:session" }, ignore_alpha = 0})
hl.layer_rule({ match = { namespace = "quickshell:sidebarRight" }, animation = "slide right"})
hl.layer_rule({ match = { namespace = "quickshell:sidebarLeft" }, animation = "slide left"})
-- The sidebars draw a translucent drop shadow (StyledRectangularShadow) in
-- their surface's elevation margin. The catch-all whole-surface blur above
-- frosts that shadow into an ugly band along the panel's edge (#82). Turn the
-- layerrule blur off for these namespaces; the shell scopes blur to just the
-- panel body instead, via ext-background-effect (WindowBlurRegion.qml), so a
-- translucent body still gets its backdrop blur while the shadow stays crisp.
hl.layer_rule({ match = { namespace = "quickshell:sidebarRight" }, blur = false})
hl.layer_rule({ match = { namespace = "quickshell:sidebarLeft" }, blur = false})
-- Same treatment for the bars and dock: their drop shadows and margin strips
-- share the surface with the body, so the whole-surface blur frosted them
-- too. The shell scopes blur to the painted body rects instead (see
-- WindowBlurRegion in Bar.qml / VerticalBar.qml / Dock.qml).
hl.layer_rule({ match = { namespace = "quickshell:bar" }, blur = false})
hl.layer_rule({ match = { namespace = "quickshell:verticalBar" }, blur = false})
hl.layer_rule({ match = { namespace = "quickshell:dock" }, blur = false})
-- And the transient surfaces, which were the last panels still frosting their
-- own shadow (#89): every OSD indicator sits in an elevation margin, and the
-- overview surface carries two shadowed cards (the search widget and the
-- overview itself). See WindowBlurRegion in OnScreenDisplay.qml / Overview.qml.
hl.layer_rule({ match = { namespace = "quickshell:onScreenDisplay" }, blur = false})
hl.layer_rule({ match = { namespace = "quickshell:overview" }, blur = false})
-- The cheatsheet has drawn a StyledRectangularShadow all along; the
-- whole-surface blur was frosting it, which is why the card read as having no
-- shadow at all. See WindowBlurRegion in Cheatsheet.qml.
hl.layer_rule({ match = { namespace = "quickshell:cheatsheet" }, blur = false})
-- Notification popups: each card carries its own shadow, so the whole-surface
-- blur frosted every one of them. The shell publishes a region per card
-- instead, leaving the gaps between them unblurred. See WindowBlurRegion in
-- NotificationPopup.qml.
hl.layer_rule({ match = { namespace = "quickshell:notificationPopup" }, blur = false})
-- The on-screen keyboard and the wallpaper selector were the last two panels
-- still frosting their own shadow: both draw a StyledRectangularShadow inside
-- an elevation margin, and the catch-all blur above takes every pixel over
-- ignore_alpha (0.05), which a shadow clears easily. See WindowBlurRegion in
-- OnScreenKeyboard.qml / WallpaperSelector.qml.
hl.layer_rule({ match = { namespace = "quickshell:osk" }, blur = false})
hl.layer_rule({ match = { namespace = "quickshell:wallpaperSelector" }, blur = false})
-- The popups those surfaces open (the tray menu, the dock's context menu, the
-- drag-apps sheet, every tooltip) draw shadows too, and blur_popups above
-- frosts them the same way. The fix above does not reach them: an
-- ext-background-effect region belongs to a layer surface, and a popup is an
-- xdg-popup, so a region published from one is accepted and does nothing.
-- Popups carry no namespace of their own either - they inherit their parent
-- surface's rules, which is why this is keyed on the parents.
--
-- So threshold by alpha instead: below `ignore_alpha` a pixel is left
-- unblurred, and the shadow and the body sit at different alphas. Where the
-- line falls depends on the user's transparency setting, which a layerrule
-- cannot read, so the shell computes it and writes it out - see
-- services/PopupBlurThreshold.qml. The fallback covers the first run, before
-- the shell has ever written the file.
local ok, generated = pcall(dofile, os.getenv("HOME") .. "/.config/hypr/hyprland/shellOverrides/popupBlur.lua")
local popup_blur_threshold = (ok and type(generated) == "number") and generated or 0.6

-- Keyed on the parent surfaces. Their own bodies are blurred through a
-- region, and a region is subject to ignore_alpha too, so the threshold has
-- to stay below the faintest body among them as well as above the shadow -
-- which is what PopupBlurThreshold computes. Getting that backwards unblurs
-- the panels themselves.
for _, ns in ipairs({ "quickshell:bar", "quickshell:verticalBar", "quickshell:dock",
                      "quickshell:sidebarLeft", "quickshell:sidebarRight",
                      -- The bar popup overlay: one always-mapped surface whose
                      -- card hosts every bar popup's content, so the menus those
                      -- popups open are now xdg-popups of *this* surface and
                      -- inherit its threshold rather than the bar's.
                      "quickshell:barPopup" }) do
    hl.layer_rule({ match = { namespace = ns }, ignore_alpha = popup_blur_threshold })
end

hl.layer_rule({ match = { namespace = "quickshell:verticalBar" }, animation = "slide"})
hl.layer_rule({ match = { namespace = "quickshell:osk" }, order = -1})
-- Quickshell: waffles
hl.layer_rule({ match = { namespace = "quickshell:wallpaperSelector" }, animation = "slide top"})
hl.layer_rule({ match = { namespace = "quickshell:wNotificationCenter" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:wOnScreenDisplay" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:wStartMenu" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:wTaskView" }, ignore_alpha = 0})
hl.layer_rule({ match = { namespace = "quickshell:wTaskView" }, no_anim = true})

-- Launchers need to be FAST
hl.layer_rule({ match = { namespace = "gtk4-layer-shell" }, no_anim = true})
