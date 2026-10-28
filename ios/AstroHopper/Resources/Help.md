# AstroHopper

AstroHopper helps you find objects across the night sky. It lets you hop accurately from a well-known, easily identifiable star to fainter stars or deep-sky objects by measuring changes in the phone's pointing angle with its gyroscope and gravity sensors. It works like Digital Setting Circles implemented in a phone.

The phone needs gyroscope and gravity sensors, and preferably a compass. AstroHopper works fully offline; only the optional Wikipedia pages need a network connection.

## Operation

Attach the phone to the telescope so that the physical **top** of the phone points in the viewing direction. This is different from typical sky apps that simulate a camera view: in AstroHopper the screen is parallel to the viewing direction.

Before you attach the phone, calibrate the compass by moving it in a figure-8 pattern. Calibration significantly improves compass accuracy. If the compass still does not work properly, tap the hand button to use manual mode.

1. Point the telescope at an easily identifiable star or planet near the object you want to observe.
2. Tap **Align** at the top left of the screen.
3. Tap the star or planet you pointed at. A 3 second countdown starts so the telescope can stop shaking. Then the app is aligned on the selected object: "Aligned" is shown and a cross in the center of the screen shows where the telescope points.
4. Tap the object you want to observe, or type its name in the search box. A line shows the direction to move the telescope, and the remaining altitude and azimuth changes are shown at the right and bottom of the screen.
5. Move the telescope until these numbers are close to zero. The telescope now points at the requested object.
6. To move to the next object, repeat the alignment from step 1, because the phone's gyroscope loses accuracy over time and over multiple movements.

Tutorial videos:

- Demonstration and tutorial by Nir Zonshine: <https://youtu.be/AtArqBLWWJ8>
- Review by John Dreese (Reflactor): <https://youtu.be/6-_58mSGz1Q>

## Troubleshooting

**The sky looks different from what I expect.** Make sure Location Services are allowed for AstroHopper. Until a location is known, "No Geolocation" is shown. Check the coordinates at the bottom of the Settings screen.

**I move the telescope but only the altitude changes.** Your phone may not have a working compass. A crossed-out location icon is shown at the top right. Drag the map left or right until the azimuth is right, then align.

**I pointed the telescope at a star but the phone seems to point elsewhere.** The compass may be significantly off. You can:

1. Move the phone in a figure-8 pattern to calibrate the compass.
2. Increase the field of view with `-` next to `∠60°`.
3. Switch to manual azimuth mode with the hand button and drag the map until the star is visible.

**The app stopped following the telescope in azimuth, or moves strangely.** The gyroscope lost accuracy. Try again. If it keeps happening:

1. Choose an alignment star that is closer in azimuth to the target; altitude tracking is much more accurate.
2. Correct the altitude first, then search for the object along the azimuth.

**Running without sensors.** When the device has no gyroscope (for example in the iOS Simulator), AstroHopper runs as a demo: drag the map to move a virtual telescope.

## Controls

Left side, from top to bottom:

- **Align** button and status: starts the alignment; then select the star or planet you are aligned on.
- Field of view: change it with `-` and `+`.
- When a watch list is selected, `<` and `>` browse its objects. The selected object's name is shown below.
- **W** appears when a named object is selected and the phone is online, and opens the object's Wikipedia page.

Right side:

- Object search box: type an object name or code, such as `M31`, `NGC 7000` or `Vega`.
- Hand button: switch to manual mode. Compass button: switch back to compass mode. A crossed-out location icon means no compass is available.
- Gear button: Settings.

You can also pinch the map to change the field of view.

## Settings

- `↻`: reset alignment and target.
- **Small UI**: smaller buttons; the field of view controls move to Settings. The Align button becomes `◎` with status `✓` aligned, `✗` not aligned, `?` select the alignment star.
- **Night**: red night-vision mode for the sky map.
- **Stars**: the faintest star magnitude to show and align on.
- **DSO**: the faintest deep-sky object magnitude to show.
- **List**: select and edit watch lists.
- **Font**: make labels bigger.
- Object search field.
- **Align on DSO**: allow aligning on any object. Use with care, since it is hard to pinpoint the center of a big object such as an open cluster.
- Object type filters, star names, pinch zoom and the startup tutorial.
- **Wiki**: when the Wikipedia button is available: never, in day mode only, or always.
- **User Objects**: show and edit your own objects.
- Location and sensor information.

## Wikipedia Page Info

When a named object is selected and the phone has a network connection, the **W** button appears. Tap it to open the Wikipedia page about the object. Without a connection the button is hidden. The page is not designed for night use and may be bright, so by default this is disabled in Night mode. Change this with the "Wiki" setting.

## Watch List

You can prepare a watch list in advance to browse it easily during the night. Open Settings and tap `[edit]` next to "List".

A watch list is a list of object names separated by spaces, new lines or commas, for example:

    M41, M47, M49, M50, M44, M45

Define several named lists by giving each list a name followed by `:`, for example:

    clusters: M41 M47 M49
     M50 M44 M45
    doublestars: Polaris, "Cor Caroli"

You can add a comment between `(` and `)` to explain an object. It is shown when the object is selected:

    Galaxies: M31 (Andromeda), M64 (Black Eye)

If you add a comment or use a name that contains spaces, use a comma `,` as the separator.

Select a list with `<` and `>` in Settings. Then two buttons, `<` and `>`, appear on the main screen under the Align button to browse its objects. The lists are saved on the phone.

## User Objects

The database does not contain every star or deep-sky object. You can add your own under "User Objects" in Settings.

User objects use CSV format: the first column is the object name, the second its right ascension (RA) and the third its declination (DEC). RA and DEC can be decimal degrees (0 to 360 for RA, -90 to +90 for DEC) or hours/degrees with minutes and optional seconds, separated by spaces, `:` or symbols such as `h`, `m`, `s`, `d`:

- RA: `170.6358`, `11:22:32.6`, `11h 22m 32.6s`, `11h 22' 32.6''`, `11 22′ 32.6″`, `11 22 32.6`, `11:32`
- DEC: `-87.3757`, `-87:22:32.6`, `-87d 22m 32.6s`, `-87d 22' 32.6''`, `-87° 22′ 32.6″`, `-87 22 32.6`, `-87:22`

For example:

    V1405,23h 24m 48s, +61° 11′ 15″
    Pluto,19:55:16,-22:13:42

## Equatorial Mount Users

The app assumes an alt-azimuth mount. With an equatorial mount, any misalignment between the phone's long axis and the telescope axis adds an error.

If the targets are close to the poles and the hop needs a large change in right ascension, the misalignment affects accuracy. The final error is about 2e⋅sin(Δα/2)⋅sin(δ), where e is the misalignment between phone and telescope, Δα the change in right ascension and δ the declination of the target. So it may not work reliably for equatorial mounts; alt-az mounts are recommended.

## Copyrights

AstroHopper (C) 2021-2023 Artyom Beilis, licensed under the GPL v3. It works only with well-working sensors. No warranty of any kind is given.

- Star and constellation data derived from <https://github.com/eleanorlutz/western_constellations_atlas_of_space> (GPL).
- Deep-sky object data from OpenNGC <https://github.com/mattiaverga/OpenNGC> (CC-BY-SA 4.0).
- Planet calculations by Greg A Miller, public domain.
- Quick start images (C) Maxim Tonkikh.
