printf "${STY_YELLOW}"
printf "============WARNING/NOTE (1)============\n"
printf "Ensure you have a global use flag for elogind or systemd in your make.conf for simplicity\n"
printf "Or you can manually add the use flags for each package that requires it\n"
printf "${STY_RST}"
pause

printf "${STY_YELLOW}"
printf "============WARNING/NOTE (2)============\n"
printf "https://github.com/end-4/dots-hyprland/blob/main/sdata/dist-gentoo/README.md\n"
printf "Checkout the above README for potential bug fixes or additional information\n\n"
printf "${STY_RST}"
pause

x sudo emerge --update --quiet app-eselect/eselect-repository
x sudo emerge --update --quiet app-portage/smart-live-rebuild
# Currently using 3.12 python, this doesn't need to be default though
x sudo emerge --update --quiet dev-lang/python:3.12

if [[ -z $(eselect repository list | grep ii-dots) ]]; then
	v sudo eselect repository create ii-dots
	v sudo eselect repository enable ii-dots
fi

if [[ -z $(eselect repository list | grep -E ".*guru \*.*") ]]; then
        v sudo eselect repository enable guru
fi

if [[ -z $(eselect repository list | grep -E ".*hyproverlay \*.*") ]]; then
	v sudo eselect repository enable hyproverlay
fi

arch=$(portageq envvar ACCEPT_KEYWORDS)

# Exclude hyprland, will deal with that separately
metapkgs=(immaterial-impulse-{audio,backlight,basic,bibata-modern-classic-bin,fonts-themes,hyprland,kde,microtex-git,portal,python,quickshell-git,screencapture,toolkit,widgets})

ebuild_dir="/var/db/repos/ii-dots"


########## IMPORT KEYWORDS (START)
# Illogical-Impulse
x sudo cp ./sdata/dist-gentoo/keywords ./sdata/dist-gentoo/keywords-user
x sed -i "s/$/ ~${arch}/" ./sdata/dist-gentoo/keywords-user
v sudo cp ./sdata/dist-gentoo/keywords-user /etc/portage/package.accept_keywords/immaterial-impulse

########## IMPORT USEFLAGS
v sudo cp ./sdata/dist-gentoo/useflags /etc/portage/package.use/immaterial-impulse
v sudo sh -c 'cat ./sdata/dist-gentoo/additional-useflags >> /etc/portage/package.use/immaterial-impulse'

########## UPDATE SYSTEM
v sudo emerge --sync
v sudo emerge --quiet --newuse --update --deep @world
v sudo emerge --quiet @smart-live-rebuild

# Remove old ebuilds (if this isn't done the wildcard will fuck upon a version change)
x sudo rm -fr ${ebuild_dir}/app-misc/immaterial-impulse-*

source ./sdata/dist-gentoo/import-local-pkgs.sh

########## INSTALL ILLOGICAL-IMPUSEL EBUILDS
for i in "${metapkgs[@]}"; do
	x sudo mkdir -p ${ebuild_dir}/app-misc/${i}
	v sudo cp ./sdata/dist-gentoo/${i}/${i}*.ebuild ${ebuild_dir}/app-misc/${i}/
	v sudo ebuild ${ebuild_dir}/app-misc/${i}/*.ebuild digest
	v sudo emerge --update --quiet app-misc/${i}
done

v sudo emerge --depclean

## TODO(qs-wallpaperengine, INSTALL_WE): linux-wallpaperengine's upstream
## README only documents Ubuntu/Debian/Alt-Linux/Fedora dep lists, no Gentoo
## atoms, and this distro's dep mechanism is a whole ebuild/overlay pipeline
## (ii-dots/guru/hyproverlay above) rather than ad-hoc `emerge <pkg>` calls,
## so package-category names below aren't confidently verifiable from here
## (e.g. cmake has moved between sys-devel/ and dev-build/ across Gentoo
## versions). The underlying deps to cover, per linux-wallpaperengine's
## System Requirements section: cmake, lz4, zlib, sdl2, ffmpeg, X11/XRandr,
## glfw3, glew, freeglut, glm, mpv, pulseaudio, fftw3, freetype. Gate any
## addition behind `[[ "${INSTALL_WE:-0}" == "1" ]]` same as dist-arch/
## dist-fedora, e.g.:
##   if [[ "${INSTALL_WE:-0}" == "1" ]]; then
##     v sudo emerge --update --quiet <verified atoms for the deps above>
##   fi
