# E02.3 Account and shop preference isolation

Portable preferences belong to one authenticated account in one shop. The same account can choose a different appearance in a second shop. A different member in the same shop starts with their own settings. An account with no saved choice uses the default.

## Theme on web and Android

The web Appearance picker uses `GET` and `PUT /v1/shops/{shop_id}/preferences/theme` for the active paid workspace. Both responses contain `{ "theme": "system" | "light" | "dark" }`. The authenticated member supplies the owner identity through their session. Owner, admin and staff can edit their own selection. Theme defaults to System when there is no valid active row. A signed-out browser keeps its existing device preference separately from workspace choices.

Web and Android store the selection in the same `user_preferences` row for `app_theme_preference`. An explicit update can replace a previously deleted choice. Theme writes retain the existing row UUID and use the current sync timestamp ordering. Changing a preference does not change shared shop settings or the other members' choices.

## Android account handoff

Android applies the existing nine portable preference keys for the current account and shop. Missing, deleted and invalid values fall back to each setting's normal default. A previously saved offline preference can transfer during the first eligible local-shop upload. Switching accounts preserves the previous account's private rows and uses the destination scope for future writes and pulls. A late write must stay in its original scope or be rejected.

Device security, printer pairing, credentials and checkout ownership keep their existing storage. Android continues to support English and Hindi. Web translation and language selection remain a later slice.
