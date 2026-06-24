# lnu_elytra

https://github.com/mcitem/lnuElytra

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

```sh
# local.properties
RELEASE_STORE_FILE=
RELEASE_KEY_ALIAS=
RELEASE_STORE_PASSWORD=
RELEASE_KEY_PASSWORD=
```

```jsonc
// ohos.build-profile.json5
{
  "name": "default",
  "type": "HarmonyOS",
  "material": {
    "storeFile": "..",
    "storePassword": "..",
    "keyAlias": "..",
    "keyPassword": "..",
    "signAlg": "..",
    "profile": "..",
    "certpath": "..",
  },
}
```

```sh
fvm use hmos/3.35.8-ohos-1.0.1
```

```sh
fvm use stable
```

```sh
flutter --version
```
