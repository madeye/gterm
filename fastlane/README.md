# fastlane — App Store metadata & screenshots

This folder holds the App Store Connect listing for **gterm**
(`io.github.madeye.gterm`), managed with [`deliver`](https://docs.fastlane.tools/actions/deliver/).

## Layout

```
fastlane/
  Appfile              app id / Apple id / team
  Deliverfile          deliver config (auth, paths, safety flags)
  metadata/
    copyright.txt, primary_category.txt, secondary_category.txt
    en-US/             name, subtitle, description, keywords, urls, notes
    review_information/ App Review contact + demo notes
  screenshots/
    en-US/             *_APP_IPHONE_61_* (1206×2622) and *_APP_IPHONE_67_* (1290×2796)
```

Screenshots are ordered by the leading number and grouped by device by the
`APP_IPHONE_61` / `APP_IPHONE_67` token in the filename.

## Auth

`deliver` authenticates with the App Store Connect API key at
`/Users/mlv/.appstoreconnect/api_key.json` (referenced from `Deliverfile`).
The `.p8` and JSON live outside the repo and must never be committed.

## Usage

```sh
bundle install                         # first time

# Preview / push the listing (asks before anything goes live):
bundle exec fastlane deliver

# Metadata only (no screenshots), or vice-versa:
bundle exec fastlane deliver --skip_screenshots
bundle exec fastlane deliver --skip_metadata

# Pull the current live listing down into these files:
bundle exec fastlane deliver download_metadata
bundle exec fastlane deliver download_screenshots
```

`Deliverfile` sets `submit_for_review false`, `automatic_release false`, and
`skip_binary_upload true` — it manages the listing text/images only and never
submits or releases on its own. Upload the build (`.ipa`) separately
(`pilot`/`deliver` with a binary, or Xcode/Transporter).

## TODO before first submission

- **Privacy URL**: `metadata/en-US/privacy_url.txt` points to
  `https://madeye.github.io/gterm/privacy/`, which does not exist yet. Either
  publish a privacy page there or change the URL. App Review requires a working
  privacy policy URL.
- **App Privacy "nutrition label"**: not expressible in these files — fill it in
  on App Store Connect (gterm stores SSH credentials/keys only in the on-device
  Keychain; the AI assistant sends prompt context to the user's configured
  provider with the user's own API key).
- **Screenshots**: the `APP_IPHONE_67` (6.9″) set is scaled from the 6.3″
  captures (aspect ratio differs ~0.3%). For pixel-perfect store images,
  recapture on an iPhone 16 Pro Max simulator at 1290×2796.
- Verify **category** (`DEVELOPER_TOOLS` / `UTILITIES`) and the localized copy.
