# Assets

`Sources/BildShow/Resources/DemoPortrait.png` was generated with the built-in image-generation tool on 2026-10-17. It depicts a fictional adult and is independent of Lenna and USC 4.1.04. The returned image is 1672 × 941 pixels, despite the requested 4K output. BildShow creates proportional smaller demo variants locally with ImageIO. The app does not use generative AI at runtime.

## Generation prompt

```text
Use case: photorealistic-natural.
Asset type: high-resolution demonstration photograph for BildShow, a macOS slideshow viewer.
Primary request: Create an original, photorealistic photographic portrait of a fictional adult woman, suitable for demonstrating image scaling, fine detail, tonal transitions and edge feathering. Generate a brand-new composition and identity without using or recreating any existing test photograph.
Output intent: 3840 x 2160 pixels, landscape 16:9, maximum native detail.
Scene/backdrop: a simple photographic studio backdrop with subtle natural texture and a smooth warm-gray tonal gradient.
Subject: a fictional woman about 35 years old, natural dark brown wavy hair, realistic skin texture and a calm expression, wearing a finely woven teal-blue linen blouse with a modest neckline.
Composition/framing: centered head-and-shoulders portrait with the entire head and hair visible, comfortable headroom and background space around the silhouette. The portrait must remain useful when viewed as a centered square or vertical crop.
Lighting/mood: soft directional studio daylight with gentle shadow detail and restrained highlights.
Style/medium: premium natural photographic realism, sharply resolved eyes, individual hair strands, believable pores and fabric weave. Natural color, no beauty retouching, no artificial sharpening halos.
Constraints: one adult subject, no text, no logo, no watermark, no decorative border, opaque background, no hats, no props, no collage, no in-image UI. Preserve natural proportions.
```

## App icon

The original geometric icon is drawn using AppKit by `scripts/make-icon.swift`. Rebuild it by running the script with a `.iconset` output directory, then `iconutil -c icns`.
