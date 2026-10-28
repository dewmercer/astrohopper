# AstroHopper

AstroHopper helps you find objects across the night sky. It lets you hop accurately from a well-known, easily identifiable star to fainter stars or deep-sky objects by measuring changes in the phone's pointing angle with its gyroscope and gravity sensors. It works like Digital Setting Circles implemented in a phone.

The phone needs gyroscope and gravity sensors, and preferably a compass. AstroHopper works fully offline; only the optional Wikipedia pages need a network connection.

## Operation

Attach the phone to the telescope so that the physical **top** of the phone points in the viewing direction. This is different from typical sky apps that simulate a camera view: in AstroHopper the screen is parallel to the viewing direction.

Before you attach the phone, calibrate the compass by moving it in a figure-8 pattern. Calibration significantly improves compass accuracy. If the compass still does not work properly, tap **Compass** in the toolbar to switch to manual mode.

1. Point the telescope at an easily identifiable star or planet near the object you want to observe.
2. Tap **Align** in the toolbar.
3. Tap the star or planet you pointed at, then let go of the telescope. The app waits until the gyroscope shows the telescope has stopped shaking, and the ring at the top fills while it stays still. If it moves, the status says "Waiting for the telescope to settle" and the wait starts again. Then the app is aligned on that object: the status at the top says "Aligned", and a cross in the center of the screen shows where the telescope points. Tap **Cancel** to keep the previous alignment instead.
4. Tap the object you want to observe, or tap **Search** and find it by name. A line on the map shows which way to move the telescope, and the card at the bottom shows how far: up or down, and left or right.
5. Move the telescope until the numbers on the card are close to zero. The telescope now points at the requested object.
6. To move to the next object, repeat the alignment from step 1, because the phone's gyroscope loses accuracy over time and over multiple movements.

### Two- and Three-Star Alignment

A single star corrects the map near that star, but if the phone isn't exactly parallel to the tube, the error grows as you move away from it. In Settings › Alignment, choose 2 or 3 alignment stars to correct for this.

After the first star, the card at the bottom suggests the next one: a bright star well away from the first, comfortably above the horizon. Follow the arrows to it, tap it, and let the telescope settle as before. Tap **Other Star** for a different suggestion; any bright star far from the first works. With three stars, the app also corrects a small tilt.

When alignment is complete, the status shows how well the stars agree, for example "Aligned on 2 stars ±0.3°". A large value means one of the stars wasn't centered, so align again. Tap **Done** at any point to stop with the stars aligned so far.

### Finder and Eyepiece Circles

In Settings › Field of View Circles, turn on a circle for your finder (its field of view in degrees) or your eyepiece (from the telescope and eyepiece focal lengths and the eyepiece's apparent field). The circles are drawn around the center of the map. When the target enters one, the phone taps — lightly for the finder, firmly for the eyepiece — and the card shows "In Finder" or "In Eyepiece".

Tutorial videos:

- Demonstration and tutorial by Nir Zonshine: <https://youtu.be/AtArqBLWWJ8>
- Review by John Dreese (Reflactor): <https://youtu.be/6-_58mSGz1Q>

## Troubleshooting

**The sky looks different from what I expect.** Make sure Location Services are allowed for AstroHopper. Until a location is known, "No Location" is shown at the top of the screen. Check the coordinates under Settings › Location and Sensors.

**I move the telescope but only the altitude changes.** Your phone may not have a working compass; the toolbar then shows **No Compass**. Drag the map left or right until the azimuth is right, then align.

**I pointed the telescope at a star but the phone seems to point elsewhere.** The compass may be significantly off. You can:

1. Move the phone in a figure-8 pattern to calibrate the compass.
2. Zoom out with `−` on the right side of the screen to widen the field of view.
3. Tap **Compass** to switch to manual mode, then drag the map until the star is visible.

**The app stopped following the telescope in azimuth, or moves strangely.** The gyroscope lost accuracy. Try again. If it keeps happening:

1. Choose an alignment star that is closer in azimuth to the target; altitude tracking is much more accurate.
2. Correct the altitude first, then search for the object along the azimuth.

**Running without sensors.** When the device has no gyroscope (for example in the iOS Simulator), AstroHopper runs as a demo: drag the map to move a virtual telescope.

## Controls

At the top, the status shows whether the app is aligned, and on which object. Below it are the altitude and azimuth the telescope points at.

On the right, `+` and `−` change the field of view. You can also pinch the map.

The toolbar at the bottom has:

- **Align**: start an alignment, then tap the star or planet the telescope points at. While aligning, this becomes **Cancel**.
- **Search**: find an object by name or catalog number, such as `M31`, `NGC 7000`, `Vega` or `Jupiter`.
- **Lists**: choose a watch list to browse.
- **Compass** or **Manual**: switch between compass mode and manual mode, where you drag the map to set the azimuth. **No Compass** means the phone has none.
- **Settings**.

When an object is selected, a card shows its name, type, magnitude, size and other names, and how far to move the telescope. With a watch list selected, `‹` and `›` on the card step through the list. Tap `✕` to clear the target.

## Settings

- **Display**: Night mode (red only, to protect your dark adaptation), star names, pinch to zoom, and map label size.
- **Faintest Magnitude**: the faintest stars and deep-sky objects to show. Only stars shown on the map can be used for alignment.
- **Show on Map**: object types to show.
- **Lists**: edit watch lists and your own objects.
- **Alignment**: the number of alignment stars, and whether to allow aligning on deep-sky objects (use that with care, since it is hard to pinpoint the center of a large object such as an open cluster). You can also reset the alignment and target here.
- **Field of View Circles**: finder and eyepiece circles.
- **Wikipedia Button**: never, in day mode only, or always.
- **Help**: this guide and the quick start.
- **Location and Sensors**: your coordinates and raw sensor readings.

## Wikipedia Page Info

When a named object is selected and the phone has a network connection, the target card shows a **Wikipedia** button. Tap it to open the object's Wikipedia page. Without a connection the button is hidden. Wikipedia pages are not designed for night use and may be bright, so by default the button is hidden in Night mode. Change this with Settings › Wikipedia Button.

## Watch List

You can prepare a watch list in advance to browse it easily during the night. Open Settings › Watch Lists.

A watch list is a list of object names separated by spaces, new lines or commas, for example:

    M41, M47, M49, M50, M44, M45

Define several named lists by giving each list a name followed by `:`, for example:

    clusters: M41 M47 M49
     M50 M44 M45
    doublestars: Polaris, "Cor Caroli"

You can add a comment between `(` and `)` to explain an object. It is shown when the object is selected:

    Galaxies: M31 (Andromeda), M64 (Black Eye)

If you add a comment or use a name that contains spaces, use a comma `,` as the separator.

Choose a list from **Lists** in the toolbar. Its first object becomes the target, and `‹` and `›` on the target card step through the list. The lists are saved on the phone.

## User Objects

The database does not contain every star or deep-sky object. You can add your own under Settings › User Objects.

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
