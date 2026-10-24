# Verify 10: real stereo pair + real 360 panorama (seen 2026-10-24)

## A. Stereo pair: HOLDS WITH CAVEATS
- Source: Perseverance raw-image JSON API, https://mars.nasa.gov/rss/api/?feed=raw_images&category=mars2020&feedtype=json&num=100&order=sol+desc&search=MCZ_LEFT (the `search` value must be the instrument name MCZ_LEFT / MCZ_RIGHT; `search=ZL0` returns nothing). Seen 2026-10-24.
- Pair: Mastcam-Z, sol 1529 (2025-06-08), site 75, drive 0, sequence ZCAM09594, RGB, 1648x1200, 8-bit PNG (the raw-site "full_res" PNG), unrectified.
  - L: ZL0_1529_0802674999_598EBY_N0750000ZCAM09594_1100LMJ, MCZ_LEFT, 2025-06-08T17:36:21Z, SCLK 802675015.309. Page: https://mars.nasa.gov/mars2020/multimedia/raw-images/ZL0_1529_0802674999_598EBY_N0750000ZCAM09594_1100LMJ
  - R: ZR0_1529_0802675015_598EBY_N0750000ZCAM09594_1100LMJ, MCZ_RIGHT, 2025-06-08T17:36:31Z, SCLK 802675025.802. Page: https://mars.nasa.gov/mars2020/multimedia/raw-images/ZR0_1529_0802675015_598EBY_N0750000ZCAM09594_1100LMJ
  - Files: vr/Assets/nasa/pers-stereo-sol1529-L.png (5.06 MB), pers-stereo-sol1529-R.png (5.05 MB). Both 1648x1200, so no 2048 copy needed.
- Subject: a rock abrasion patch on the Jezero rim (Witch Hazel Hill area). Inferred, not confirmed by a caption, to be the "Kenmore" patch (abraded sol ~1526, PIA26576; sol 1529 is 3 sols later, same site 75). Lat/lon: UNVERIFIED (not in the API; a rim location, not the crater floor).
- Simultaneity: NOT strictly simultaneous. Same sol, same sequence, same file timestamp stem, but R was exposed about 10 s after L (SCLK +10.5 s). Rover was parked (drive 0), so the scene is static; usable as a stereo pair. Mastcam-Z always exposes L and R in sequence.
- Baseline: CAHVOR camera centres in the JSON differ by 0.235 m (24 cm, matches the spec). Human IPD 6.3 cm, so 3.7x hyperstereo: depth is exaggerated, the scene reads as a miniature.
- Optics: zoom lens, focal about 110 mm (hs about 14,770 px, computed from the CAHVOR model): HFOV 6.4 deg, VFOV 4.65 deg. This is a telephoto close-up. In a headset it will look like a flat screen with a large magnified view, not a window with natural size, unless shown as a quad with scale set deliberately.
- Distance: camera 1.93 m above ground, pitched 57 deg down gives about 2.3 m; the axes converge 5.4 deg apart over a 0.235 m baseline, giving about 2.5 m. Estimate: 2.3 to 2.5 m to the patch.
- Credit: NASA/JPL-Caltech/ASU (as stated in the API `credit` field).
- Caveats for builders: (1) the cameras are toed-in (5.4 deg) and have different poses, so there is visible vertical disparity (the patch sits about 40 px lower in R); rectify, or shift R up by about 40 px and accept the rest. (2) About 24 px black border on the left edge of both frames; crop it. (3) Raw frames have lens vignetting and radiometric artefacts. (4) The 3.7x baseline plus toe-in means a convergence at about 2.5 m; place the zero-parallax plane at the patch. (5) Navcam pair not searched; not needed.

## B. Panorama: HOLDS WITH CAVEATS
- Choice: PIA24663 "Mastcam-Z's 360-degree View of Van Zyl Overlook". Page: https://science.nasa.gov/photojournal/mastcam-zs-360-degree-view-of-van-zyl-overlook/ (fetched via photojournal.jpl.nasa.gov/catalog/PIA24663, seen 2026-10-24, page last updated 2021-06-09).
- Camera: Mastcam-Z right eye, 992 images stitched, sols 53 to 64 (2021-04-15 to 04-26). The 93,060x20,652 px (2.0 GB) master is only on the interactive viewer; the largest download is the 23,265x5,165 px version.
- Files (vr/Assets/nasa/): pers-pano-PIA24663-vanzyl-full.jpg (23265x5165, 15.4 MB, from https://assets.science.nasa.gov/content/dam/science/psd/photojournal/pia/pia24/pia24663/PIA24663.jpg); pers-pano-vanzyl-8192.jpg (8192x1818, 2.7 MB); pers-pano-vanzyl-4096.jpg (4096x909, 0.64 MB). A 213 MB TIFF exists at the same path with .tif; not downloaded (same size, no need).
- Projection: the caption does NOT state it. Aspect 4.50:1 is consistent with an equirectangular/cylindrical 360 x about 80 deg (64.6 px/deg). Horizon sits about 11% from the top (about 9 deg of sky above, about 71 deg of ground below). I am treating it as equirectangular-like: UNVERIFIED. Test it on the headset.
- Gaps: the image has big black voids (the rover deck and near-field area, bottom left, about 25% of the width at the bottom, and a smaller one at right). The caption mentions a Figure 1 version that adds the deck from Navcam; I did not find a downloadable file for it. Builder must fill or mask the black areas (e.g. sample the ground from a terrain texture below about 35 deg below the horizon).
- The sky is digitally smoothed and extended (caption).
- Location: Van Zyl Overlook is about 70 to 85 m from the Wright Brothers Field helicopter airfield, close to the Octavia E. Butler landing site (about 18.4446 N, 77.4509 E, my recollection, not confirmed here). That is on the Jezero floor roughly 2 km from the western delta front; the delta scarp (Kodiak, Hawksbill Gap) is the line of mesa on the horizon. Distance to our HiRISE tile centre (18.4 N, 77.4 E): about 3 km if the landing-site coordinates are right. UNVERIFIED (no lat/lon in the caption).
- Azimuth alignment: not stated in the caption. Alignment unknown. Landmark guess for a builder: the delta lies roughly NW of the landing site; the mesas on the horizon (right of centre in the image) look like the delta/Kodiak. Confirm by eye.
- Credit: NASA/JPL-Caltech/ASU/MSSS (photojournal credit; check the page "Credit" field before captioning).
- Not chosen: later 2023-2025 delta/rim panoramas not examined in depth; time-boxed.

## Licence
NASA media is generally not copyrighted (NASA media usage guidelines, https://www.nasa.gov/nasa-brand-center/images-and-media/); no NASA logo, no implied endorsement. Not independently re-fetched this session: UNVERIFIED beyond the guideline page's standard text.
